# Complete Implementation Prompt: Streaming + Tools Unification

**Project**: Claude Agent SDK v0.6.0 - Streaming + Tools Transport Unification
**Date**: 2025-10-26
**Status**: Ready for Implementation
**Estimated Duration**: 10-14 developer days
**Development Methodology**: Test-Driven Development (TDD)

---

## CRITICAL CONTEXT: WHAT YOU NEED TO KNOW

### The Problem

Currently, Claude Agent SDK has a **SPLIT BRAIN** architecture:

1. **`Streaming.Session`** - Fast CLI streaming with `--include-partial-messages`
   - ✅ Character-level text streaming
   - ❌ No hooks support
   - ❌ No SDK MCP servers
   - ❌ No permission callbacks

2. **`Client`** - Full control protocol support
   - ✅ Hooks
   - ✅ SDK MCP tools
   - ✅ Permission callbacks
   - ❌ No character-level streaming

**Users must choose ONE or the OTHER** - they cannot have both.

### The Solution

Implement a **ROUTER** that automatically selects the right transport based on features:
- Simple streaming → Use `Streaming.Session` (fast path)
- Streaming + tools/hooks → Use `Client` with streaming enabled (full path)

**This is transparent to users** - they just call `Streaming.start_session/1` and it works.

---

## REQUIRED READING (IN ORDER)

You MUST read and understand these documents before implementing:

### 1. Design Documents (Read First)

Located in: `claude_agent_sdk/docs/20251025/claude_streaming_tools/`

**Priority 1 - Must Read**:
1. `00_FEASIBILITY_ASSESSMENT.md` - Architectural readiness, risks, timeline (2077 lines)
2. `01_ROUTER_DESIGN.md` - Core routing logic, decision matrix (873 lines)
3. `02_CLIENT_STREAMING_ENHANCEMENTS.md` - Client modifications needed
4. `05_IMPLEMENTATION_ROADMAP.md` - Day-by-day implementation guide (1070 lines)

**Priority 2 - Reference**:
5. `03_STREAMING_FACADE_INTEGRATION.md` - Streaming module updates
6. `04_TESTING_STRATEGY.md` - Comprehensive test plan (~150 tests)
7. `STREAMING_WITH_TOOLS_ARCHITECTURE.md` - High-level architecture

### 2. Source Code (Reference During Implementation)

**Core Modules to Understand**:

```elixir
# Transport abstraction (already exists)
lib/claude_agent_sdk/transport.ex

# Options configuration
lib/claude_agent_sdk/options.ex
# Lines 48-94: defstruct with ~30 fields
# Lines 202-298: to_args/1 pipeline (CLI argument generation)

# EventParser (streaming events) - NO CHANGES NEEDED
lib/claude_agent_sdk/streaming/event_parser.ex
# Lines 1-285: Complete SSE event parsing
# Handles: text_delta, tool_input_delta, thinking_delta, message_start/stop

# Streaming.Session (CLI-only streaming) - NO CHANGES NEEDED
lib/claude_agent_sdk/streaming/session.ex
# Lines 1-550: GenServer with erlexec subprocess management
# Lines 229-316: Subscriber queue (FIFO, single active)
# Lines 445-461: build_streaming_args with --include-partial-messages

# Client (control protocol) - MAJOR CHANGES HERE
lib/claude_agent_sdk/client.ex
# Lines 84-98: State struct (ADD streaming fields)
# Lines 525-584: handle_info for port messages (ADD stream_event case)
# Lines 801-818: build_cli_command (ADD --include-partial-messages)
# Lines 1139-1151: Subscriber management (CHANGE to queue model)

# Streaming facade (public API) - CHANGES HERE
lib/claude_agent_sdk/streaming.ex
# Lines 1-150: Public API (ADD router integration)
```

### 3. Test Infrastructure

```elixir
# Existing test support (477 tests passing)
test/support/supertester_case.ex

# Mock system
lib/claude_agent_sdk/mock.ex
test/support/mock_process.ex
```

---

## IMPLEMENTATION REQUIREMENTS

### Architecture Principles

