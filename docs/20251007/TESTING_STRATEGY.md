# Comprehensive Testing Strategy
## Claude Code SDK for Elixir
## Date: 2025-10-07

---

## 🎯 Testing Philosophy

**Goals**:
1. **Confidence**: Ship with confidence that features work
2. **Speed**: Fast feedback loop for developers
3. **Coverage**: 95%+ coverage for critical paths
4. **Isolation**: Tests don't depend on external services (except integration tests)
5. **Documentation**: Tests serve as usage examples

---

## 📊 Test Pyramid

```
           /\
          /  \  End-to-End (5%)
         /    \  - Full workflow tests
        /------\  - Real CLI + API
       /        \ Integration (15%)
      /          \ - Module integration
     /            \ - Tagged :integration
    /--------------\ Unit (80%)
   /                \ - Pure functions
  /                  \ - Mocked dependencies
 /____________________\ - Fast (<1ms each)
```

---

## 🧪 Test Categories

### 1. Unit Tests (80% of tests)

**Characteristics**:
- Fast (<1ms per test)
- No external dependencies
- Use mocks for all I/O
- Test single function/module

**Example**:
```elixir
defmodule ClaudeCodeSDK.OptionsTest do
  use ExUnit.Case

  describe "to_args/1" do
    test "converts model to CLI args" do
      options = %Options{model: "opus"}
      args = Options.to_args(options)

      assert "--model" in args
      assert "opus" in args
    end

    test "handles nil model gracefully" do
      options = %Options{model: nil}
      args = Options.to_args(options)

      refute "--model" in args
    end
  end
end
```

**Coverage Target**: 100% for pure functions

---

### 2. Integration Tests (15% of tests)

**Characteristics**:
- Moderate speed (100ms - 5s)
- Tests module interactions
- May use real CLI (mocked API)
- Tagged `:integration`

**Example**:
```elixir
defmodule ClaudeCodeSDK.AuthIntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "AuthManager integrates with Process" do
    # Setup authentication
    {:ok, _token} = ClaudeCodeSDK.AuthManager.setup_token()

    # Verify Process can use authentication
    messages = ClaudeCodeSDK.query("Hello") |> Enum.to_list()

    assert Enum.any?(messages, &(&1.type == :assistant))
  end
end
```

**Coverage Target**: 90% for integration paths

---

### 3. End-to-End Tests (5% of tests)

**Characteristics**:
- Slow (5s - 30s)
- Real Claude CLI + API
- Real costs incurred
- Tagged `:expensive` and `:e2e`
- Run manually or in scheduled CI

**Example**:
```elixir
defmodule ClaudeCodeSDK.E2ETest do
  use ExUnit.Case

  @tag :e2e
  @tag :expensive
  test "complete workflow: auth → query → session → resume" do
    # 1. Authenticate
    {:ok, _token} = ClaudeCodeSDK.AuthManager.setup_token()

    # 2. Run query
    messages = ClaudeCodeSDK.query("Write a function to add two numbers")
    |> Enum.to_list()

    session_id = extract_session_id(messages)

    # 3. Save session
    :ok = SessionStore.save_session(session_id, messages)

    # 4. Resume session
    more_messages = ClaudeCodeSDK.resume(session_id, "Now add error handling")
    |> Enum.to_list()

    # 5. Verify continuity
    assert Enum.any?(more_messages, &(&1.type == :assistant))
  end
end
```

**Coverage Target**: 100% of critical user workflows

---

## 🏷️ Test Tags

### Standard Tags

```elixir
@tag :unit          # Fast, no I/O (default, no tag needed)
@tag :integration   # Module integration, uses mocks
@tag :e2e          # Full workflow, real API
@tag :expensive    # Makes real API calls (costs money)
@tag :slow         # Takes >5 seconds
@tag :skip         # Temporarily disabled
```

### CI Configuration

```elixir
# test/test_helper.exs

# Exclude expensive tests by default
ExUnit.configure(
  exclude: [:expensive, :e2e],
  timeout: 60_000
)

# Include integration tests in CI
if System.get_env("CI") do
  ExUnit.configure(exclude: [:expensive, :e2e, :skip])
end

# Enable all tests for nightly builds
if System.get_env("NIGHTLY_BUILD") do
  ExUnit.configure(exclude: [:skip])
end
```

### Running Tests

```bash
# Fast tests only (development)
mix test

# Include integration tests
mix test --include integration

# Run expensive tests (manual)
mix test --include expensive --include e2e

# Run specific test file
mix test test/claude_code_sdk/auth_manager_test.exs

# Run with coverage
mix test --cover
```

---

## 🎭 Mocking Strategy

### Mock System (Existing)

**When to use**:
- Unit tests for all modules
- Development without API calls
- Fast feedback loops

**Example**:
```elixir
# test/test_helper.exs
Application.put_env(:claude_code_sdk, :use_mock, true)
{:ok, _} = ClaudeCodeSDK.Mock.start_link()

# In tests
test "query returns mocked response" do
  ClaudeCodeSDK.Mock.set_response("hello", [
    %{"type" => "assistant", "message" => %{"content" => "Hello!"}}
  ])

  messages = ClaudeCodeSDK.query("hello") |> Enum.to_list()

  assert Enum.any?(messages, &(&1.type == :assistant))
end
```

