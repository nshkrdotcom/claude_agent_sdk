# Rate Limiting & Circuit Breaking - Best Practices
## Application-Level Implementation Guide
## claude_code_sdk_elixir

---

## 🎯 Philosophy

**The SDK does not enforce rate limits or circuit breaking.** This is intentional.

**Why?**
- Apps know their usage patterns better than the SDK
- Different Claude tiers have different limits (60-1000 queries/min)
- Apps often have existing infrastructure (Plug, Oban, etc.)
- Flexibility > one-size-fits-all

**This guide shows you how to implement both using battle-tested Elixir libraries.**

---

## 🚦 Rate Limiting

### Why You Need It

```elixir
# Accidental abuse - rapid loop
1..10_000 |> Enum.each(fn i ->
  ClaudeCodeSDK.query("Query #{i}")  # ← Could hit API limits!
end)

# Concurrent orchestration
Orchestrator.query_parallel(500_queries)  # ← Could overwhelm API
```

**Without rate limiting**: API returns 429 errors, queries fail
**With rate limiting**: Controlled queueing, graceful degradation

### Recommended: Use Hammer

**Hammer** is the most flexible, production-ready rate limiter for Elixir.

#### Installation

```elixir
# mix.exs
defp deps do
  [
    {:claude_code_sdk, "~> 0.1.0"},
    {:hammer, "~> 6.1"}
  ]
end
```

#### Configuration

```elixir
# config/config.exs
config :hammer,
  backend: {Hammer.Backend.ETS, [
    expiry_ms: 60_000 * 60 * 2,  # 2 hours
    cleanup_interval_ms: 60_000 * 10  # 10 minutes
  ]}

# Or for distributed apps
config :hammer,
  backend: {Hammer.Backend.Redis, [
    expiry_ms: 60_000 * 60 * 2,
    redis_url: System.get_env("REDIS_URL")
  ]}
```

#### Basic Usage

```elixir
defmodule MyApp.Claude do
  @doc """
  Execute Claude query with rate limiting (60 queries/minute).
  """
  def query_with_limit(prompt, options \\ %{}) do
    bucket = "claude_api_global"
    scale_ms = 60_000  # 1 minute
    limit = 60  # 60 queries per minute

    case Hammer.check_rate(bucket, scale_ms, limit) do
      {:allow, _count} ->
        ClaudeCodeSDK.query(prompt, options) |> Enum.to_list()

      {:deny, retry_after_ms} ->
        {:error, {:rate_limited, "Retry after #{retry_after_ms}ms"}}
    end
  end
end
```

#### Advanced: Per-User Rate Limiting

```elixir
defmodule MyApp.Claude do
  @queries_per_user_per_minute 10

  def query_for_user(user_id, prompt, options \\ %{}) do
    bucket = "claude_user:#{user_id}"

    case Hammer.check_rate(bucket, 60_000, @queries_per_user_per_minute) do
      {:allow, count} ->
        Logger.info("User #{user_id} query #{count}/#{@queries_per_user_per_minute}")
        ClaudeCodeSDK.query(prompt, options) |> Enum.to_list()

      {:deny, retry_after_ms} ->
        Logger.warning("User #{user_id} rate limited, retry in #{retry_after_ms}ms")
        {:error, :rate_limited}
    end
  end
end
```

#### With Orchestrator

```elixir
defmodule MyApp.BulkAnalyzer do
  alias ClaudeCodeSDK.Orchestrator

  @rate_limit_per_minute 60

  def analyze_files(files, opts) do
    # Create queries
    queries = Enum.map(files, fn file ->
      {"Analyze #{file}", opts}
    end)

    # Rate-limited parallel execution
    queries
    |> Enum.chunk_every(@rate_limit_per_minute)
    |> Enum.flat_map(fn chunk ->
      # Execute chunk
      {:ok, results} = Orchestrator.query_parallel(chunk)

      # Wait 1 minute before next chunk
      if length(chunk) == @rate_limit_per_minute do
        Process.sleep(60_000)
      end

      results
    end)
  end
end
```

