# Rate Limiting & Circuit Breaking - Architecture Analysis
## Should SDK Implement These or Let Applications Handle?
## Date: 2025-10-07

---

## 🎯 The Core Question

**Should `claude_code_sdk_elixir` implement rate limiting and circuit breaking, or is this application-level concern?**

---

## 📊 Arguments FOR SDK Implementation

### Pro #1: Protect Against Accidental Abuse
```elixir
# Developer mistake - rapid loop
1..1000 |> Enum.each(fn i ->
  ClaudeCodeSDK.query("Query #{i}")  # ← Could hit API limits!
end
```

**SDK rate limiting prevents this automatically.**

### Pro #2: Consistent Behavior Across Applications
- Every app using the SDK gets protection
- Standardized error messages
- Predictable behavior
- Less for app developers to remember

### Pro #3: SDK Knows API Constraints Best
- We know Claude API limits (queries/min, cost/hour)
- Can encode best practices
- Can update limits when API changes
- Application developers don't need to research this

### Pro #4: Works with Orchestrator
```elixir
# Orchestrator.query_parallel already needs rate limiting
Orchestrator.query_parallel(100_queries)  # Could overwhelm API
```

Built-in limiting makes Orchestrator safer.

---

## 📊 Arguments AGAINST SDK Implementation

### Con #1: Application May Have Better Context
```elixir
# Application knows its usage patterns
defmodule MyApp.ClaudeService do
  # We only run 10 queries/hour total
  # SDK limiting at 60/min is too generous
  # OR
  # We need bursts of 100 queries, then quiet periods
  # SDK limiting at 60/min is too restrictive
end
```

**Application-level limiting can be more intelligent.**

### Con #2: Multiple Integration Patterns
```elixir
# Phoenix app
defmodule MyAppWeb.ClaudeController do
  plug :rate_limit_per_user  # Already has Plug.RateLimiter

  def analyze(conn, params) do
    # Don't need SDK-level limiting here
  end
end

# Background job
defmodule MyApp.Worker do
  use Oban.Worker, max_attempts: 3  # Already has retry

  def perform(%{prompt: prompt}) do
    # Don't need SDK circuit breaker here
  end
end
```

**Apps often have their own infrastructure.**

### Con #3: One Size Doesn't Fit All
- Free tier: 60 queries/min
- Pro tier: 1000 queries/min
- Enterprise: Custom limits
- AWS Bedrock: Different limits entirely

**SDK can't know which tier you're on.**

### Con #4: Elixir Ecosystem Has Better Libraries

**Rate Limiting**:
- `ex_rated` - Battle-tested, Redis-backed
- `hammer` - Distributed, pluggable backends
- `plug_attack` - HTTP-specific

**Circuit Breaking**:
- `fuse` - Erlang circuit breaker (mature)
- `breaker` - Elixir-friendly wrapper
- `circuit_breaker` - Simple implementation

**These are mature, well-tested, and flexible.**

---

## 🔍 Deep Dive: Existing Elixir Libraries

### Rate Limiting Options

#### Option 1: `ex_rated` (Most Popular)
```elixir
# Pros:
✅ Battle-tested (1000+ stars)
✅ Redis or ETS backends
✅ Simple API
✅ Per-user, per-endpoint limits

# Cons:
❌ Requires Redis for distributed
❌ Synchronous checks (small latency)

# Integration:
{:ex_rated, "~> 2.0"}

defmodule ClaudeCodeSDK.RateLimiter do
  def check_limit(identifier) do
    case ExRated.check_rate(identifier, 60_000, 60) do  # 60/min
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, :rate_limited}
    end
  end
end
```

#### Option 2: `hammer` (Most Flexible)
```elixir
# Pros:
✅ Pluggable backends (ETS, Redis, Mnesia)
✅ Distributed-ready
✅ Token bucket algorithm
✅ Better for complex scenarios

# Cons:
❌ More complex API
❌ Heavier dependency

# Integration:
{:hammer, "~> 6.0"}

defmodule ClaudeCodeSDK.RateLimiter do
  def check_limit do
    case Hammer.check_rate("claude_api", 60_000, 60) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end
end
```

#### Option 3: Custom (Lightweight)
```elixir
# Pros:
✅ No dependencies
✅ Full control
✅ Exactly what we need
✅ ~100 lines of code

# Cons:
❌ We maintain it
❌ Not battle-tested
❌ Reinventing wheel

# From our plan:
defmodule ClaudeCodeSDK.RateLimiter do
  use GenServer
  # Token bucket with ETS
end
```

### Circuit Breaker Options