### Mox (for Behaviors)

**When to use**:
- Testing plugins
- Testing storage backends
- Testing providers

**Example**:
```elixir
# Define behavior
defmodule ClaudeCodeSDK.Auth.Provider do
  @callback setup_token() :: {:ok, String.t(), DateTime.t()} | {:error, term()}
end

# Define mock
Mox.defmock(ClaudeCodeSDK.Auth.MockProvider, for: ClaudeCodeSDK.Auth.Provider)

# In tests
test "AuthManager uses provider" do
  expect(MockProvider, :setup_token, fn ->
    {:ok, "sk-test-token", DateTime.utc_now()}
  end)

  {:ok, token} = AuthManager.setup_token()
  assert token == "sk-test-token"
end
```

---

## 📈 Coverage Requirements

### Per Module

| Module Type | Coverage Target | Enforcement |
|-------------|----------------|-------------|
| **Core Logic** | 100% | CI blocks at <95% |
| **Integration** | 90% | CI warns at <80% |
| **Examples** | 50% | No enforcement |
| **Mix Tasks** | 80% | CI warns at <70% |

### Running Coverage

```bash
# Generate coverage report
mix test --cover

# Detailed HTML report
mix coveralls.html

# CI coverage check
mix coveralls --min-coverage 95
```

### Coverage Configuration

```elixir
# mix.exs
def project do
  [
    # ...
    test_coverage: [
      tool: ExCoveralls,
      minimum_coverage: 95,
      refuse_to_drop: true
    ],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.html": :test
    ]
  ]
end
```

---

## 🔄 Continuous Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/elixir.yml
name: Elixir CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Install dependencies
        run: mix deps.get

      - name: Run fast tests
        run: mix test --exclude integration --exclude expensive

      - name: Run integration tests
        run: mix test --only integration
        env:
          CI: true

      - name: Check coverage
        run: mix coveralls.json --min-coverage 95

      - name: Run dialyzer
        run: mix dialyzer

      - name: Run credo
        run: mix credo --strict

  nightly:
    runs-on: ubuntu-latest
    if: github.event_name == 'schedule'

    steps:
      # ... same setup as above

      - name: Run all tests including expensive
        run: mix test --include expensive --include e2e
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          NIGHTLY_BUILD: true
```

---

## 🧩 Property-Based Testing

### StreamData for AuthManager

```elixir
defmodule ClaudeCodeSDK.AuthManager.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "token always starts with sk-ant-api03-" do
    check all token <- generate_token() do
      assert String.starts_with?(token, "sk-ant-api03-")
      assert String.length(token) == 118  # Known format
    end
  end

  property "token refresh maintains validity" do
    check all initial_token <- generate_token() do
      # Setup with initial token
      AuthManager.set_token(initial_token)

      # Refresh
      {:ok, new_token} = AuthManager.refresh_token()

      # Both tokens should be valid format
      assert valid_token_format?(initial_token)
      assert valid_token_format?(new_token)

      # Tokens should be different
      assert initial_token != new_token
    end
  end
end
```

### StreamData for Orchestrator

```elixir
property "parallel queries complete in parallel time" do
  check all query_count <- integer(1..10),
            query_duration_ms <- integer(100..1000) do

    queries = for i <- 1..query_count do
      {"Query #{i}", %Options{}}
    end

    start_time = System.monotonic_time(:millisecond)
    {:ok, _results} = Orchestrator.query_parallel(queries)
    duration = System.monotonic_time(:millisecond) - start_time

    # Parallel execution should not take query_count * query_duration
    # Allow 20% overhead
    max_expected = query_duration_ms * 1.2

    assert duration < max_expected,
      "Expected parallel execution in ~#{max_expected}ms, took #{duration}ms"
  end
end
```

---

## 🎯 Test-Driven Development Workflow

### Red-Green-Refactor Cycle

1. **Red**: Write failing test
2. **Green**: Make it pass (simplest way)
3. **Refactor**: Improve code quality
4. **Repeat**

### Example: AuthManager Token Refresh

```elixir
# 1. RED - Write failing test
test "refreshes token before expiry" do
  # Setup token expiring in 1 second
  setup_expiring_token(1000)

  # Wait for refresh
  Process.sleep(2000)

  # Should have new token
  {:ok, new_token} = AuthManager.get_token()
  refute new_token == old_token  # FAILS - refresh not implemented
end

# 2. GREEN - Implement minimum code
defp schedule_refresh(state) do
  timer = Process.send_after(self(), :refresh_token, state.expiry_ms)
  %{state | refresh_timer: timer}
end

def handle_info(:refresh_token, state) do
  {:ok, new_token} = perform_token_setup()
  {:noreply, %{state | token: new_token}}
end