1. **Zero Breaking Changes** - All 477 existing tests MUST pass unchanged
2. **Opt-In Behavior** - New features require explicit `include_partial_messages: true`
3. **TDD Required** - Write tests FIRST, then implement (Red-Green-Refactor)
4. **Performance** - <10% regression on any path
5. **Type Safety** - Full Dialyzer coverage, no warnings

### Quality Gates (Must Pass Before PR)

```bash
mix format --check-formatted   # Zero formatting issues
mix compile --warnings-as-errors # Zero compiler warnings
mix credo --strict              # Zero Credo issues
mix dialyzer                    # Zero Dialyzer errors
mix test --include integration  # 620+ tests passing, 0 failures
mix test --cover                # >90% coverage on new code
```

---

## DETAILED IMPLEMENTATION GUIDE

### Phase 1: Foundation (Days 1-3)

#### Day 1: CLI Verification & Router (CRITICAL GATE)

**BEFORE ANYTHING ELSE**:

```bash
# Test CLI compatibility
echo '{"type":"control_request","request_id":"test-001","request":{"subtype":"initialize","version":"1.0.0","hooks":{}}}' | \
claude --output-format stream-json \
       --input-format stream-json \
       --include-partial-messages \
       --verbose

# Expected: CLI accepts both flags and responds
# If FAILS: STOP and escalate - CLI may not support this
```

**If CLI verification passes**, proceed with router:

```elixir
# FILE: lib/claude_agent_sdk/transport/streaming_router.ex
defmodule ClaudeAgentSDK.Transport.StreamingRouter do
  @moduledoc """
  Selects streaming transport based on required features.

  ## Decision Logic

  1. Check explicit override (`preferred_transport`)
  2. Detect control protocol requirements:
     - hooks present?
     - SDK MCP servers present?
     - permission callback present?
     - runtime agents configured?
     - special permission mode?
  3. Default to CLI-only (fast path)

  ## Examples

      # Simple streaming → CLI-only
      iex> select_transport(%Options{})
      :streaming_session

      # With hooks → Control client
      iex> select_transport(%Options{hooks: %{pre_tool_use: [hook]}})
      :control_client
  """

  alias ClaudeAgentSDK.Options

  @type transport_choice :: :streaming_session | :control_client

  @doc """
  Selects transport implementation.

  Pure function, no I/O, <0.1ms execution time.
  """
  @spec select_transport(Options.t()) :: transport_choice()
  def select_transport(%Options{preferred_transport: :cli}),
    do: :streaming_session

  def select_transport(%Options{preferred_transport: :control}),
    do: :control_client

  def select_transport(%Options{} = opts) do
    if requires_control_protocol?(opts) do
      :control_client
    else
      :streaming_session
    end
  end

  @doc "Checks if options require control protocol"
  @spec requires_control_protocol?(Options.t()) :: boolean()
  def requires_control_protocol?(opts) do
    has_hooks?(opts) or
    has_sdk_mcp_servers?(opts) or
    has_permission_callback?(opts) or
    has_runtime_agents?(opts) or
    has_special_permission_mode?(opts)
  end

  # Feature Detection (implement all per 01_ROUTER_DESIGN.md lines 191-228)

  defp has_hooks?(%Options{hooks: hooks}) when is_map(hooks) and map_size(hooks) > 0 do
    # Must have non-empty matchers
    Enum.any?(hooks, fn {_event, matchers} ->
      is_list(matchers) and length(matchers) > 0
    end)
  end
  defp has_hooks?(_), do: false

  defp has_sdk_mcp_servers?(%Options{mcp_servers: servers}) when is_map(servers) do
    # Only SDK servers require control; external use CLI flags
    Enum.any?(servers, fn
      {_name, %{type: :sdk}} -> true
      _ -> false
    end)
  end
  defp has_sdk_mcp_servers?(_), do: false

  defp has_permission_callback?(%Options{can_use_tool: cb})
    when is_function(cb, 1),
    do: true
  defp has_permission_callback?(_), do: false

  defp has_runtime_agents?(%Options{agents: agents})
    when is_map(agents) and map_size(agents) > 0,
    do: true
  defp has_runtime_agents?(_), do: false

  defp has_special_permission_mode?(%Options{permission_mode: mode})
    when mode in [:accept_edits, :bypass_permissions, :plan],
    do: true
  defp has_special_permission_mode?(_), do: false

  @doc "Human-readable explanation (for debugging)"
  @spec explain(Options.t()) :: String.t()
  def explain(%Options{} = opts) do
    choice = select_transport(opts)
    features = detect_features(opts)
    reason = selection_reason(opts)

    """
    Transport: #{choice}
    Reason: #{reason}
    Features: #{inspect(features)}
    """
  end

  # Add helper functions per design doc...
  # (see 01_ROUTER_DESIGN.md lines 230-270)
end
```

