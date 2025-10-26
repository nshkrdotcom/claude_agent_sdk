# Comprehensive Testing Strategy

**Status**: Test Plan
**Target Coverage**: >90% for new code
**Estimated Test Count**: ~150 tests total

---

## Test Pyramid

```
                ┌──────────────┐
                │   E2E/Live   │   5% (~5 tests)
                │  (Real CLI)  │
                └──────┬───────┘
            ┌──────────┴──────────┐
            │  Integration Tests  │   20% (~30 tests)
            │   (Mocked CLI)      │
            └──────────┬──────────┘
        ┌──────────────┴──────────────┐
        │      Unit Tests              │   75% (~115 tests)
        │  (Pure functions, GenServer) │
        └──────────────────────────────┘
```

---

## 1. Unit Tests (~115 tests)

### 1.1 StreamingRouter Tests (test/claude_agent_sdk/transport/streaming_router_test.exs)

**Coverage**: 100% (pure functions)
**Test Count**: ~50

**Categories**:
- Default behavior (empty options)
- Hook detection (all hook types)
- SDK MCP vs external MCP
- Permission callback detection
- Agent detection
- Permission mode detection
- Explicit overrides
- Combined features
- Edge cases

**Example**:
```elixir
describe "select_transport/1" do
  test "empty options → CLI-only" do
    assert :streaming_session = StreamingRouter.select_transport(%Options{})
  end

  test "with hooks → control client" do
    opts = %Options{hooks: %{pre_tool_use: [...]}}
    assert :control_client = StreamingRouter.select_transport(opts)
  end

  # ... 48 more tests
end
```

### 1.2 Client Streaming Tests (test/claude_agent_sdk/client_streaming_test.exs)

**Coverage**: >95%
**Test Count**: ~40

**Categories**:
- Stream event handling (text_delta, thinking_delta, tool_input_delta)
- Text accumulation across deltas
- Message completion and reset
- Subscriber queue (activation, queueing, auto-activation)
- Mixed event/message streams
- Error handling (malformed events, missing subscribers)

**Example**:
```elixir
describe "streaming event handling" do
  test "broadcasts text_delta to active subscriber" do
    opts = %Options{include_partial_messages: true}
    {:ok, client} = Client.start_link(opts)

    ref = make_ref()
    :ok = GenServer.call(client, {:subscribe, ref})

    send(client, simulate_stream_event(text_delta("Hello")))

    assert_receive {:stream_event, ^ref, %{
      type: :text_delta,
      text: "Hello",
      accumulated: "Hello"
    }}
  end
end
```

### 1.3 EventAdapter Tests (test/claude_agent_sdk/streaming/event_adapter_test.exs)

**Coverage**: 100%
**Test Count**: ~25

**Categories**:
- Event normalization (map → map passthrough)
- Message struct conversion (Message → event map)
- Text-only filtering
- Tool-only filtering
- Text accumulation
- Edge cases (unknown types, nil values)

---

## 2. Integration Tests (~30 tests)

### 2.1 Streaming + Tools Integration (test/claude_agent_sdk/streaming_tools_integration_test.exs)

**Coverage**: End-to-end scenarios
**Test Count**: ~20

**Scenarios**:
1. Text-only streaming via control client
2. Tool execution without streaming
3. **Interleaved text + tools**
4. Multiple tools in sequence
5. Tool error during stream
6. Hook denial mid-stream
7. Permission callback during stream
8. SDK MCP tool invocation
9. Subscriber queue with multiple messages
10. Session recovery after error
11. Thinking blocks with tools
12. Tool input deltas during tool call
13. Message stop triggers queue activation
14. Concurrent subscribers (queued properly)
15. External MCP + streaming (CLI-only path)
16. SDK MCP + streaming (control path)
17. Mixed SDK + external MCP
18. Runtime agent switch during stream
19. Runtime permission mode change
20. Transport override with features present

