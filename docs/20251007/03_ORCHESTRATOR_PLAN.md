# Implementation Plan: Concurrent Orchestrator
## Priority: MUST-HAVE (Critical)
## Estimated Effort: 3 days
## Target Version: 0.1.0

---

## 🎯 Objective

Enable concurrent Claude query orchestration with rate limiting, error recovery, and workflow management for production-scale automation.

---

## 📋 Problem Statement

**Current**: Single-query, blocking execution
```elixir
# Can't do this efficiently
queries = ["Query 1", "Query 2", "Query 3"]
results = Enum.map(queries, &ClaudeAgentSDK.query/1)  # Sequential, slow
```

**Desired**: Parallel execution with control
```elixir
# Run multiple queries concurrently
results = ClaudeAgentSDK.Orchestrator.query_parallel([
  {"Analyze file1.ex", analysis_opts},
  {"Analyze file2.ex", analysis_opts},
  {"Analyze file3.ex", analysis_opts}
], max_concurrent: 3)

# Pipeline queries (output → input)
{:ok, final_result} = ClaudeAgentSDK.Orchestrator.query_pipeline([
  {"Analyze code", analysis_opts},
  {"Suggest refactorings", refactor_opts},
  {"Generate tests", test_opts}
])

# Retry with backoff
{:ok, result} = ClaudeAgentSDK.Orchestrator.query_with_retry(
  prompt,
  options,
  max_retries: 3,
  backoff_ms: 1000
)
```

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────┐
│ ClaudeAgentSDK.Orchestrator (GenServer)               │
├──────────────────────────────────────────────────────┤
│ • Rate limiting (queries/minute)                     │
│ • Concurrent execution management                    │
│ • Retry logic with exponential backoff               │
│ • Pipeline workflows                                 │
│ • Cost tracking and budgeting                        │
└──────────────────────────────────────────────────────┘
          │                │               │
    ┌─────▼────┐    ┌─────▼────┐    ┌────▼────┐
    │ Parallel │    │ Pipeline │    │  Retry  │
    │ Executor │    │ Executor │    │ Manager │
    └──────────┘    └──────────┘    └─────────┘