#### Cost Budgeting

```elixir
defmodule MyApp.CostLimiter do
  use GenServer

  # Track spending per hour
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{spent: 0.0, window_start: DateTime.utc_now()}, name: __MODULE__)
  end

  def check_budget(estimated_cost, max_hourly_budget \\ 10.0) do
    GenServer.call(__MODULE__, {:check_budget, estimated_cost, max_hourly_budget})
  end

  def handle_call({:check_budget, cost, max}, _from, state) do
    # Reset window if > 1 hour old
    state = maybe_reset_window(state)

    if state.spent + cost <= max do
      {:reply, :ok, %{state | spent: state.spent + cost}}
    else
      {:reply, {:error, :budget_exceeded}, state}
    end
  end

  defp maybe_reset_window(state) do
    if DateTime.diff(DateTime.utc_now(), state.window_start, :hour) >= 1 do
      %{spent: 0.0, window_start: DateTime.utc_now()}
    else
      state
    end
  end
end

# Usage
case MyApp.CostLimiter.check_budget(0.05) do  # Opus query ~$0.05
  :ok ->
    result = ClaudeCodeSDK.query(prompt, OptionBuilder.with_opus())
    # Track actual cost after
    cost = Session.calculate_cost(result)
    # Could adjust budget tracking here

  {:error, :budget_exceeded} ->
    Logger.warning("Hourly budget exceeded, skipping query")
    {:error, :budget_exceeded}
end
```

### Alternative: ExRated (Simpler)

If you don't need distributed rate limiting:

```elixir
# mix.exs
{:ex_rated, "~> 2.0"}

# Usage
defmodule MyApp.Claude do
  def query_with_limit(prompt) do
    case ExRated.check_rate("claude_api", 60_000, 60) do
      {:ok, _count} ->
        ClaudeCodeSDK.query(prompt) |> Enum.to_list()

      {:error, _limit} ->
        {:error, :rate_limited}
    end
  end
end
```

**Simpler but ETS-only (not distributed).**

---

## 🔌 Circuit Breaking

### Why You Need It

```elixir
# Claude API is down
ClaudeCodeSDK.query("test")  # ← Fails
ClaudeCodeSDK.query("test")  # ← Fails
ClaudeCodeSDK.query("test")  # ← Fails
# ... keeps trying, wastes time/money
```

**With circuit breaker**: After N failures, stop trying (circuit "opens"), fail fast

### Recommended: Use :fuse

**:fuse** is a mature Erlang circuit breaker, battle-tested in production.

#### Installation

```elixir
# mix.exs
defp deps do
  [
    {:fuse, "~> 2.5"}
  ]
end

# Add to applications
def application do
  [
    extra_applications: [:logger, :fuse]  # ← Add :fuse
  ]
end
```

#### Configuration

```elixir
# In your application start
defmodule MyApp.Application do
  def start(_type, _args) do
    # Install fuse for Claude API
    :fuse.install(:claude_api, {
      {:standard, 5, 60_000},  # Allow 5 failures in 60 seconds
      {:reset, 60_000}         # Auto-reset after 60 seconds
    })

    children = [
      # ... your children
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

#### Basic Usage

```elixir
defmodule MyApp.Claude do
  def query_with_circuit_breaker(prompt, options \\ %{}) do
    case :fuse.ask(:claude_api, :sync) do
      :ok ->
        # Circuit closed, try query
        try do
          result = ClaudeCodeSDK.query(prompt, options) |> Enum.to_list()

          # Check for errors in result
          if has_errors?(result) do
            :fuse.melt(:claude_api)  # Record failure
            {:error, :query_failed}
          else
            :fuse.reset(:claude_api)  # Record success
            {:ok, result}
          end
        catch
          error ->
            :fuse.melt(:claude_api)  # Record failure
            {:error, error}
        end

      :blown ->
        # Circuit open, fail fast
        {:error, :circuit_breaker_open}

      {:error, :not_found} ->
        # Fuse not installed
        {:error, :circuit_breaker_not_configured}
    end
  end

  defp has_errors?(messages) do
    Enum.any?(messages, fn msg ->
      msg.type == :result && msg.subtype != :success
    end)
  end