**Mock Strategy**:
```elixir
defmodule ClaudeAgentSDK.Test.MockCLI do
  @moduledoc "Mock CLI process for integration tests"

  def spawn_with_script(script) do
    # script = [
    #   {:stream_event, :message_start},
    #   {:stream_event, text_delta("Hello")},
    #   {:tool_use, "Bash", %{command: "ls"}},
    #   {:stream_event, text_delta(" world")},
    #   {:stream_event, :message_stop}
    # ]

    {:ok, pid} = Task.start_link(fn ->
      run_script(script)
    end)

    pid
  end

  defp run_script(script) do
    receive do
      {:send, _message} ->
        # Emit scripted events
        Enum.each(script, &emit_event/1)
        run_script([])  # Script exhausted
    end
  end

  defp emit_event({:stream_event, event}) do
    send_to_parent({:stream_event, event})
  end

  defp emit_event({:tool_use, tool, input}) do
    send_to_parent({:tool_use, tool, input})
  end
end
```

**Example Test**:
```elixir
@tag :integration
test "streams text while executing tools" do
  mock_cli = MockCLI.spawn_with_script([
    {:stream_event, message_start()},
    {:stream_event, text_delta("Running: ")},
    {:tool_use, "Bash", %{command: "ls"}},
    {:tool_result, "Bash", "file1.txt\nfile2.txt"},
    {:stream_event, text_delta("Found 2 files")},
    {:stream_event, message_stop()}
  ])

  opts = %Options{
    hooks: %{pre_tool_use: [test_hook()]},
    transport: MockTransport,
    transport_opts: [cli_process: mock_cli]
  }

  {:ok, session} = Streaming.start_session(opts)

  events = Streaming.send_message(session, "List files")
    |> Enum.to_list()

  # Verify mixed stream
  text_events = Enum.filter(events, &(&1.type == :text_delta))
  tool_events = Enum.filter(events, &(&1.type in [:tool_use_start, :tool_result]))

  assert length(text_events) == 2
  assert length(tool_events) >= 1

  # Verify text content
  full_text = text_events
    |> Enum.map(&(&1.text))
    |> Enum.join("")

  assert full_text =~ "Running:"
  assert full_text =~ "Found 2 files"
end
```

### 2.2 Transport Selection Integration (test/claude_agent_sdk/transport/routing_integration_test.exs)

**Coverage**: Router + Streaming integration
**Test Count**: ~10

**Scenarios**:
- Simple streaming → Session selected
- Hooks → Client selected
- SDK MCP → Client selected
- External MCP only → Session selected
- Override to CLI → Session even with hooks
- Override to control → Client without features
- Feature detection across all option types
- Session type verification
- send_message works with both transports
- close works with both transports

---

## 3. E2E / Live Tests (~5 tests)

### 3.1 Live CLI Tests (test/integration/streaming_tools_live_test.exs)

**Coverage**: Real Claude CLI
**Test Count**: ~5

**Prerequisites**:
- Claude CLI installed
- Authentication configured
- `mix test --include live`

**Scenarios**:
1. **Real Bash tool with streaming**:
   ```elixir
   @tag :live
   @tag :requires_cli
   test "streams bash tool output" do
     {:ok, session} = Streaming.start_session(%Options{
       allowed_tools: ["Bash"],
       include_partial_messages: true
     })

     events = Streaming.send_message(session, "Run: echo 'Hello from Bash'")
       |> Enum.take(100)

     # Should see text deltas AND tool result
     assert Enum.any?(events, &(&1.type == :text_delta))
     assert Enum.any?(events, &(&1.type == :tool_result))
   end
   ```

2. **Real SDK MCP server**:
   ```elixir
   @tag :live
   test "uses SDK MCP calculator" do
     server = ClaudeAgentSDK.create_sdk_mcp_server(
       name: "calc",
       tools: [CalculatorTools.Add]
     )

     opts = %Options{
       mcp_servers: %{"calc" => server}
     }

     {:ok, session} = Streaming.start_session(opts)

     events = Streaming.send_message(session, "What is 25 + 17?")
       |> Enum.to_list()

     # Verify tool was called and result correct
     assert Enum.any?(events, fn
       %{type: :tool_result, tool_name: "add"} -> true
       _ -> false
     end)

     final_text = accumulate_text(events)
     assert final_text =~ "42"
   end
   ```