#### Option 1: `:fuse` (Erlang, Most Mature)
```elixir
# Pros:
✅ Erlang/OTP (rock solid)
✅ Used in production everywhere
✅ Three-state circuit breaker
✅ Configurable thresholds

# Cons:
❌ Erlang API (less Elixir-friendly)
❌ Global state

# Integration:
{:fuse, "~> 2.5"}

:fuse.install(:claude_api, {{:standard, 5, 60_000}, {:reset, 60_000}})

case :fuse.ask(:claude_api, :sync) do
  :ok -> execute_query()
  :blown -> {:error, :circuit_open}
end
```

#### Option 2: `breaker` (Elixir Wrapper)
```elixir
# Pros:
✅ Elixir-friendly API
✅ Wraps :fuse
✅ Simple to use

# Cons:
❌ Thin wrapper (minimal value add)
❌ Less flexible than raw :fuse

# Integration:
{:breaker, "~> 0.1"}

Breaker.call(:claude_api, fn ->
  ClaudeCodeSDK.query(prompt)
end)
```

#### Option 3: Custom (GenServer)
```elixir
# Pros:
✅ Simple, focused
✅ Full control
✅ ~150 lines

# Cons:
❌ Reinventing wheel
❌ :fuse is better tested
```

---

## 💡 My Recommendation

### **Use Existing Libraries + Make Them Optional**

**Best Approach**:

```elixir
# 1. SDK provides OPTIONAL integration
defmodule ClaudeCodeSDK.RateLimiting do
  @moduledoc """
  Optional rate limiting integration.

  Supports multiple backends:
  - :none (default) - No rate limiting
  - :ex_rated - Use ex_rated library
  - :hammer - Use hammer library
  - :custom - Provide your own module
  """

  def check_limit(backend \\ :none) do
    case backend do
      :none -> :ok
      :ex_rated -> check_with_ex_rated()
      :hammer -> check_with_hammer()
      module when is_atom(module) -> module.check_rate_limit()
    end
  end
end

# 2. Application configures it
config :claude_code_sdk,
  rate_limiting: :ex_rated,  # or :none, :hammer, MyApp.CustomLimiter
  rate_limit_config: [
    queries_per_minute: 60,
    backend_config: %{bucket: "claude_api"}
  ]

# 3. SDK checks before executing
defmodule ClaudeCodeSDK.Process do
  defp stream_real(args, options, stdin) do
    # Check rate limit if configured
    case check_rate_limit() do
      :ok ->
        # Proceed with query
        Stream.resource(...)

      {:error, :rate_limited} ->
        raise RateLimitError, "Rate limit exceeded. Try again later."
    end
  end
end
```

### Why This Is Best:

✅ **Flexible**: Apps can choose their backend
✅ **Optional**: Default is no limiting (backward compatible)
✅ **Leverages ecosystem**: Use battle-tested libraries
✅ **Simple**: SDK provides integration points, not implementation
✅ **Maintainable**: We don't maintain complex limiting logic

---

## 🎯 Specific Recommendations

### Rate Limiting: **Use hammer + make it optional**

```elixir
# mix.exs
def deps do
  [
    {:hammer, "~> 6.0", optional: true}  # ← Optional!
  ]
end

# lib/claude_code_sdk/rate_limiter.ex
defmodule ClaudeCodeSDK.RateLimiter do
  def check_limit do
    case Application.get_env(:claude_code_sdk, :rate_limiting) do
      nil -> :ok  # No limiting
      :disabled -> :ok

      config when is_map(config) ->
        backend = config[:backend] || :hammer
        apply_rate_limit(backend, config)
    end
  end

  defp apply_rate_limit(:hammer, config) do
    if Code.ensure_loaded?(Hammer) do
      # Use hammer
      bucket = config[:bucket] || "claude_sdk"
      limit = config[:queries_per_minute] || 60

      case Hammer.check_rate(bucket, 60_000, limit) do
        {:allow, _count} -> :ok
        {:deny, _retry_after} -> {:error, :rate_limited}
      end
    else
      # hammer not available, skip
      :ok
    end
  end

  defp apply_rate_limit(module, config) when is_atom(module) do
    # Custom module
    module.check_rate_limit(config)
  end
end
```

**Benefits**:
- Apps that need it can add `hammer` dependency
- Apps that don't need it pay zero cost
- SDK provides clean integration point
- Flexible for different use cases

### Circuit Breaking: **Use :fuse + make it optional**