**TDD: Write Tests FIRST** (50 tests):

```elixir
# FILE: test/claude_agent_sdk/transport/streaming_router_test.exs
defmodule ClaudeAgentSDK.Transport.StreamingRouterTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Transport.StreamingRouter}
  alias ClaudeAgentSDK.Hooks.Matcher

  describe "select_transport/1 - defaults" do
    test "empty options → CLI-only" do
      assert :streaming_session = StreamingRouter.select_transport(%Options{})
    end

    test "standard options → CLI-only" do
      opts = %Options{model: "sonnet", max_turns: 5}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - hooks detection" do
    test "with hooks → control client" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}
      }
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "empty hooks map → CLI-only" do
      opts = %Options{hooks: %{}}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "hooks with empty matchers → CLI-only" do
      opts = %Options{hooks: %{pre_tool_use: []}}
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - SDK MCP detection" do
    test "SDK MCP server → control client" do
      server = ClaudeAgentSDK.create_sdk_mcp_server(
        name: "test",
        tools: []
      )
      opts = %Options{mcp_servers: %{"test" => server}}
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "external MCP server only → CLI-only" do
      opts = %Options{
        mcp_servers: %{
          "external" => %{type: :stdio, command: "mcp-server", args: []}
        }
      }
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end
  end

  describe "select_transport/1 - explicit override" do
    test "preferred_transport :cli with hooks → CLI-only" do
      callback = fn _, _, _ -> :allow end
      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]},
        preferred_transport: :cli
      }
      # Override takes precedence
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "preferred_transport :control without features → control client" do
      opts = %Options{preferred_transport: :control}
      assert :control_client = StreamingRouter.select_transport(opts)
    end
  end

  # Add 40+ more tests per 01_ROUTER_DESIGN.md lines 279-646
  # Test EVERY feature detection function
  # Test ALL combinations
  # Test edge cases (nil, empty, invalid)
end
```

**Run tests** - they should ALL FAIL (router not implemented yet):

```bash
mix test test/claude_agent_sdk/transport/streaming_router_test.exs
# Expected: 50 failures (TDD RED phase)
```

**Now implement** router to make tests pass (TDD GREEN phase).

**Day 1 Deliverable**:
- ✅ CLI compatibility verified (GATE PASSED)
- ✅ StreamingRouter complete (~120 LOC)
- ✅ 50 tests passing

---

#### Day 2: Options Extension

**FILE: lib/claude_agent_sdk/options.ex**

Add two new fields:

```elixir
# Around line 94 - Add to defstruct:
defstruct [
  # ... existing 30+ fields ...
  :timeout_ms,
  # NEW FIELDS (v0.6.0)
  :include_partial_messages,  # boolean - enable streaming events
  :preferred_transport        # :auto | :cli | :control - transport override
]

# Around line 153 - Add to typespecs:
@type t :: %__MODULE__{
  # ... existing types ...
  timeout_ms: integer() | nil,
  include_partial_messages: boolean() | nil,
  preferred_transport: transport_preference() | nil
}

@type transport_preference :: :auto | :cli | :control

# Around line 222 - Add to to_args pipeline:
def to_args(%__MODULE__{} = options) do
  []
  |> add_output_format_args(options)
  # ... existing 15+ pipeline stages ...
  |> add_strict_mcp_args(options)
  |> add_partial_messages_args(options)  # NEW
end

# After line 298 - Add CLI arg generator:
defp add_partial_messages_args(args, %{include_partial_messages: true}) do
  args ++ ["--include-partial-messages"]
end
defp add_partial_messages_args(args, _), do: args
```