end
```

#### With Retry Logic

```elixir
defmodule MyApp.Claude do
  def query_with_resilience(prompt, opts \\ %{}) do
    # Combine circuit breaker + retry
    case :fuse.ask(:claude_api, :sync) do
      :ok ->
        Orchestrator.query_with_retry(prompt, opts,
          max_retries: 3,
          backoff_ms: 1000
        )
        |> handle_result()

      :blown ->
        {:error, :service_degraded}
    end
  end

  defp handle_result({:ok, messages}) do
    :fuse.reset(:claude_api)
    {:ok, messages}
  end

  defp handle_result({:error, reason}) do
    :fuse.melt(:claude_api)
    {:error, reason}
  end
end
```

#### Monitoring Circuit State

```elixir
defmodule MyApp.ClaudeMonitor do
  def check_circuit_health do
    case :fuse.ask(:claude_api, :sync) do
      :ok ->
        %{status: :healthy, circuit: :closed}

      :blown ->
        # Circuit open - service degraded
        %{status: :degraded, circuit: :open}

      {:error, :not_found} ->
        %{status: :unknown, circuit: :not_configured}
    end
  end

  def get_circuit_stats do
    # Get detailed stats if available
    case :fuse.circuit_state(:claude_api) do
      {:ok, state} -> state
      _ -> :not_available
    end
  end
end
```

### Alternative: Custom Simple Circuit Breaker

If you don't want dependencies:

```elixir
defmodule MyApp.SimpleCircuitBreaker do
  use GenServer

  # State: :closed, :open, :half_open
  defstruct state: :closed, failure_count: 0, last_failure: nil

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  def call(fun) do
    case GenServer.call(__MODULE__, :check_state) do
      :closed ->
        try do
          result = fun.()
          GenServer.cast(__MODULE__, :record_success)
          result
        catch
          error ->
            GenServer.cast(__MODULE__, :record_failure)
            raise error
        end

      :open ->
        {:error, :circuit_open}

      :half_open ->
        # Try one request
        try do
          result = fun.()
          GenServer.cast(__MODULE__, :record_success)
          result
        catch
          error ->
            GenServer.cast(__MODULE__, :record_failure)
            raise error
        end
    end
  end

  # GenServer implementation (~100 more lines)
  # See: https://martinfowler.com/bliki/CircuitBreaker.html
end
```

---

## 🏗️ Production Patterns

### Pattern 1: Phoenix Controller with Rate Limiting

```elixir
defmodule MyAppWeb.ClaudeController do
  use MyAppWeb, :controller

  plug :rate_limit when action in [:analyze, :generate]

  def analyze(conn, %{"code" => code}) do
    case MyApp.Claude.query_with_limit("Analyze: #{code}") do
      {:ok, result} ->
        json(conn, %{analysis: extract_text(result)})

      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> json(%{error: "Rate limit exceeded. Try again later."})
    end
  end

  defp rate_limit(conn, _opts) do
    user_id = get_session(conn, :user_id)

    case Hammer.check_rate("user:#{user_id}", 60_000, 10) do
      {:allow, _} ->
        conn

      {:deny, _} ->
        conn
        |> put_status(429)
        |> json(%{error: "Rate limit exceeded"})
        |> halt()
    end
  end
end
```

### Pattern 2: Background Job with Circuit Breaker

```elixir
defmodule MyApp.Workers.CodeReview do
  use Oban.Worker, max_attempts: 3

  def perform(%{args: %{"code" => code}}) do
    case :fuse.ask(:claude_api, :sync) do
      :ok ->
        execute_review(code)

      :blown ->
        # Circuit open - reschedule for later
        {:snooze, 60}  # Retry in 60 seconds
    end
  end

  defp execute_review(code) do
    try do
      result = ClaudeCodeSDK.query("Review: #{code}")
      |> Enum.to_list()

      :fuse.reset(:claude_api)
      {:ok, result}
    catch
      error ->
        :fuse.melt(:claude_api)
        {:error, error}
    end
  end