```elixir
# Same pattern - optional dependency
def deps do
  [
    {:fuse, "~> 2.5", optional: true}
  ]
end

defmodule ClaudeCodeSDK.CircuitBreaker do
  def call(fun) do
    case Application.get_env(:claude_code_sdk, :circuit_breaker) do
      nil -> fun.()  # No circuit breaking

      config ->
        apply_circuit_breaker(config, fun)
    end
  end

  defp apply_circuit_breaker(config, fun) do
    if Code.ensure_loaded?(:fuse) do
      name = config[:name] || :claude_sdk

      case :fuse.ask(name, :sync) do
        :ok ->
          try do
            result = fun.()
            :fuse.reset(name)  # Record success
            result
          catch
            error ->
              :fuse.melt(name)  # Record failure
              raise error
          end

        :blown ->
          {:error, :circuit_open}
      end
    else
      fun.()  # :fuse not available
    end
  end
end
```

---

## 🤔 What About "Just Config Options"?

**You suggested**: Maybe just expose configuration?

**Example**:
```elixir
# Option A: SDK implements, apps configure
config :claude_code_sdk,
  rate_limit: %{queries_per_minute: 60},
  circuit_breaker: %{failure_threshold: 5}

# Option B: SDK provides hooks, apps implement
config :claude_code_sdk,
  before_query: &MyApp.RateLimiter.check/0,
  on_error: &MyApp.CircuitBreaker.record_failure/1
```

**Analysis**:

| Approach | Pros | Cons |
|----------|------|------|
| **SDK implements** | Simple for users, consistent | Inflexible, one-size-fits-all |
| **SDK integrates libraries** | Best of both worlds | Requires optional deps |
| **SDK provides hooks** | Maximum flexibility | Users must implement |
| **Apps handle entirely** | No SDK complexity | Every app reinvents wheel |

**Verdict**: **SDK integrates libraries (Option B)** is best.

---

## 🏗️ Proposed Architecture

### Minimal SDK Code (~200 lines total)

```elixir
# lib/claude_code_sdk/middleware.ex
defmodule ClaudeCodeSDK.Middleware do
  @moduledoc """
  Optional middleware for rate limiting and circuit breaking.

  Configure in config.exs:

      config :claude_code_sdk,
        rate_limiting: [
          backend: :hammer,  # or :ex_rated, or YourModule
          queries_per_minute: 60
        ],
        circuit_breaker: [
          backend: :fuse,  # or YourModule
          failure_threshold: 5,
          timeout_ms: 60_000
        ]

  Dependencies (optional):
      {:hammer, "~> 6.0", optional: true}
      {:fuse, "~> 2.5", optional: true}
  """

  def before_query do
    with :ok <- check_rate_limit(),
         :ok <- check_circuit_breaker() do
      :ok
    end
  end

  def after_query(:ok), do: record_success()
  def after_query({:error, _}), do: record_failure()

  # Delegates to configured backends...
end

# lib/claude_code_sdk/process.ex (integration)
defp stream_real(args, options, stdin) do
  # Only check if middleware configured
  if middleware_enabled?() do
    :ok = ClaudeCodeSDK.Middleware.before_query()
  end

  result = Stream.resource(...)

  if middleware_enabled?() do
    ClaudeCodeSDK.Middleware.after_query(result)
  end

  result
end
```

**Total new code**: ~200 lines
**Complexity**: Low (mostly delegation)
**Dependencies**: 2 optional libs

---

## 🎓 Comparison: Custom vs Libraries

### Rate Limiting

| Feature | Custom (~150 lines) | hammer | ex_rated |
|---------|---------------------|--------|----------|
| **Token bucket** | ✅ We implement | ✅ Built-in | ✅ Built-in |
| **Distributed** | ❌ Single node | ✅ Redis/Mnesia | ✅ Redis |
| **Mature** | ❌ Untested | ✅ Production | ✅ Production |
| **Flexible** | ✅ Our rules | ✅ Very | 🟡 Moderate |
| **Maintenance** | ❌ We maintain | ✅ Community | ✅ Community |

**Winner**: hammer (if distributed) or ex_rated (simpler)

### Circuit Breaking

| Feature | Custom (~150 lines) | :fuse | Tesla.Middleware |
|---------|---------------------|-------|------------------|
| **3-state CB** | ✅ We implement | ✅ Built-in | ✅ Built-in |
| **Mature** | ❌ Untested | ✅ Erlang/OTP | ✅ Production |
| **Simple API** | ✅ Our design | 🟡 Erlang API | ✅ Elixir-friendly |
| **Standalone** | ✅ Yes | ✅ Yes | ❌ Needs Tesla |

**Winner**: :fuse (most mature, proven)

---

## 💰 Cost/Benefit Analysis

### Option A: Implement Custom (~300 lines)

**Effort**: 1.5 days (from plan)
**Maintenance**: Ongoing (edge cases, bugs)
**Flexibility**: Perfect fit for SDK
**Risk**: Untested in production