**TDD: Write tests FIRST**:

```elixir
# FILE: test/claude_agent_sdk/options_test.exs (add to existing file)
describe "new fields (v0.6.0)" do
  test "includes partial messages flag when set" do
    opts = %Options{include_partial_messages: true}
    args = Options.to_args(opts)
    assert "--include-partial-messages" in args
  end

  test "omits partial messages flag when false" do
    opts = %Options{include_partial_messages: false}
    args = Options.to_args(opts)
    refute "--include-partial-messages" in args
  end

  test "preferred_transport accepts valid values" do
    for transport <- [:auto, :cli, :control] do
      assert %Options{preferred_transport: transport}
    end
  end

  # Add 7+ more tests
end
```

**Day 2 Deliverable**:
- ✅ Options extended (~30 LOC)
- ✅ 10 new tests passing
- ✅ Documentation updated

---

#### Day 3: Test Infrastructure

Create mock CLI helpers for integration testing:

```bash
mkdir -p test/support
touch test/support/mock_cli.ex
touch test/support/cli_script_builder.ex
touch test/support/event_assertions.ex
```

See `04_TESTING_STRATEGY.md` section 5.1 for MockCLI design.

Write **one failing integration test** to drive Phase 2:

```elixir
# FILE: test/claude_agent_sdk/streaming_tools_integration_test.exs
defmodule ClaudeAgentSDK.StreamingToolsIntegrationTest do
  use ClaudeAgentSDK.SupertesterCase

  @moduletag :integration

  test "streams text while executing tools" do
    # This test will FAIL until Phase 2 complete
    # That's expected - it drives our implementation

    # Setup: Create SDK MCP server
    server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "calculator",
      tools: [TestCalculator]
    )

    opts = %Options{
      include_partial_messages: true,
      mcp_servers: %{"calculator" => server}
    }

    # Start streaming session (should use control client)
    {:ok, session} = Streaming.start_session(opts)

    # Send message that requires tool
    events = Streaming.send_message(session, "What is 25 + 17?")
      |> Enum.to_list()

    # Should see BOTH text deltas AND tool calls
    text_deltas = Enum.filter(events, &(&1.type == :text_delta))
    tool_events = Enum.filter(events, &(&1.type in [:tool_use_start, :tool_result]))

    assert length(text_deltas) > 0, "Expected text streaming"
    assert length(tool_events) > 0, "Expected tool execution"
  end
end
```

**Day 3 Deliverable**:
- ✅ Mock CLI infrastructure ready
- ✅ 1 failing integration test (expected)

---

### Phase 2: Core Implementation (Days 4-8)

#### Day 4-5: Client Enhancements - Streaming Support

**CRITICAL**: Client must handle streaming events while maintaining control protocol.

**FILE: lib/claude_agent_sdk/client.ex**

**Step 1: Update State** (around line 84):

```elixir
@type state :: %{
  # ... existing fields (port, options, hooks, subscribers, etc.) ...
  current_model: String.t() | nil,
  pending_model_change: {GenServer.from(), reference()} | nil,

  # NEW FIELDS for streaming support
  accumulated_text: String.t(),         # Buffer for partial text
  active_subscriber: reference() | nil, # Current streaming consumer
  subscriber_queue: [{reference(), String.t()}]  # Pending messages
}
```

**Step 2: Update Initialization** (around line 354):

```elixir
defp do_init(options, opts) do
  # ... existing validation ...

  state = %{
    # ... existing fields ...
    current_model: updated_options.model,
    pending_model_change: nil,

    # Initialize streaming fields
    accumulated_text: "",
    active_subscriber: nil,
    subscriber_queue: []
  }

  {:ok, state, {:continue, :start_cli}}
end
```

**Step 3: Modify CLI Command Builder** (around line 801):