end
```

### Pattern 3: Orchestrator with Budget Control

```elixir
defmodule MyApp.BulkProcessor do
  alias ClaudeCodeSDK.{Orchestrator, Session}

  def process_with_budget(queries, max_cost_usd \\ 5.0) do
    # Track cost as we go
    {results, total_cost} = Enum.reduce_while(queries, {[], 0.0}, fn query, {results, cost} ->
      if cost >= max_cost_usd do
        Logger.warning("Budget limit reached: $#{cost}")
        {:halt, {results, cost}}
      else
        # Execute query
        {:ok, [result]} = Orchestrator.query_parallel([query], max_concurrent: 1)

        new_cost = cost + result.cost

        {:cont, {[result | results], new_cost}}
      end
    end)

    Logger.info("Processed #{length(results)} queries, cost: $#{total_cost}")

    {:ok, Enum.reverse(results), total_cost}
  end
end
```

### Pattern 4: Combined Rate Limit + Circuit Breaker + Retry

```elixir
defmodule MyApp.ResilientClaude do
  @doc """
  Production-grade Claude query with all protections:
  - Rate limiting (60/min)
  - Circuit breaking (5 failures = open)
  - Retry with backoff (3 attempts)
  - Cost tracking
  """
  def query(prompt, options \\ %{}) do
    with :ok <- check_rate_limit(),
         :ok <- check_circuit_breaker(),
         {:ok, result} <- execute_with_retry(prompt, options),
         :ok <- record_success() do
      {:ok, result}
    else
      {:error, :rate_limited} = error ->
        Logger.warning("Rate limit exceeded")
        error

      {:error, :circuit_open} = error ->
        Logger.error("Circuit breaker open - service degraded")
        error

      {:error, reason} = error ->
        record_failure()
        Logger.error("Query failed: #{inspect(reason)}")
        error
    end
  end

  defp check_rate_limit do
    case Hammer.check_rate("claude_global", 60_000, 60) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  defp check_circuit_breaker do
    case :fuse.ask(:claude_api, :sync) do
      :ok -> :ok
      :blown -> {:error, :circuit_open}
      {:error, _} -> :ok  # Fuse not configured, allow
    end
  end

  defp execute_with_retry(prompt, options) do
    Orchestrator.query_with_retry(prompt, options,
      max_retries: 3,
      backoff_ms: 1000
    )
  end

  defp record_success, do: :fuse.reset(:claude_api)
  defp record_failure, do: :fuse.melt(:claude_api)
end
```

---

## 📊 Rate Limit Guidelines by Tier

### Free Tier (~60 queries/minute)

```elixir
config :my_app,
  claude_rate_limit: [
    queries_per_minute: 50,  # Conservative (10 buffer)
    queries_per_hour: 1000,
    cost_per_hour: 1.0  # ~$1/hour limit
  ]
```

### Pro Tier (~1000 queries/minute)

```elixir
config :my_app,
  claude_rate_limit: [
    queries_per_minute: 900,  # 100 buffer
    queries_per_hour: 10_000,
    cost_per_hour: 50.0
  ]
```

### Enterprise (Custom)

```elixir
# Contact Anthropic for your limits
config :my_app,
  claude_rate_limit: [
    queries_per_minute: 5000,
    queries_per_hour: 100_000,
    cost_per_hour: 1000.0
  ]