**Total cost**: 1.5 days + ongoing maintenance

### Option B: Integrate Libraries (~200 lines)

**Effort**: 4 hours (just integration code)
**Maintenance**: Minimal (libraries handle it)
**Flexibility**: Apps choose backend
**Risk**: Low (mature libraries)

**Total cost**: 4 hours + trivial maintenance

### Option C: Provide Hooks Only (~50 lines)

**Effort**: 2 hours
**Maintenance**: None
**Flexibility**: Apps fully control
**Risk**: None (apps handle implementation)

**Total cost**: 2 hours

### Option D: Do Nothing

**Effort**: 0 hours
**Maintenance**: None
**Flexibility**: Apps do what they want
**Risk**: Some apps might not implement (but is that our problem?)

**Total cost**: 0 hours

---

## 🎯 My Recommendation

### **Option B: Integrate Libraries (Optional)**

**Implementation**:

1. **Add optional dependencies**:
```elixir
# mix.exs
{:hammer, "~> 6.0", optional: true},
{:fuse, "~> 2.5", optional: true}
```

2. **Create integration module** (~200 lines):
```elixir
# lib/claude_code_sdk/middleware.ex
# - Checks if libraries are loaded
# - Delegates to them if present
# - Skips if not configured
# - Provides sensible defaults
```

3. **Document clearly**:
```markdown
## Rate Limiting (Optional)

The SDK supports optional rate limiting via popular Elixir libraries.

### Setup

```elixir
# 1. Add hammer to your deps
{:hammer, "~> 6.0"}

# 2. Configure
config :claude_code_sdk,
  rate_limiting: [
    backend: :hammer,
    queries_per_minute: 60
  ]

# 3. SDK automatically enforces limits
ClaudeCodeSDK.query(...)  # Rate limited!
```

### Without Rate Limiting

Don't add hammer to deps - SDK works normally.
```

**Effort**: 4 hours (vs 1.5 days for custom)
**Value**: Same protection, better flexibility
**Maintenance**: Minimal

---

## 🚀 Revised Plan

### DON'T Build Custom

Skip `docs/20251007/04_RATE_LIMITING_CIRCUIT_BREAKING_PLAN.md` custom implementation.

### DO Build Integration

**New approach**:
1. Add optional deps (5 min)
2. Create Middleware module (3 hours)
3. Integrate with Process.ex (30 min)
4. Document (30 min)
5. Examples (30 min)

**Total**: 4-5 hours (vs 1.5 days)

---

## 📋 Specific Implementation

### Phase 1: Add Dependencies
```elixir
# mix.exs
defp deps do
  [
    # ... existing deps
    {:hammer, "~> 6.1", optional: true},
    {:fuse, "~> 2.5", optional: true}
  ]
end
```

### Phase 2: Middleware Module
```elixir
# lib/claude_code_sdk/middleware.ex (~200 lines)
defmodule ClaudeCodeSDK.Middleware do
  # Rate limiting integration
  def check_rate_limit
  def supports_rate_limiting?

  # Circuit breaker integration
  def call_with_circuit_breaker(fun)
  def supports_circuit_breaking?

  # Configuration helpers
  def configure_rate_limit(backend, opts)
  def configure_circuit_breaker(opts)
end
```

### Phase 3: Integration Point
```elixir
# lib/claude_code_sdk/process.ex
defp stream_real(args, options, stdin) do
  if ClaudeCodeSDK.Middleware.enabled?() do
    ClaudeCodeSDK.Middleware.call_with_protection(fn ->
      Stream.resource(...)
    end)
  else
    Stream.resource(...)  # Direct execution
  end
end
```

### Phase 4: Documentation
- README section on optional middleware
- Config examples for hammer/:fuse
- Custom backend example
- Performance impact notes

---

## 🎯 Final Recommendation

**DO NOT implement custom rate limiting/circuit breaking.**

**INSTEAD**:

1. **Document patterns** for apps to handle it themselves
2. **Provide optional integration** with hammer/:fuse (4 hours work)
3. **Make it explicit** that apps can use their own infrastructure

**Rationale**:
- Apps often have existing infrastructure (Plug, Oban, etc.)
- Elixir ecosystem has mature solutions
- One-size-fits-all doesn't work (free vs pro vs enterprise tiers)
- 4 hours > 1.5 days, same value

**Next Steps**:

**Option A**: Skip middleware entirely, document patterns (2 hours)
**Option B**: Implement optional middleware (4 hours)
**Option C**: Move to next feature (sessions already done!)

**What do you prefer?**

---

**Analysis complete. Recommendation: Optional library integration, not custom implementation.**