```elixir
defp build_cli_command(options) do
  executable = System.find_executable("claude")

  if executable do
    base_args = [
      "--output-format", "stream-json",
      "--input-format", "stream-json",
      "--verbose"
    ]

    # Add partial messages flag if requested
    base_args = if options.include_partial_messages do
      base_args ++ ["--include-partial-messages"]
    else
      base_args
    end

    args = base_args ++ Options.to_args(options)
    cmd = Enum.join([executable | args], " ") <> " 2>/dev/null"
    {:ok, cmd}
  else
    {:error, :claude_not_found}
  end
end
```

**Step 4: Add Stream Event Handler** (new function after line 837):

```elixir
# Add to Protocol.decode_message/1 first:
defp decode_message_type(json) do
  case json do
    %{"type" => "control_request"} -> {:ok, :control_request}
    %{"type" => "control_response"} -> {:ok, :control_response}
    %{"type" => "sdk_message"} -> {:ok, :sdk_message}
    %{"type" => "stream_event"} -> {:ok, :stream_event}  # NEW
    %{"type" => type} when is_binary(type) -> {:ok, :sdk_message}
    _ -> {:error, :unknown_type}
  end
end

# Then add handler:
defp handle_decoded_message(:stream_event, event_data, state) do
  # Parse streaming event via EventParser
  {:ok, events, new_accumulated} =
    ClaudeAgentSDK.Streaming.EventParser.parse_event(
      event_data,
      state.accumulated_text
    )

  # Broadcast to active subscriber only (queue model)
  if state.active_subscriber do
    broadcast_events_to_subscriber(
      state.active_subscriber,
      state.subscribers,
      events
    )
  end

  # Check for message completion
  message_complete? = Enum.any?(events, &(&1.type == :message_stop))

  if message_complete? do
    handle_stream_completion(state, new_accumulated)
  else
    %{state | accumulated_text: new_accumulated}
  end
end

defp handle_stream_completion(state, accumulated_text) do
  # Process next queued message if any
  case state.subscriber_queue do
    [{next_ref, next_message} | rest] ->
      # Send queued message
      json = encode_outgoing_message(next_message)
      _ = send_payload(state, json)

      %{
        state
        | active_subscriber: next_ref,
          subscriber_queue: rest,
          accumulated_text: ""
      }

    [] ->
      %{
        state
        | active_subscriber: nil,
          subscriber_queue: [],
          accumulated_text: accumulated_text
      }
  end
end

defp broadcast_events_to_subscriber(ref, subscribers, events) do
  case Map.get(subscribers, ref) do
    nil -> :ok
    pid ->
      Enum.each(events, fn event ->
        send(pid, {:stream_event, ref, event})
      end)
  end
end
```

**Step 5: Update Subscriber Management** (modify around line 432):

```elixir
def handle_call({:subscribe, ref}, from, state) do
  {pid, _ref} = from

  # Add to subscribers map
  subscribers = Map.put(state.subscribers, ref, pid)

  # Activate if no active subscriber, otherwise subscriber waits
  {new_active, new_queue} = if state.active_subscriber == nil do
    {ref, state.subscriber_queue}
  else
    # This subscriber will wait
    {state.active_subscriber, state.subscriber_queue}
  end

  {:reply, :ok, %{
    state
    | subscribers: subscribers,
      active_subscriber: new_active,
      subscriber_queue: new_queue
  }}
end
```

**TDD: Write Tests FIRST** (~40 tests):

```elixir
# FILE: test/claude_agent_sdk/client_streaming_test.exs
defmodule ClaudeAgentSDK.ClientStreamingTest do
  use ClaudeAgentSDK.SupertesterCase

  describe "partial message streaming" do
    test "broadcasts text_delta events to active subscriber" do
      options = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(options)

      ref = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref})

      # Simulate streaming event from CLI
      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Hello"}
      }

      send(client, simulate_port_data(event))

      assert_receive {:stream_event, ^ref, %{type: :text_delta, text: "Hello"}}
    end

    test "accumulates text across multiple deltas" do
      # ... test accumulated_text field updates
    end

    test "resets accumulated text on message_stop" do
      # ... test state cleanup
    end

    test "queues subscribers correctly" do
      # ... test FIFO queue behavior
    end

    test "activates next subscriber after message_stop" do
      # ... test queue processing
    end

    test "handles interleaved text deltas and tool calls" do
      # ... complex scenario
    end

    # Add 35+ more tests per design docs
  end
end
```