# 3. REFACTOR - Improve implementation
defp schedule_refresh(state) do
  # Cancel existing timer
  if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

  # Calculate refresh time (1 day before expiry)
  refresh_at = DateTime.add(state.expiry, -86_400, :second)
  refresh_ms = DateTime.diff(refresh_at, DateTime.utc_now(), :millisecond)
  refresh_ms = max(refresh_ms, 60_000)  # At least 1 minute

  timer = Process.send_after(self(), :refresh_token, refresh_ms)
  %{state | refresh_timer: timer}
end
```

---

## 🔬 Specialized Testing

### Load Testing

**Tool**: Custom Elixir load generator

```elixir
defmodule ClaudeCodeSDK.LoadTest do
  def run_load_test(queries_per_second, duration_seconds) do
    # Spawn workers
    workers = for _i <- 1..queries_per_second do
      spawn_link(fn -> query_worker(duration_seconds) end)
    end

    # Collect results
    Enum.map(workers, fn pid ->
      receive do
        {:result, ^pid, stats} -> stats
      end
    end)
  end

  defp query_worker(duration_seconds) do
    start_time = System.monotonic_time(:second)
    stats = execute_queries_until(start_time + duration_seconds, %{
      completed: 0,
      failed: 0,
      total_latency_ms: 0
    })

    send(parent(), {:result, self(), stats})
  end
end
```

**Run Load Test**:
```bash
# 100 QPS for 60 seconds
mix run -e 'ClaudeCodeSDK.LoadTest.run_load_test(100, 60)'
```

### Chaos Testing

**Simulate Failures**:

```elixir
defmodule ClaudeCodeSDK.ChaosTest do
  test "recovers from subprocess crash" do
    # Start query
    task = Task.async(fn ->
      ClaudeCodeSDK.query("Long task...")
    end)

    # Kill subprocess mid-query
    Process.sleep(100)
    subprocess_pid = find_claude_subprocess()
    Process.exit(subprocess_pid, :kill)

    # Should handle gracefully
    assert {:error, reason} = Task.await(task)
    assert reason =~ "subprocess"
  end

  test "circuit breaker opens after failures" do
    # Simulate 5 consecutive API failures
    for _i <- 1..5 do
      simulate_api_failure()
      assert {:error, _} = ClaudeCodeSDK.query("Test")
    end

    # Circuit should be open
    assert CircuitBreaker.state() == :open

    # Requests should be rejected immediately
    assert {:error, :circuit_open} = ClaudeCodeSDK.query("Test")
  end
end
```

---

## 📋 Test Checklist Template

For each new feature, ensure:

### Functional Tests
- [ ] Happy path test
- [ ] Error path test
- [ ] Edge case tests (nil, empty, large values)
- [ ] Concurrent access test (if stateful)
- [ ] Idempotency test (if applicable)

### Integration Tests
- [ ] Module integration test
- [ ] End-to-end workflow test
- [ ] Backward compatibility test

### Performance Tests
- [ ] Benchmark baseline established
- [ ] No performance regression
- [ ] Memory usage acceptable

### Documentation
- [ ] Inline docs complete
- [ ] Usage examples in tests
- [ ] README updated

### Quality
- [ ] Dialyzer clean
- [ ] Credo passing
- [ ] Coverage >95%

---

## 🎓 Testing Best Practices

### 1. Test Naming

**Good**:
```elixir
test "returns error when token expired"
test "refreshes token before expiry"
test "handles concurrent token refresh safely"
```

**Bad**:
```elixir
test "test 1"
test "auth works"
test "edge case"
```

### 2. Arrange-Act-Assert Pattern

```elixir
test "description" do
  # Arrange - Setup
  initial_state = %{token: "old", expiry: expired_time()}

  # Act - Execute
  {:ok, new_token} = AuthManager.refresh_token(initial_state)

  # Assert - Verify
  assert new_token != "old"
  assert valid_token?(new_token)
end
```

### 3. One Assertion Per Concept

**Good**:
```elixir
test "token has correct format" do
  {:ok, token} = AuthManager.get_token()

  assert String.starts_with?(token, "sk-ant-api03-")
  assert String.length(token) == 118
  assert String.match?(token, ~r/^[a-zA-Z0-9\-_]+$/)
end
```

**Bad**:
```elixir
test "token works" do
  {:ok, token} = AuthManager.get_token()
  assert token  # Too vague
end
```

### 4. Test Independence

```elixir
# Each test should be independent
setup do
  # Reset state before each test
  :ok = AuthManager.clear_auth()
  :ok = SessionStore.clear_all()

  # Return context
  {:ok, %{}}
end
```

---

## 📊 Metrics to Track

### CI Metrics

- **Test Duration**: <5 minutes for full suite
- **Coverage**: >95% overall
- **Flaky Tests**: <1% failure rate
- **Build Success Rate**: >99%

### Quality Metrics

- **Dialyzer Warnings**: 0
- **Credo Issues**: 0 (strict mode)
- **Outdated Dependencies**: <10

### Performance Metrics

- **Unit Test Speed**: <1ms per test
- **Integration Test Speed**: <5s per test
- **E2E Test Speed**: <30s per test

---

**Status**: Living Document
**Last Updated**: 2025-10-07
**Review Frequency**: Monthly
**Owner**: TBD