3. **Performance benchmark**:
   ```elixir
   @tag :live
   @tag :benchmark
   test "latency acceptable" do
     {time_us, _result} = :timer.tc(fn ->
       {:ok, session} = Streaming.start_session()

       Streaming.send_message(session, "Say hello")
         |> Enum.take(1)  # Time to first event
     end)

     latency_ms = time_us / 1000

     # Should be <500ms to first event
     assert latency_ms < 500,
       "Latency too high: #{latency_ms}ms"
   end
   ```

4. **LiveView simulation**:
   ```elixir
   @tag :live
   test "LiveView integration pattern" do
     # Simulates Phoenix LiveView streaming scenario
     {:ok, session} = Streaming.start_session()

     # Async stream processing (like LiveView handle_info)
     parent = self()

     Task.async(fn ->
       Streaming.send_message(session, "Write a haiku")
         |> Stream.each(fn event ->
           send(parent, {:ui_update, event})
         end)
         |> Stream.run()
     end)

     # Collect UI updates
     ui_updates = collect_messages(:ui_update, timeout: 10_000)

     assert length(ui_updates) > 5  # Multiple deltas
   end
   ```

5. **Stress test**:
   ```elixir
   @tag :live
   @tag :stress
   test "handles high-frequency deltas" do
     {:ok, session} = Streaming.start_session()

     # Request verbose output
     events = Streaming.send_message(
       session,
       "List all files in /usr/bin with full details"
     ) |> Enum.take(1000)

     # Should handle many events without issues
     assert length(events) > 100
     refute Enum.any?(events, &(&1.type == :error))
   end
   ```

---

## 4. Property-Based Tests (Optional)

### 4.1 Router Properties

```elixir
defmodule StreamingRouterProperties do
  use ExUnitProperties

  property "router always returns valid transport" do
    check all(
      has_hooks <- boolean(),
      has_mcp <- boolean(),
      override <- member_of([nil, :cli, :control])
    ) do
      opts = build_options(hooks: has_hooks, mcp: has_mcp, override: override)
      choice = StreamingRouter.select_transport(opts)

      assert choice in [:streaming_session, :control_client]

      # Override always respected
      if override == :cli, do: assert choice == :streaming_session
      if override == :control, do: assert choice == :control_client
    end
  end
end
```

### 4.2 Event Stream Properties

```elixir
property "text accumulation commutative" do
  check all(deltas <- list_of(text_delta(), min_length: 1)) do
    # Accumulating deltas in order should equal summing texts
    events = simulate_deltas(deltas)
    final = List.last(events)

    expected_text = deltas |> Enum.map(&(&1.text)) |> Enum.join("")

    assert final.accumulated == expected_text
  end
end
```

---

## 5. Test Utilities & Helpers

### 5.1 Mock CLI Builder

```elixir
defmodule ClaudeAgentSDK.Test.CLIScriptBuilder do
  def new do
    %__MODULE__{events: []}
  end

  def emit_text(builder, text) do
    event = {:stream_event, text_delta(text)}
    %{builder | events: builder.events ++ [event]}
  end

  def use_tool(builder, tool, input) do
    start_event = {:stream_event, tool_use_start(tool)}
    use_event = {:tool_use, tool, input}

    %{builder | events: builder.events ++ [start_event, use_event]}
  end

  def complete(builder) do
    stop_event = {:stream_event, message_stop()}
    %{builder | events: builder.events ++ [stop_event]}
  end

  def run(builder) do
    MockCLI.spawn_with_script(builder.events)
  end
end
```

**Usage**:
```elixir
mock_cli = CLIScriptBuilder.new()
  |> CLIScriptBuilder.emit_text("Starting...")
  |> CLIScriptBuilder.use_tool("Bash", %{command: "ls"})
  |> CLIScriptBuilder.emit_text("Done.")
  |> CLIScriptBuilder.complete()
  |> CLIScriptBuilder.run()
```

### 5.2 Event Assertions