```

---

## 🎓 Advanced Patterns

### Pattern: Adaptive Rate Limiting

```elixir
defmodule MyApp.AdaptiveRateLimiter do
  @moduledoc """
  Adjusts rate limit based on error responses.

  If getting 429s, slow down.
  If succeeding, speed up (within limits).
  """

  use GenServer

  defstruct current_limit: 60, min_limit: 30, max_limit: 100

  def query(prompt) do
    limit = GenServer.call(__MODULE__, :get_current_limit)

    case Hammer.check_rate("claude_adaptive", 60_000, limit) do
      {:allow, _} ->
        result = ClaudeCodeSDK.query(prompt) |> Enum.to_list()

        # Adjust based on result
        if got_rate_limited?(result) do
          GenServer.cast(__MODULE__, :decrease_limit)
        else
          GenServer.cast(__MODULE__, :increase_limit)
        end

        {:ok, result}

      {:deny, _} ->
        {:error, :rate_limited}
    end
  end

  defp got_rate_limited?(messages) do
    Enum.any?(messages, fn msg ->
      case msg do
        %{type: :assistant, data: %{message: %{"content" => content}}} ->
          String.contains?(content, "429") || String.contains?(content, "rate limit")

        _ ->
          false
      end
    end)
  end

  # GenServer callbacks to adjust limit dynamically...
end
```

### Pattern: Priority Queuing

```elixir
defmodule MyApp.PriorityQueue do
  @moduledoc """
  Different rate limits for different priority levels.
  """

  def query(prompt, priority \\ :normal) do
    {bucket, limit} = case priority do
      :critical -> {"claude_critical", 100}  # Higher limit
      :normal -> {"claude_normal", 60}
      :low -> {"claude_low", 30}
    end

    case Hammer.check_rate(bucket, 60_000, limit) do
      {:allow, _} -> ClaudeCodeSDK.query(prompt) |> Enum.to_list()
      {:deny, _} -> {:error, :rate_limited}
    end
  end
end
```

---

## 🔧 Library Comparison

### Rate Limiting

| Library | Stars | Distributed | Backend | Complexity | Best For |
|---------|-------|-------------|---------|------------|----------|
| **hammer** | 700+ | ✅ Yes | ETS, Redis, Mnesia | Medium | Production apps |
| **ex_rated** | 400+ | ❌ ETS only | ETS | Low | Simple apps |
| **plug_attack** | 300+ | ✅ Yes | Pluggable | Medium | Phoenix apps |
| **Custom** | - | Your choice | Your code | High | Learning |

**Recommendation**: **hammer** (most flexible, production-ready)

### Circuit Breaking

| Library | Stars | Maturity | API | Best For |
|---------|-------|----------|-----|----------|
| **:fuse** | 400+ | ✅ Erlang/OTP | Erlang | Production |
| **breaker** | 50+ | 🟡 Elixir wrapper | Elixir-friendly | Simpler API |
| **Tesla.Middleware.Fuse** | - | ✅ Production | Tesla-specific | HTTP clients |
| **Custom** | - | ❌ Untested | Your design | Learning |

**Recommendation**: **:fuse** (most mature, proven)

---

## 🎯 Summary & Recommendations

### What SDK Should Do: NOTHING (Almost)

**Don't**:
- ❌ Implement custom rate limiter
- ❌ Implement custom circuit breaker
- ❌ Enforce any limits by default
- ❌ Add these as required dependencies

**Do**:
- ✅ Document best practices (this guide)
- ✅ Provide example integrations
- ✅ Show patterns for Orchestrator
- ✅ Recommend hammer + :fuse

### What Applications Should Do

**Small apps / prototypes**:
```elixir
# No rate limiting needed
# Just use SDK directly
ClaudeCodeSDK.query(prompt)
```

**Production apps**:
```elixir
# Add hammer + :fuse
{:hammer, "~> 6.1"}
{:fuse, "~> 2.5"}

# Configure in application.ex
# Wrap SDK calls with rate limit + circuit breaker
```

**Phoenix apps**:
```elixir
# Use Plug.RateLimiter or hammer_plug
plug HammerPlug, [rate_limit: {"claude", 60_000, 60}]
```

**Background jobs**:
```elixir
# Oban already has retry
use Oban.Worker, max_attempts: 3