**Days 4-5 Deliverable**:
- ✅ Client streaming support (~200 LOC)
- ✅ 40 new tests passing

---

#### Day 6: Subscriber Queue Implementation

Continue in Client - implement full queue semantics matching `Streaming.Session`:

```elixir
# Enhance send_message to queue if subscriber active
def handle_call({:send_message, message}, from, state) do
  if state.active_subscriber do
    # Queue this message
    {ref, _} = from
    new_queue = state.subscriber_queue ++ [{ref, message}]
    {:reply, :ok, %{state | subscriber_queue: new_queue}}
  else
    # Send immediately
    # ... existing logic
  end
end
```

Write 15+ tests for queue behavior.

**Day 6 Deliverable**:
- ✅ Subscriber queue working
- ✅ 15 new tests passing

---

#### Day 7: Streaming Facade Integration

**FILE: lib/claude_agent_sdk/streaming.ex**

Integrate router into public API:

```elixir
defmodule ClaudeAgentSDK.Streaming do
  @moduledoc """
  Character-level streaming API for Claude conversations.

  ## Transport Selection (v0.6.0)

  Automatically selects appropriate transport:
  - **CLI-only**: Fast path for simple streaming
  - **Control client**: Full features (hooks + MCP + streaming)

  Selection is transparent - just use the API.

  ## Examples

      # Simple streaming (uses CLI-only)
      {:ok, session} = Streaming.start_session()

      # Streaming with hooks (uses control client)
      {:ok, session} = Streaming.start_session(%Options{
        include_partial_messages: true,
        hooks: %{pre_tool_use: [my_hook]}
      })
  """

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Streaming.Session
  alias ClaudeAgentSDK.Transport.StreamingRouter

  @type session :: pid() | {:control_client, pid()}
  @type event :: map()

  @doc """
  Starts a streaming session with automatic transport selection.
  """
  @spec start_session(Options.t() | nil) :: {:ok, session()} | {:error, term()}
  def start_session(options \\ nil) do
    opts = options || %Options{}

    # Force partial messages enabled for streaming
    opts = %{opts | include_partial_messages: true}

    case StreamingRouter.select_transport(opts) do
      :streaming_session ->
        # Fast path: Direct CLI streaming
        Session.start_link(opts)

      :control_client ->
        # Full features path: Control client with streaming
        start_control_streaming(opts)
    end
  end

  defp start_control_streaming(opts) do
    case Client.start_link(opts) do
      {:ok, client} ->
        # Wrap client to provide Session-compatible API
        {:ok, {:control_client, client}}

      error ->
        error
    end
  end

  @doc """
  Sends a message and returns a stream of events.

  Works transparently with both transports.
  """
  @spec send_message(session(), String.t()) :: Enumerable.t(event())
  def send_message({:control_client, client}, message) do
    # Route through control client
    stream_via_control_client(client, message)
  end

  def send_message(session, message) when is_pid(session) do
    # Original CLI-only path
    Session.send_message(session, message)
  end

  defp stream_via_control_client(client, message) do
    ref = make_ref()

    # Subscribe to control client
    :ok = GenServer.call(client, {:subscribe, ref})

    # Send message
    :ok = Client.send_message(client, message)

    # Return stream that adapts client messages to events
    Stream.resource(
      fn -> {client, ref, :active, ""} end,
      fn {client, ref, status, accumulated} = state ->
        if status == :complete do
          {:halt, state}
        else
          receive do
            # Stream events from control client
            {:stream_event, ^ref, event} ->
              new_status = case event.type do
                :message_stop -> :complete
                _ -> :active
              end

              new_accumulated = event[:accumulated] || accumulated

              {[event], {client, ref, new_status, new_accumulated}}

            # Regular messages (tool results, etc.)
            {:claude_message, message} ->
              # Convert Message to event format
              event = message_to_event(message, accumulated)
              {[event], state}

            {:stream_error, ^ref, reason} ->
              error_event = %{type: :error, error: reason}
              {[error_event], {client, ref, :complete, accumulated}}
          after
            300_000 -> # 5 minutes
              timeout_event = %{type: :error, error: :timeout}
              {[timeout_event], {client, ref, :complete, accumulated}}
          end
        end
      end,
      fn {client, ref, _, _} ->
        GenServer.cast(client, {:unsubscribe, ref})
      end
    )
  end

  # Convert Message struct to streaming event format
  defp message_to_event(%{type: :tool_result} = msg, accumulated) do
    %{
      type: :tool_complete,
      tool_name: msg.tool_name,
      result: msg.content,
      accumulated: accumulated
    }
  end

  defp message_to_event(%{type: :error} = msg, accumulated) do
    %{type: :error, error: msg.content, accumulated: accumulated}
  end

  defp message_to_event(msg, accumulated) do
    %{type: :message, message: msg, accumulated: accumulated}
  end

  @doc "Closes the streaming session"
  @spec close(session()) :: :ok
  def close({:control_client, client}), do: Client.stop(client)
  def close(session) when is_pid(session), do: Session.close(session)

  @doc "Gets the session ID"
  @spec get_session_id(session()) :: {:ok, String.t()} | {:error, term()}
  def get_session_id({:control_client, _client}) do
    {:error, :not_supported}  # TODO: Extract from first message
  end
  def get_session_id(session) when is_pid(session) do
    Session.get_session_id(session)
  end
end
```