```

---

## 📁 Implementation

### Core Module

**File**: `lib/claude_agent_sdk/orchestrator.ex`

```elixir
defmodule ClaudeAgentSDK.Orchestrator do
  use GenServer
  require Logger

  @moduledoc """
  Concurrent query orchestration with rate limiting and error recovery.

  ## Features
  - Parallel query execution with concurrency limits
  - Sequential pipeline workflows
  - Automatic retry with exponential backoff
  - Rate limiting (configurable queries/minute)
  - Cost tracking and budget enforcement
  - Circuit breaking for fault tolerance

  ## Usage

      # Start orchestrator
      {:ok, _pid} = ClaudeAgentSDK.Orchestrator.start_link()

      # Parallel queries
      results = Orchestrator.query_parallel([
        {"Query 1", opts1},
        {"Query 2", opts2}
      ])

      # Pipeline
      {:ok, result} = Orchestrator.query_pipeline([
        {"Step 1", opts},
        {"Step 2", opts}
      ])
  """

  # Configuration
  @default_rate_limit 60  # queries per minute
  @default_max_concurrent 5
  @default_max_retries 3
  @default_backoff_ms 1000

  defstruct [
    :rate_limiter,        # RateLimiter state
    :circuit_breaker,     # CircuitBreaker state
    :stats,               # Usage statistics
    :budget               # Cost budget enforcement
  ]

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec query_parallel([{String.t(), Options.t()}], keyword()) ::
    {:ok, [result :: map()]} | {:error, term()}
  def query_parallel(queries, opts \\ []) do
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    timeout = Keyword.get(opts, :timeout, 300_000)

    queries
    |> Task.async_stream(
      fn {prompt, options} ->
        # Rate limit check
        :ok = check_rate_limit()

        # Budget check
        :ok = check_budget()

        # Execute query
        result = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

        # Track usage
        track_usage(result)

        %{
          prompt: prompt,
          messages: result,
          cost: extract_cost(result),
          session_id: extract_session_id(result),
          success: success?(result)
        }
      end,
      max_concurrency: max_concurrent,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.to_list()
    |> process_parallel_results()
  end

  @spec query_pipeline([{String.t(), Options.t()}], keyword()) ::
    {:ok, [Message.t()]} | {:error, term()}
  def query_pipeline(steps, opts \\ []) do
    use_context = Keyword.get(opts, :use_context, false)

    Enum.reduce_while(steps, {:ok, []}, fn {prompt, options}, {:ok, prev_result} ->
      :ok = check_rate_limit()

      enhanced_prompt = if use_context && prev_result != [] do
        append_context(prompt, prev_result)
      else
        prompt
      end

      result = ClaudeAgentSDK.query(enhanced_prompt, options) |> Enum.to_list()

      case extract_errors(result) do
        [] -> {:cont, {:ok, result}}
        errors -> {:halt, {:error, {:step_failed, prompt, errors}}}
      end
    end)
  end

  @spec query_with_retry(String.t(), Options.t(), keyword()) ::
    {:ok, [Message.t()]} | {:error, term()}
  def query_with_retry(prompt, options, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    backoff_ms = Keyword.get(opts, :backoff_ms, @default_backoff_ms)

    Enum.reduce_while(1..max_retries, nil, fn attempt, _acc ->
      Logger.info("Orchestrator: Query attempt #{attempt}/#{max_retries}")

      :ok = check_rate_limit()

      result = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

      case extract_errors(result) do
        [] ->
          {:halt, {:ok, result}}

        errors when attempt < max_retries ->
          Logger.warn("Attempt #{attempt} failed: #{inspect(errors)}, retrying...")
          Process.sleep(backoff_ms * attempt)  # Exponential backoff
          {:cont, nil}

        errors ->
          {:halt, {:error, {:max_retries_exceeded, errors}}}
      end
    end)
  end

  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @spec reset_stats() :: :ok
  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    rate_limit = Keyword.get(opts, :rate_limit, @default_rate_limit)

    state = %__MODULE__{
      rate_limiter: init_rate_limiter(rate_limit),
      circuit_breaker: init_circuit_breaker(),
      stats: init_stats(),
      budget: Keyword.get(opts, :budget_usd, nil)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:check_rate_limit, _from, state) do
    case check_rate_limit_internal(state.rate_limiter) do
      {:ok, new_limiter} ->
        {:reply, :ok, %{state | rate_limiter: new_limiter}}

      {:error, wait_ms} ->
        Logger.warn("Rate limit reached, waiting #{wait_ms}ms")
        Process.sleep(wait_ms)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    {:reply, :ok, %{state | stats: init_stats()}}
  end

  ## Private Helpers

  defp check_rate_limit do
    GenServer.call(__MODULE__, :check_rate_limit, 5000)
  end

  defp check_rate_limit_internal(limiter) do
    now = System.monotonic_time(:millisecond)
    window_duration = now - limiter.window_start

    limiter = if window_duration >= 60_000 do
      %{limiter | count: 0, window_start: now}
    else
      limiter
    end

    if limiter.count < limiter.limit do
      {:ok, %{limiter | count: limiter.count + 1}}
    else
      wait_ms = 60_000 - window_duration
      {:error, wait_ms}
    end
  end

  defp check_budget do
    # TODO: Implement budget checking
    :ok
  end

  defp track_usage(_result) do
    # TODO: Implement usage tracking
    :ok
  end

  defp init_rate_limiter(limit) do
    %{
      limit: limit,
      count: 0,
      window_start: System.monotonic_time(:millisecond)
    }
  end

  defp init_circuit_breaker do
    %{state: :closed, failure_count: 0, last_failure: nil}
  end

  defp init_stats do
    %{
      total_queries: 0,
      successful_queries: 0,
      failed_queries: 0,
      total_cost_usd: 0.0,
      total_duration_ms: 0,
      avg_cost_per_query: 0.0
    }
  end

  defp extract_cost(messages) do
    messages
    |> Enum.find(&(&1.type == :result))
    |> case do
      %{data: %{total_cost_usd: cost}} -> cost
      _ -> 0.0
    end
  end

  defp extract_session_id(messages) do
    messages
    |> Enum.find(&(&1.type == :system))
    |> case do
      %{data: %{session_id: id}} -> id
      _ -> nil
    end
  end

  defp extract_errors(messages) do
    messages
    |> Enum.filter(&(&1.type == :result && &1.subtype != :success))
    |> Enum.map(& &1.subtype)
  end

  defp success?(messages) do
    Enum.any?(messages, &(&1.type == :result && &1.subtype == :success))
  end

  defp process_parallel_results(task_results) do
    results = Enum.map(task_results, fn
      {:ok, result} -> result
      {:exit, reason} -> %{error: reason, success: false}
    end)

    if Enum.all?(results, & &1.success) do
      {:ok, results}
    else
      failures = Enum.filter(results, &(not &1.success))
      {:error, {:parallel_failures, failures}}
    end
  end

  defp append_context(prompt, previous_messages) do
    context = previous_messages
    |> List.last()
    |> ClaudeAgentSDK.ContentExtractor.extract_text()

    """
    Context from previous step:
    #{context}

    Now:
    #{prompt}
    """
  end
end
```

---

## 🧪 Testing

### Unit Tests

```elixir
defmodule ClaudeAgentSDK.OrchestratorTest do
  use ExUnit.Case

  setup do
    start_supervised!(ClaudeAgentSDK.Orchestrator)
    :ok
  end

  test "parallel queries execute concurrently" do
    queries = [
      {"Query 1", %Options{}},
      {"Query 2", %Options{}},
      {"Query 3", %Options{}}
    ]

    start_time = System.monotonic_time(:millisecond)
    {:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 3)
    duration = System.monotonic_time(:millisecond) - start_time

    assert length(results) == 3
    # Verify parallel execution (should be faster than sequential)
    assert duration < 10_000  # Adjust based on expected query time
  end

  test "pipeline passes context between steps" do
    steps = [
      {"Step 1", %Options{}},
      {"Step 2", %Options{}}
    ]

    {:ok, result} = Orchestrator.query_pipeline(steps, use_context: true)

    assert Enum.any?(result, &(&1.type == :assistant))
  end

  test "retry mechanism works" do
    # Mock failure followed by success
    prompt = "Test query"
    options = %Options{}

    {:ok, result} = Orchestrator.query_with_retry(prompt, options, max_retries: 3)

    assert Enum.any?(result, &(&1.type == :result))
  end

  test "rate limiting enforced" do
    # Execute queries that exceed rate limit
    # Verify waiting occurs
  end
end
```

---

## 📊 Success Criteria

- [ ] Parallel execution working (3-5x speedup)
- [ ] Rate limiting prevents API overload
- [ ] Retry logic recovers from transient failures
- [ ] Pipeline workflows preserve context
- [ ] Cost tracking accurate
- [ ] Circuit breaker prevents cascading failures
- [ ] Stats collection and reporting
- [ ] All tests passing

---

## ⏱️ Timeline

**Day 1**: Core implementation (8h)
**Day 2**: Testing and error handling (6h)
**Day 3**: Documentation and examples (4h)

**Total**: 18 hours (2.25 days)

---

**Status**: Ready for Implementation
**Dependencies**: None
**Risk**: Medium (complex concurrency patterns)