# Just add circuit breaker
:fuse.ask(:claude_api, :sync)
```

---

## 📋 Decision Matrix

### Should YOU implement rate limiting?

| Question | Answer | Action |
|----------|--------|--------|
| Production app? | Yes | ✅ Add hammer |
| Multiple users? | Yes | ✅ Per-user limits |
| Free tier? | Yes | ✅ Strict limits (50/min) |
| Pro/Enterprise? | Yes | 🟡 Looser limits |
| Prototype? | Yes | ❌ Skip it |

### Should YOU implement circuit breaking?

| Question | Answer | Action |
|----------|--------|--------|
| Production app? | Yes | ✅ Add :fuse |
| Calling from web requests? | Yes | ✅ Fail fast needed |
| Background jobs? | Yes | ✅ Prevent cascading failures |
| Using Orchestrator heavily? | Yes | ✅ Protect against API issues |
| Prototype? | Yes | ❌ Skip it |

---

## 🚀 Quick Start Templates

### Template 1: Minimal Protection

```elixir
# mix.exs
{:hammer, "~> 6.1"}

# lib/my_app/claude.ex
defmodule MyApp.Claude do
  def query(prompt) do
    case Hammer.check_rate("claude", 60_000, 60) do
      {:allow, _} ->
        ClaudeCodeSDK.query(prompt) |> Enum.to_list()

      {:deny, retry_ms} ->
        {:error, {:rate_limited, retry_ms}}
    end
  end
end
```

### Template 2: Full Production Setup

```elixir
# mix.exs
{:hammer, "~> 6.1"}
{:fuse, "~> 2.5"}

# lib/my_app/application.ex
def start(_type, _args) do
  # Install circuit breaker
  :fuse.install(:claude_api, {
    {:standard, 5, 60_000},
    {:reset, 60_000}
  })

  # ... start supervisors
end

# lib/my_app/claude.ex
defmodule MyApp.Claude do
  alias ClaudeCodeSDK.Orchestrator

  def query(prompt, opts \\ %{}) do
    with :ok <- check_rate_limit(),
         :ok <- check_circuit(),
         {:ok, result} <- execute_query(prompt, opts) do
      :fuse.reset(:claude_api)
      {:ok, result}
    end
  end

  defp check_rate_limit do
    case Hammer.check_rate("claude", 60_000, 60) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  defp check_circuit do
    case :fuse.ask(:claude_api, :sync) do
      :ok -> :ok
      :blown -> {:error, :circuit_open}
    end
  end

  defp execute_query(prompt, opts) do
    try do
      Orchestrator.query_with_retry(prompt, opts, max_retries: 2)
    catch
      error ->
        :fuse.melt(:claude_api)
        {:error, error}
    end
  end
end
```

---

## 📚 Further Reading

- [Hammer Documentation](https://hexdocs.pm/hammer)
- [ExRated Documentation](https://hexdocs.pm/ex_rated)
- [:fuse Documentation](https://hexdocs.pm/fuse)
- [Circuit Breaker Pattern (Martin Fowler)](https://martinfowler.com/bliki/CircuitBreaker.html)
- [Rate Limiting Strategies](https://cloud.google.com/architecture/rate-limiting-strategies)

---

## ❓ FAQ

**Q: Why doesn't SDK enforce limits by default?**
A: Apps know their tier (free/pro/enterprise) and usage patterns better than SDK.

**Q: What if I don't add rate limiting?**
A: SDK works fine. You might hit API limits under heavy load (429 errors).

**Q: Should I use hammer or ex_rated?**
A: hammer if you need distributed, ex_rated if single-node is fine.

**Q: Is :fuse really better than custom circuit breaker?**
A: Yes. It's Erlang/OTP, battle-tested, and proven. Don't reinvent.

**Q: Can I use Orchestrator without rate limiting?**
A: Yes! Just be careful with `max_concurrent` to avoid overwhelming API.

---

**Conclusion**: Rate limiting and circuit breaking are **application concerns**, not SDK concerns. Use hammer + :fuse, they're excellent.

**SDK's job**: Provide reliable API access. Your job: Decide how to limit it.