**TDD: Write Tests** (~10 tests):

```elixir
describe "transport routing" do
  test "uses Session for simple streaming" do
    {:ok, session} = Streaming.start_session()
    assert is_pid(session)
  end

  test "uses Client for streaming with hooks" do
    callback = fn _, _, _ -> %{behavior: :allow} end
    opts = %Options{
      hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}
    }

    {:ok, session} = Streaming.start_session(opts)
    assert match?({:control_client, _}, session)
  end

  # Add 8+ more tests
end
```

**Day 7 Deliverable**:
- ✅ Streaming facade integrated (~180 LOC)
- ✅ 10 new tests passing

---

#### Day 8: EventAdapter Utilities

Create helper module for consuming mixed streams:

```elixir
# FILE: lib/claude_agent_sdk/streaming/event_adapter.ex
defmodule ClaudeAgentSDK.Streaming.EventAdapter do
  @moduledoc """
  Utilities for heterogeneous event/message streams.

  When streaming with control features, the stream contains
  both streaming events and Message structs. These helpers
  normalize and filter streams.
  """

  alias ClaudeAgentSDK.Message

  @doc """
  Normalizes mixed stream to consistent event maps.
  """
  def to_events(stream) do
    Stream.map(stream, &normalize/1)
  end

  @doc "Filters to only text deltas"
  def text_only(stream) do
    Stream.filter(stream, &is_text_event?/1)
  end

  @doc "Accumulates text from deltas"
  def accumulate_text(stream) do
    Stream.scan(stream, "", fn event, acc ->
      case event do
        %{type: :text_delta, text: text} -> acc <> text
        %{accumulated: text} when is_binary(text) -> text
        _ -> acc
      end
    end)
  end

  # Implementation per design doc...
end
```

Write 25 tests.

**Day 8 Deliverable**:
- ✅ EventAdapter complete (~120 LOC)
- ✅ 25 new tests passing

---

### Phase 3: Integration & Hardening (Days 9-11)

#### Day 9: Integration Testing

Implement 20 integration scenarios with MockCLI:

```elixir
@tag :integration
test "interleaved text and tool execution" do
  # Mock CLI that emits:
  # 1. text_delta("Running")
  # 2. tool_use(bash)
  # 3. text_delta("Done")
  # 4. message_stop

  # Verify both event types received
  # Verify order preserved
end
```

See `04_TESTING_STRATEGY.md` for all 20 scenarios.

**Day 9 Deliverable**:
- ✅ 20 integration tests passing

---

#### Day 10: Performance Validation

Benchmark router and streaming:

```elixir
# Router overhead
{time, _} = :timer.tc(fn ->
  for _ <- 1..1000, do: StreamingRouter.select_transport(opts)
end)
avg_us = time / 1000
# Target: <100μs
```

**Day 10 Deliverable**:
- ✅ Performance validated (<10% regression)

---

#### Day 11: Edge Cases

Test error scenarios:
- Malformed events
- CLI crashes
- Subscriber dies
- Queue overflow

**Day 11 Deliverable**:
- ✅ Edge case tests passing
- ✅ No memory leaks

---

### Phase 4: Finalization (Days 12-14)

#### Day 12: Documentation

Update:
- README with streaming + tools examples
- CHANGELOG for v0.6.0
- Module docs
- Architecture docs

Create 3+ working examples.

---

#### Day 13: Live CLI Validation

```bash
LIVE_TESTS=true mix test --include live
# 5 tests with real Claude CLI
```

Test examples with real CLI.

---

#### Day 14: Quality Gates & Release

Run full suite:

```bash
mix format
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test --include integration
mix test --cover
```

All must pass. Create PR.

---

## TDD WORKFLOW (MANDATORY)

For EVERY feature:

1. **RED**: Write failing test
2. **GREEN**: Implement minimum code to pass
3. **REFACTOR**: Clean up, extract functions
4. **REPEAT**: Next test

Example:

```elixir
# 1. RED - Write test
test "router selects CLI for empty options" do
  assert :streaming_session = Router.select_transport(%Options{})
end
# Run: FAIL - function undefined

# 2. GREEN - Implement
def select_transport(_), do: :streaming_session
# Run: PASS

# 3. REFACTOR - (none needed yet)

# 4. REPEAT - Next test
test "router selects control for hooks" do
  # ...
end
```

---

## CRITICAL SUCCESS CRITERIA

### Functional Requirements (ALL MUST PASS)

- [ ] Router correctly selects transport based on options
- [ ] Control client emits partial message events
- [ ] Text deltas and tool calls stream interleaved
- [ ] Hooks invoked correctly during streaming
- [ ] SDK MCP tools executable while streaming
- [ ] Permission callbacks work with streaming
- [ ] CLI-only path performance maintained
- [ ] All 477 existing tests pass unchanged

### Non-Functional Requirements

- [ ] Router overhead <1ms
- [ ] Control streaming latency <350ms to first event
- [ ] Zero breaking changes
- [ ] Test coverage >90% for new code
- [ ] Documentation complete
- [ ] Dialyzer clean, Credo clean

---

## CONTINGENCY PLANS

### If CLI Incompatible (Day 1 Gate Failure)

**STOP IMMEDIATELY**. Options:
1. Document minimum CLI version required
2. Defer feature to CLI v2.1+
3. Propose CLI enhancement to Anthropic

### If Behind Schedule

- Day 5: Drop EventAdapter to Phase 4
- Day 9: Add buffer day for debugging
- Day 10: Accept 10-15% regression if unavoidable

### If Integration Tests Fail >50%

Add Day 9.5 for debugging. Review assumptions.

---

## FINAL CHECKLIST

Before submitting PR:

- [ ] All 620+ tests passing
- [ ] Zero compiler warnings
- [ ] Zero Credo issues
- [ ] Zero Dialyzer errors
- [ ] >90% test coverage
- [ ] Documentation complete
- [ ] Examples working
- [ ] CHANGELOG updated
- [ ] Self-review complete
- [ ] No TODOs in code

---

## RESOURCES

- Design docs: `docs/20251025/claude_streaming_tools/*.md`
- Source: `lib/claude_agent_sdk/{streaming.ex,client.ex,options.ex}`
- Tests: `test/claude_agent_sdk/`
- Existing infrastructure: 477 passing tests to reference

---

## QUESTIONS? BLOCKERS?

If stuck:
1. Re-read relevant design doc section
2. Check existing code patterns
3. Look at similar tests
4. Ask for clarification

**DO NOT PROCEED** past Day 1 if CLI verification fails.

---

**GOOD LUCK! Follow TDD strictly and you'll succeed.**