```elixir
defmodule ClaudeAgentSDK.Test.EventAssertions do
  def assert_text_delta(event, expected_text) do
    assert event.type == :text_delta
    assert event.text == expected_text
  end

  def assert_accumulated_equals(events, expected) do
    final = List.last(events)
    assert final.accumulated == expected
  end

  def assert_contains_tool_result(events, tool_name) do
    assert Enum.any?(events, fn
      %{type: :tool_result, tool_name: ^tool_name} -> true
      _ -> false
    end), "Expected tool result for #{tool_name}"
  end

  def accumulate_text(events) do
    events
    |> Enum.filter(&(&1.type == :text_delta))
    |> Enum.map(&(&1.text))
    |> Enum.join("")
  end
end
```

---

## 6. Test Execution Plan

### Day 1-2: Unit Tests (TDD Red Phase)
```bash
# Write all unit tests (should fail)
mix test test/claude_agent_sdk/transport/streaming_router_test.exs
# Expected: 50 failures

mix test test/claude_agent_sdk/client_streaming_test.exs
# Expected: 40 failures

mix test test/claude_agent_sdk/streaming/event_adapter_test.exs
# Expected: 25 failures
```

### Day 4-5: Unit Tests (TDD Green Phase)
```bash
# Implement modules, tests should pass
mix test test/claude_agent_sdk/transport/streaming_router_test.exs
# Expected: 50 passes

mix test test/claude_agent_sdk/client_streaming_test.exs
# Expected: 40 passes

mix test test/claude_agent_sdk/streaming/event_adapter_test.exs
# Expected: 25 passes
```

### Day 8-9: Integration Tests
```bash
mix test test/claude_agent_sdk/streaming_tools_integration_test.exs
# Expected: 20 passes

mix test test/claude_agent_sdk/transport/routing_integration_test.exs
# Expected: 10 passes
```

### Day 12-13: Live Tests
```bash
# Requires auth + CLI
LIVE_TESTS=true mix test --include live
# Expected: 5 passes
```

### Final: Full Suite
```bash
mix test --include integration
# Expected: 150+ passes, 0 failures
```

---

## 7. Coverage Requirements

### Per-Module Coverage Targets

| Module | Target | Justification |
|--------|--------|---------------|
| StreamingRouter | 100% | Pure functions, easy to test |
| Client (new code) | >95% | Critical path, but some error branches hard to trigger |
| Streaming facade | >90% | Integration code, some edge cases |
| EventAdapter | 100% | Utility functions, straightforward |
| Overall new code | >90% | Industry standard for production code |

### Measuring Coverage

```bash
# Generate coverage report
mix test --cover

# Review detailed coverage
open cover/excoveralls.html

# Check specific module
mix test --cover --filter module:StreamingRouter
```

---

## 8. Continuous Integration

### GitHub Actions Workflow

```yaml
name: Streaming + Tools Tests

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'

      - name: Install dependencies
        run: mix deps.get

      - name: Run unit tests
        run: mix test --exclude integration --exclude live

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1

      - name: Install dependencies
        run: mix deps.get

      - name: Run integration tests
        run: mix test --include integration --exclude live

  live-tests:
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1

      - name: Install Claude CLI
        run: |
          npm install -g @anthropic/claude-code

      - name: Configure auth
        env:
          CLAUDE_AGENT_OAUTH_TOKEN: ${{ secrets.CLAUDE_TOKEN }}
        run: echo "Auth configured"

      - name: Run live tests
        env:
          CLAUDE_AGENT_OAUTH_TOKEN: ${{ secrets.CLAUDE_TOKEN }}
          LIVE_TESTS: "true"
        run: mix test --include live
```

---

## Summary

Comprehensive testing strategy ensures:

✅ **100% coverage of router** (pure functions)
✅ **>95% coverage of Client enhancements**
✅ **>90% overall new code coverage**
✅ **20 integration scenarios** (mocked CLI)
✅ **5 live scenarios** (real CLI)
✅ **TDD approach** (red → green → refactor)

**Total Tests**: ~150
**Total Time**: ~3 days (Days 1-2, 8-9, 12-13)
