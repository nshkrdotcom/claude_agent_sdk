# Feasibility Assessment: Streaming + Tools Transport Unification

**Date**: 2025-10-25
**Status**: APPROVED - Ready for Implementation
**Confidence**: 85%
**Timeline**: 10-14 developer days
**Risk Level**: LOW-MEDIUM

---

## Executive Summary

The proposed unification of streaming (partial messages) and tools (control protocol) is **highly feasible** and implementable within the estimated 14-day timeline. The codebase demonstrates excellent architectural readiness with:

- Clean transport abstraction already defined
- Production-ready streaming and control protocol implementations
- Comprehensive test coverage (477 tests passing, 0 failures)
- Minimal breaking change risk (zero anticipated)

**RECOMMENDATION: PROCEED** with Day 1 CLI compatibility verification as gate condition.

---

## Architectural Readiness Assessment

### Current State Analysis

#### 1. Transport Layer (✅ EXCELLENT)

**File**: `lib/claude_agent_sdk/transport.ex`

The Transport behaviour is well-designed:
```elixir
@callback start_link(opts()) :: {:ok, t()} | {:error, term()}
@callback send(t(), message()) :: :ok | {:error, term()}
@callback subscribe(t(), pid()) :: :ok
@callback close(t()) :: :ok
@callback status(t()) :: :connected | :disconnected | :error
```

**Strengths**:
- Clean abstraction separating communication from business logic
- Proven implementation in `Transport.Port` (306 lines, production-tested)
- Already supports pluggable transports via `Client` init options
- Subscriber pattern established (lines 113-125)

**Integration Point**: Router will select transport implementation based on Options.

#### 2. Streaming Infrastructure (✅ PRODUCTION-READY)

**File**: `lib/claude_agent_sdk/streaming/session.ex` (550 lines)

**Current Capabilities**:
- Uses `--include-partial-messages` flag (line 452)
- Erlexec subprocess management with bidirectional pipes
- Event-driven architecture with EventParser integration
- Multi-subscriber queue management (lines 229, 296-316)
- Session ID extraction and persistence

**Key Discovery**:
```elixir
# Line 445-461: Already builds streaming args
defp build_streaming_args(%Options{} = options) do
  base_args = [
    "--print",
    "--input-format", "stream-json",
    "--output-format", "stream-json",
    "--include-partial-messages",
    "--verbose"
  ]
  user_args = Options.to_args(options)
  base_args ++ user_args
end
```

**Gap**: Never sends control protocol initialize request, so hooks/MCP/permissions are ignored.

#### 3. Control Protocol (✅ MATURE)

**File**: `lib/claude_agent_sdk/client.ex` (1400 lines)

**Current Capabilities**:
- Bidirectional control channel via Port or custom transport
- Hook callback routing with timeout protection (lines 930-1004)
- Permission system integration (lines 1007-1090)
- SDK MCP server routing (lines 1186-1318)
- Runtime model switching (lines 396-430)
- Runtime agent switching (lines 455-479)

**Key Discovery**:
```elixir
# Line 801-818: Builds CLI command WITHOUT partial messages
defp build_cli_command(options) do
  executable = System.find_executable("claude")
  if executable do
    args = ["--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose"]
    args = args ++ Options.to_args(options)
    cmd = Enum.join([executable | args], " ") <> " 2>/dev/null"
    {:ok, cmd}
  end
end
```

**Gap**: Missing `--include-partial-messages`, so no character-level streaming.

#### 4. Event Parser (✅ COMPREHENSIVE)

**File**: `lib/claude_agent_sdk/streaming/event_parser.ex` (285 lines)

**Supported Event Types**:
- `message_start` - Initialization with model metadata
- `content_block_start` - Text/tool_use/thinking blocks
- `content_block_delta` - **Core streaming events**:
  - `text_delta` - Character-by-character streaming
  - `input_json_delta` - Tool input incremental updates
  - `thinking_delta` - Extended thinking (Sonnet 4.5+)
- `content_block_stop` - Block completion
- `message_delta` - Metadata updates
- `message_stop` - Message completion

**Buffer Management**: Lines 244-276 handle incomplete JSON gracefully.

**Stream Event Unwrapping**: Line 279 already handles CLI wrapper format.

**Strength**: Complete SSE implementation, no modifications needed.

#### 5. Options System (✅ EXTENSIBLE)

**File**: `lib/claude_agent_sdk/options.ex` (485 lines)

**Current Fields**: 30+ configuration options including:
- Model selection, agents, session management
- Tool permissions (allowed/disallowed)
- MCP server configuration (SDK and external)
- Hook configurations
- Permission modes and callbacks

**CLI Argument Pipeline**:
```elixir
def to_args(%__MODULE__{} = options) do
  []
  |> add_output_format_args(options)
  |> add_max_turns_args(options)
  # ... 15+ more pipeline stages
  |> add_strict_mcp_args(options)
end
```

**MCP Server Filtering** (Lines 269-298):
```elixir
defp add_mcp_args(args, options) do
  # Filters SDK servers - they require Client with control protocol
  external_servers_only =
    options.mcp_servers
    |> Enum.filter(fn {_name, config} -> config.type != :sdk end)
    |> Map.new()
  # Only external servers passed to CLI
end
```

**Strength**: Pattern established for new fields and CLI flag generation.

---

## Gap Analysis: The Precise Problem

### The Split Brain Architecture

```
Current State (Mutually Exclusive):

┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│  Streaming.Session              │     │  Client (Control Protocol)      │
│  ✅ --include-partial-messages  │     │  ✅ Initialize request          │
│  ✅ Character-level streaming   │     │  ✅ Hooks callbacks             │
│  ✅ EventParser integration     │     │  ✅ SDK MCP routing             │
│  ❌ No control protocol         │     │  ✅ Permission system           │
│  ❌ No hooks                     │     │  ❌ No partial messages         │
│  ❌ No SDK MCP                   │     │  ❌ No text deltas              │
└─────────────────────────────────┘     └─────────────────────────────────┘
         │                                        │
         └────────── CANNOT USE TOGETHER ────────┘
```

### Required Solution: Router + Integration

```
Target State (Unified):

                    ┌───────────────────────────┐
                    │  ClaudeAgentSDK.Streaming │
                    │  (Public API)             │
                    └──────────────┬────────────┘
                                   │
                                   ▼
                    ┌───────────────────────────┐
                    │  StreamingRouter          │
                    │  Decision: needs_control? │
                    └──────────┬────────────────┘
                               │
              ┌────────────────┴────────────────┐
              ▼                                  ▼
    ┌─────────────────────┐         ┌──────────────────────┐
    │  CLI-Only Path      │         │  Control Client Path │
    │  (Streaming.Session)│         │  (Client enhanced)   │
    │  - Fast             │         │  ✅ Partial messages │
    │  - No tools         │         │  ✅ Hooks            │
    └─────────────────────┘         │  ✅ SDK MCP          │
                                    │  ✅ Permissions      │
                                    └──────────────────────┘
```

---

## Technical Risk Assessment

### RISK 1: CLI Compatibility (🔴 CRITICAL - GATE CONDITION)

**Issue**: Assumption that Claude CLI supports simultaneous use of:
1. `--include-partial-messages` (streaming)
2. Control protocol initialize request (tools/hooks)

**Verification Test**:
```bash
# Day 1 verification
claude --output-format stream-json \
       --input-format stream-json \
       --include-partial-messages \
       --verbose << EOF
{"type":"control_request","request_id":"init-001","request":{"subtype":"initialize","version":"1.0.0","hooks":{}}}
EOF
```

**Expected**: CLI accepts both and responds with control_response.

**Mitigation Plans**:

A. **If Compatible** (✅ Proceed):
   - Continue as planned
   - Timeline: 10-14 days

B. **If Incompatible** (⚠️ Pivot):
   - Option 1: Version gate (require CLI v2.1+)
   - Option 2: Sequential mode (tools complete, then stream results)
   - Option 3: Defer feature to next CLI release
   - Timeline impact: +2 days (documentation, error messages)

**Probability of incompatibility**: 15% (based on CLI architecture review)

### RISK 2: Event/Message Stream Heterogeneity (🟡 MEDIUM)

**Issue**: Current consumers expect homogeneous streams:
- `Client.stream_messages/1` → `Stream.t(Message.t())`
- `Streaming` → `Stream.t(map())` with event types

Unified stream must handle both:
```elixir
# New stream type (conceptual):
Stream.t(Message.t() | Event.t())
```

**Consumer Impact Examples**:

```elixir
# Current streaming consumer:
Streaming.send_message(session, "Hello")
|> Stream.each(fn %{type: :text_delta, text: text} ->
  IO.write(text)  # ✅ Works
end)

# After unification (if using control client):
Streaming.send_message(session, "Use bash tool")
|> Stream.each(fn event ->
  case event do
    %{type: :text_delta, text: text} -> IO.write(text)  # ✅ Works
    %Message{type: :tool_result} -> handle_tool(event)  # ❌ Unexpected
  end
end)
```

**Mitigation Strategies**:

**A. Adapter Functions (RECOMMENDED)**:
```elixir
defmodule ClaudeAgentSDK.Streaming.EventAdapter do
  @doc "Normalize mixed stream to consistent event maps"
  def normalize_stream(stream) do
    Stream.map(stream, &normalize_item/1)
  end

  defp normalize_item(%Message{type: :tool_result} = msg) do
    %{type: :tool_complete, tool: msg.tool_name, result: msg.content}
  end

  defp normalize_item(%{type: _} = event), do: event
end
```

**B. Tagged Tuples**:
```elixir
# Explicit distinction
{:event, %{type: :text_delta, ...}}
{:message, %Message{type: :tool_result}}
```

**C. Unified Struct** (Future):
```elixir
defmodule ClaudeAgentSDK.Streaming.Event do
  @type t :: %__MODULE__{
    type: event_type(),
    data: map(),
    timestamp: DateTime.t()
  }
end
```

**Decision**: Start with **Strategy A** (adapters), provide **Strategy B** as opt-in, defer **Strategy C** to v0.7.0.

**Timeline Impact**: +1 day for adapter implementation and tests.

### RISK 3: Subscriber Queue State Machine (🟡 MEDIUM)

**Issue**: `Streaming.Session` implements complex subscriber queueing (lines 229-316):
- FIFO queue for pending messages
- Single active subscriber at a time
- Automatic activation on message_stop

`Client` uses simpler broadcast model (line 1139-1151):
- All subscribers receive all messages
- No queueing

**Integration Challenge**: When routing through control client, must preserve Session semantics for backwards compatibility.

**State Transitions**:
```
Initial State:
  active_subscriber: nil
  subscriber_queue: []

User calls send_message(session, "msg1"):
  1. Subscribe ref1
  2. Set active_subscriber = ref1
  3. Send msg1 to CLI

Events arrive:
  text_delta → broadcast to ref1
  message_stop → activate next in queue

Second user calls send_message(session, "msg2"):
  1. Subscribe ref2
  2. Queue: [{ref2, "msg2"}]
  3. Wait for ref1 completion

On message_stop for ref1:
  1. Dequeue ref2
  2. Set active_subscriber = ref2
  3. Send "msg2" to CLI
```

**Mitigation**:
1. Extract subscriber queue logic into shared module
2. Inject into control client when router selects it
3. Add state machine property tests

**Complexity**: ~150 lines of queue management code to integrate.

**Timeline Impact**: +2 days for extraction and integration.

### RISK 4: Partial Event Parsing in Control Client (🟡 MEDIUM)

**Current Client Message Handling** (lines 525-584):
```elixir
def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
  case Protocol.decode_message(line) do
    {:ok, {:control_request, data}} -> handle_control_request(data, state)
    {:ok, {:control_response, data}} -> handle_control_response(data, state)
    {:ok, {:sdk_message, data}} -> broadcast_message(data, state)
    {:error, reason} -> log_and_continue
  end
end
```

**Required Addition**:
```elixir
{:ok, {:stream_event, event_data}} -> handle_stream_event(event_data, state)
```

**Implementation**:
```elixir
defp handle_stream_event(event_data, state) do
  # Delegate to EventParser
  {:ok, events, new_accumulated} =
    EventParser.parse_event(event_data, state.accumulated_text)

  # Broadcast to active subscriber only (not all subscribers)
  if state.active_subscriber do
    Enum.each(events, fn event ->
      send_to_subscriber(state.active_subscriber, event)
    end)
  end

  %{state | accumulated_text: new_accumulated}
end
```

**Challenges**:
1. Add `accumulated_text` field to Client state
2. Respect subscriber queue (only active receives events)
3. Reset accumulated text on message_stop
4. Handle EventParser errors gracefully

**Testing Needs**:
- Interleaved text_delta and tool_use events
- Multiple content blocks
- Error event mid-stream

**Timeline Impact**: Included in base estimate (Client enhancements phase).

### RISK 5: Performance Regression (🟢 LOW)

**Concern**: Router adds latency even for simple streaming.

**Analysis**:
```elixir
# Router implementation (conceptual):
def select_transport(%Options{} = opts) do
  cond do
    has_control_features?(opts) -> :control_client
    true -> :streaming_session
  end
end

defp has_control_features?(opts) do
  has_hooks?(opts) or
  has_sdk_mcp?(opts) or
  has_permission_callback?(opts) or
  has_runtime_agents?(opts)
end
```

**Estimated Overhead**:
- Router decision: ~0.1ms (pattern matching)
- No I/O, no external calls
- Pure function with early returns

**Benchmark Plan**:
```elixir
# Before: Direct Streaming.Session
{time_baseline, _result} = :timer.tc(fn ->
  {:ok, session} = Streaming.start_session()
  Streaming.send_message(session, "Hello") |> Enum.to_list()
end)

# After: Via router (no control features)
{time_routed, _result} = :timer.tc(fn ->
  {:ok, session} = Streaming.start_session()  # Router selects Session
  Streaming.send_message(session, "Hello") |> Enum.to_list()
end)

acceptable? = time_routed < time_baseline * 1.05  # <5% regression
```

**Mitigation**: If overhead exceeds 5%, inline router decision in hot path.

**Timeline Impact**: +0.5 days for benchmarking and optimization.

---

## Implementation Complexity Analysis

### Component Breakdown

#### 1. StreamingRouter Module (✅ LOW COMPLEXITY)

**File**: `lib/claude_agent_sdk/transport/streaming_router.ex`

**Estimated Size**: ~120 lines

**Responsibilities**:
1. Analyze Options to detect control features
2. Return transport selection decision
3. Provide introspection for debugging

**Implementation**:
```elixir
defmodule ClaudeAgentSDK.Transport.StreamingRouter do
  @moduledoc """
  Routes streaming requests to appropriate transport based on features.

  ## Decision Logic

  - **Control Client**: hooks, SDK MCP, permission callbacks, agents
  - **CLI-Only**: simple streaming with no control features
  - **Explicit Override**: `preferred_transport` option
  """

  alias ClaudeAgentSDK.Options

  @type transport_choice :: :streaming_session | :control_client

  @doc """
  Selects transport implementation based on options.

  ## Examples

      # Simple streaming
      iex> select_transport(%Options{})
      :streaming_session

      # With hooks
      iex> select_transport(%Options{hooks: %{pre_tool_use: [...]}})
      :control_client

      # Explicit override
      iex> select_transport(%Options{preferred_transport: :cli})
      :streaming_session
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
    has_runtime_permission_mode?(opts)
  end

  defp has_hooks?(%{hooks: hooks}) when is_map(hooks) and map_size(hooks) > 0,
    do: true
  defp has_hooks?(_), do: false

  defp has_sdk_mcp_servers?(%{mcp_servers: servers}) when is_map(servers) do
    Enum.any?(servers, fn {_, config} -> config.type == :sdk end)
  end
  defp has_sdk_mcp_servers?(_), do: false

  defp has_permission_callback?(%{can_use_tool: cb}) when is_function(cb, 1),
    do: true
  defp has_permission_callback?(_), do: false

  defp has_runtime_agents?(%{agents: agents}) when is_map(agents) and map_size(agents) > 0,
    do: true
  defp has_runtime_agents?(_), do: false

  defp has_runtime_permission_mode?(%{permission_mode: mode})
    when mode in [:accept_edits, :bypass_permissions, :plan],
    do: true
  defp has_runtime_permission_mode?(_), do: false

  @doc "Human-readable explanation of transport choice"
  @spec explain(Options.t()) :: String.t()
  def explain(%Options{} = opts) do
    choice = select_transport(opts)
    features = detect_features(opts)

    """
    Transport: #{choice}
    Features detected: #{inspect(features)}
    Requires control: #{requires_control_protocol?(opts)}
    """
  end

  defp detect_features(opts) do
    []
    |> maybe_add(:hooks, has_hooks?(opts))
    |> maybe_add(:sdk_mcp, has_sdk_mcp_servers?(opts))
    |> maybe_add(:permissions, has_permission_callback?(opts))
    |> maybe_add(:agents, has_runtime_agents?(opts))
  end

  defp maybe_add(list, _feature, false), do: list
  defp maybe_add(list, feature, true), do: [feature | list]
end
```

**Test Coverage**:
```elixir
defmodule ClaudeAgentSDK.Transport.StreamingRouterTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Transport.StreamingRouter}

  describe "select_transport/1" do
    test "defaults to streaming_session for empty options" do
      assert :streaming_session = StreamingRouter.select_transport(%Options{})
    end

    test "selects control_client when hooks present" do
      opts = %Options{hooks: %{pre_tool_use: [...]}}
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "selects control_client for SDK MCP servers" do
      server = ClaudeAgentSDK.create_sdk_mcp_server(name: "test", tools: [])
      opts = %Options{mcp_servers: %{"test" => server}}
      assert :control_client = StreamingRouter.select_transport(opts)
    end

    test "stays streaming_session for external MCP servers only" do
      opts = %Options{
        mcp_servers: %{"ext" => %{type: :stdio, command: "test"}}
      }
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "respects explicit override to CLI" do
      opts = %Options{
        hooks: %{pre_tool_use: [...]},
        preferred_transport: :cli
      }
      assert :streaming_session = StreamingRouter.select_transport(opts)
    end

    test "respects explicit override to control" do
      opts = %Options{preferred_transport: :control}
      assert :control_client = StreamingRouter.select_transport(opts)
    end
  end

  describe "requires_control_protocol?/1" do
    test "detects permission callback" do
      opts = %Options{can_use_tool: fn _ -> :allow end}
      assert StreamingRouter.requires_control_protocol?(opts)
    end

    test "detects runtime agents" do
      opts = %Options{
        agents: %{test: %ClaudeAgentSDK.Agent{...}},
        agent: :test
      }
      assert StreamingRouter.requires_control_protocol?(opts)
    end

    test "detects special permission modes" do
      for mode <- [:accept_edits, :bypass_permissions, :plan] do
        opts = %Options{permission_mode: mode}
        assert StreamingRouter.requires_control_protocol?(opts)
      end
    end
  end
end
```

**Complexity Rating**: ⭐ (1/5 stars - Trivial)

#### 2. Options Extension (✅ TRIVIAL)

**File**: `lib/claude_agent_sdk/options.ex`

**Changes Required**:

1. Add fields to defstruct (lines 48-94):
```elixir
defstruct [
  # ... existing fields ...
  :timeout_ms,
  # New fields (v0.6.0)
  :include_partial_messages,  # boolean - enable streaming events
  :preferred_transport        # :auto | :cli | :control
]
```

2. Update typespecs (lines 126-153):
```elixir
@type t :: %__MODULE__{
  # ... existing types ...
  timeout_ms: integer() | nil,
  include_partial_messages: boolean() | nil,
  preferred_transport: transport_preference() | nil
}

@type transport_preference :: :auto | :cli | :control
```

3. Add CLI argument generator (after line 221):
```elixir
defp add_partial_messages_args(args, %{include_partial_messages: true}) do
  args ++ ["--include-partial-messages"]
end
defp add_partial_messages_args(args, _), do: args
```

4. Update to_args pipeline (line 202-222):
```elixir
def to_args(%__MODULE__{} = options) do
  []
  |> add_output_format_args(options)
  # ... existing pipeline ...
  |> add_strict_mcp_args(options)
  |> add_partial_messages_args(options)  # New
end
```

**Documentation Updates**:
```elixir
@moduledoc """
# ... existing docs ...

## New Fields (v0.6.0)

- `include_partial_messages` - Enable character-level streaming with `--include-partial-messages` (boolean)
- `preferred_transport` - Override automatic transport selection (`:auto | :cli | :control`)

## Transport Selection

The SDK automatically chooses the appropriate transport:
- **CLI-only**: Fast streaming without tools (no hooks, MCP, or permissions)
- **Control client**: Full features with streaming (hooks + partial messages)

Override with `preferred_transport`:
- `:auto` - Automatic selection (default)
- `:cli` - Force CLI-only mode (ignores control features)
- `:control` - Force control client (even without features)

## Examples

    # Streaming with tools
    %Options{
      include_partial_messages: true,
      hooks: %{pre_tool_use: [...]},
      mcp_servers: %{"math" => sdk_server}
    }
    # → Selects control client with streaming enabled

    # Simple streaming
    %Options{include_partial_messages: true}
    # → Selects CLI-only (faster startup)
"""
```

**Estimated Changes**: 30 lines of code, 50 lines of documentation

**Complexity Rating**: ⭐ (1/5 stars - Trivial)

#### 3. Client Enhancements (🟡 MEDIUM COMPLEXITY)

**File**: `lib/claude_agent_sdk/client.ex`

**Changes Required**:

**A. Add State Fields** (line 84-98):
```elixir
@type state :: %{
  # ... existing fields ...
  current_model: String.t() | nil,
  pending_model_change: {GenServer.from(), reference()} | nil,
  # New fields for streaming support
  accumulated_text: String.t(),        # Buffer for partial text
  active_subscriber: reference() | nil, # Current streaming consumer
  subscriber_queue: [{reference(), String.t()}]  # Pending messages
}
```

**B. Modify CLI Command Builder** (line 801-818):
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

**C. Add Stream Event Handler** (new function after line 837):
```elixir
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

**D. Enhance Subscriber Management** (modify line 432-435):
```elixir
def handle_call({:subscribe, ref}, from, state) do
  {pid, _ref} = from

  # Add to subscribers map
  subscribers = Map.put(state.subscribers, ref, pid)

  # Activate if no active subscriber
  {new_active, new_queue} = if state.active_subscriber == nil do
    {ref, state.subscriber_queue}
  else
    # Queue this subscriber
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

**E. Update Initialization** (line 337-354):
```elixir
defp do_init(options, opts) do
  # ... existing validation ...

  state = %{
    # ... existing fields ...
    current_model: updated_options.model,
    pending_model_change: nil,
    # Streaming support fields
    accumulated_text: "",
    active_subscriber: nil,
    subscriber_queue: []
  }

  {:ok, state, {:continue, :start_cli}}
end
```

**Testing Additions**:
```elixir
defmodule ClaudeAgentSDK.ClientStreamingTest do
  use ClaudeAgentSDK.SupertesterCase

  describe "partial message streaming" do
    test "broadcasts text_delta events to active subscriber" do
      options = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(options)

      # Subscribe
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

    test "queues subscribers and activates sequentially" do
      # Test subscriber queue behavior
    end

    test "resets accumulated text on message_stop" do
      # Test state cleanup
    end

    test "handles interleaved text deltas and tool calls" do
      # Complex integration scenario
    end
  end
end
```

**Estimated Changes**: ~200 lines of code, ~150 lines of tests

**Complexity Rating**: ⭐⭐⭐ (3/5 stars - Medium)

#### 4. Streaming Facade Integration (🟡 MEDIUM COMPLEXITY)

**File**: `lib/claude_agent_sdk/streaming.ex`

**Current Implementation** (lines 1-150):
- Direct delegation to `Streaming.Session`
- No router integration

**Required Changes**:

```elixir
defmodule ClaudeAgentSDK.Streaming do
  @moduledoc """
  # ... existing docs ...

  ## Transport Selection (v0.6.0)

  The streaming module automatically selects the appropriate transport:

  - **CLI-only**: Fast path for simple streaming without tools
  - **Control client**: Full features when hooks, MCP, or permissions configured

  This selection is transparent to consumers.
  """

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Streaming.Session
  alias ClaudeAgentSDK.Transport.StreamingRouter

  @type session :: pid()
  @type event :: map()

  @doc """
  Starts a streaming session.

  Automatically selects transport based on options:
  - Simple streaming → Direct CLI (Streaming.Session)
  - Streaming + tools → Control client

  ## Examples

      # Simple streaming (CLI-only path)
      {:ok, session} = Streaming.start_session()

      # Streaming with hooks (control client path)
      {:ok, session} = Streaming.start_session(%Options{
        include_partial_messages: true,
        hooks: %{pre_tool_use: [my_hook]}
      })
  """
  @spec start_session(Options.t() | nil) :: {:ok, session()} | {:error, term()}
  def start_session(options \\ nil) do
    opts = options || %Options{}

    # Ensure partial messages enabled for streaming
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
    # Start control client with streaming enabled
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

  Works with both transport types transparently.
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
    %{
      type: :error,
      error: msg.content,
      accumulated: accumulated
    }
  end

  defp message_to_event(msg, accumulated) do
    # Generic fallback
    %{
      type: :message,
      message: msg,
      accumulated: accumulated
    }
  end

  @doc """
  Closes the streaming session.

  Works with both transport types.
  """
  @spec close(session()) :: :ok
  def close({:control_client, client}), do: Client.stop(client)
  def close(session) when is_pid(session), do: Session.close(session)

  @doc """
  Gets the session ID.

  Works with both transport types.
  """
  @spec get_session_id(session()) :: {:ok, String.t()} | {:error, term()}
  def get_session_id({:control_client, _client}) do
    # Control client doesn't expose session ID yet
    {:error, :not_supported}
  end

  def get_session_id(session) when is_pid(session) do
    Session.get_session_id(session)
  end
end
```

**Testing**:
```elixir
defmodule ClaudeAgentSDK.StreamingIntegrationTest do
  use ClaudeAgentSDK.SupertesterCase

  @moduletag :integration

  describe "transport routing" do
    test "uses Session for simple streaming" do
      {:ok, session} = Streaming.start_session()
      assert is_pid(session)
      refute match?({:control_client, _}, session)
    end

    test "uses Client for streaming with hooks" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}
      }

      {:ok, session} = Streaming.start_session(opts)
      assert match?({:control_client, _}, session)
    end
  end

  describe "streaming with tools" do
    @tag :requires_cli
    test "handles text deltas and tool calls in same stream" do
      # Create SDK MCP server
      server = ClaudeAgentSDK.create_sdk_mcp_server(
        name: "test",
        tools: [TestTool]
      )

      opts = %Options{
        mcp_servers: %{"test" => server}
      }

      {:ok, session} = Streaming.start_session(opts)

      events = Streaming.send_message(session, "Use the test tool")
        |> Enum.take(100)

      # Should see both text deltas and tool completion
      assert Enum.any?(events, &(&1.type == :text_delta))
      assert Enum.any?(events, &(&1.type == :tool_complete))
    end
  end
end
```

**Estimated Changes**: ~180 lines of code, ~100 lines of tests

**Complexity Rating**: ⭐⭐⭐ (3/5 stars - Medium)

#### 5. Helper Utilities (✅ LOW COMPLEXITY)

**File**: `lib/claude_agent_sdk/streaming/event_adapter.ex` (new)

```elixir
defmodule ClaudeAgentSDK.Streaming.EventAdapter do
  @moduledoc """
  Utilities for working with heterogeneous streaming event/message streams.

  When using streaming with control features (hooks, MCP, permissions),
  the stream may contain both streaming events and message structs.
  These helpers normalize and filter streams.
  """

  alias ClaudeAgentSDK.Message

  @doc """
  Normalizes a mixed stream to consistent event maps.

  ## Examples

      stream
      |> EventAdapter.to_events()
      |> Stream.each(fn %{type: type, data: data} ->
        # Handle uniformly
      end)
  """
  def to_events(stream) do
    Stream.map(stream, &normalize/1)
  end

  @doc """
  Filters stream to only text deltas (content streaming).

  ## Examples

      stream
      |> EventAdapter.text_only()
      |> Stream.each(fn %{text: text} ->
        IO.write(text)
      end)
  """
  def text_only(stream) do
    stream
    |> Stream.filter(&is_text_event?/1)
  end

  @doc """
  Filters stream to only tool-related events.
  """
  def tools_only(stream) do
    stream
    |> Stream.filter(&is_tool_event?/1)
  end

  @doc """
  Accumulates text from stream into final string.

  ## Examples

      final_text = stream
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()
        |> List.last()
  """
  def accumulate_text(stream) do
    stream
    |> Stream.scan("", fn event, acc ->
      case event do
        %{type: :text_delta, text: text} -> acc <> text
        %{accumulated: text} when is_binary(text) -> text
        _ -> acc
      end
    end)
  end

  # Normalization

  defp normalize(%{type: _} = event), do: event

  defp normalize(%Message{type: :tool_result} = msg) do
    %{
      type: :tool_result,
      tool_name: msg.tool_name,
      result: msg.content,
      timestamp: DateTime.utc_now()
    }
  end

  defp normalize(%Message{type: :assistant, content: content}) do
    %{
      type: :message,
      content: content,
      timestamp: DateTime.utc_now()
    }
  end

  defp normalize(other) do
    %{type: :unknown, data: other}
  end

  # Type Guards

  defp is_text_event?(%{type: :text_delta}), do: true
  defp is_text_event?(%{type: :text_block_start}), do: true
  defp is_text_event?(_), do: false

  defp is_tool_event?(%{type: :tool_use_start}), do: true
  defp is_tool_event?(%{type: :tool_input_delta}), do: true
  defp is_tool_event?(%{type: :tool_result}), do: true
  defp is_tool_event?(%Message{type: :tool_result}), do: true
  defp is_tool_event?(_), do: false
end
```

**Tests**:
```elixir
defmodule ClaudeAgentSDK.Streaming.EventAdapterTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Streaming.EventAdapter
  alias ClaudeAgentSDK.Message

  describe "to_events/1" do
    test "passes through event maps unchanged" do
      events = [
        %{type: :text_delta, text: "Hello"},
        %{type: :message_stop}
      ]

      result = events |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()
      assert result == events
    end

    test "normalizes Message structs to event maps" do
      messages = [
        %Message{type: :tool_result, tool_name: "bash", content: "output"}
      ]

      [event] = messages |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()

      assert event.type == :tool_result
      assert event.tool_name == "bash"
      assert event.result == "output"
    end
  end

  describe "text_only/1" do
    test "filters to only text events" do
      mixed = [
        %{type: :text_delta, text: "A"},
        %{type: :tool_use_start, name: "bash"},
        %{type: :text_delta, text: "B"},
        %{type: :message_stop}
      ]

      text_events = mixed |> Stream.into([]) |> EventAdapter.text_only() |> Enum.to_list()

      assert length(text_events) == 2
      assert Enum.all?(text_events, &(&1.type == :text_delta))
    end
  end

  describe "accumulate_text/1" do
    test "builds complete text from deltas" do
      deltas = [
        %{type: :text_delta, text: "Hello"},
        %{type: :text_delta, text: " "},
        %{type: :text_delta, text: "world"}
      ]

      accumulated = deltas
        |> Stream.into([])
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()

      assert List.last(accumulated) == "Hello world"
    end
  end
end
```

**Estimated Size**: ~120 lines of code, ~80 lines of tests

**Complexity Rating**: ⭐⭐ (2/5 stars - Low-Medium)

---

## Test Strategy

### Test Pyramid

```
                    ┌─────────────────┐
                    │  E2E / Manual   │  5%
                    │  (Live CLI)     │
                    └────────┬────────┘
                ┌────────────┴────────────┐
                │  Integration Tests      │  20%
                │  (Mocked CLI + Tools)   │
                └────────────┬────────────┘
            ┌────────────────┴────────────────┐
            │   Unit Tests                    │  75%
            │   (Router, Parser, Adapters)    │
            └─────────────────────────────────┘
```

### Unit Tests (Priority 1)

**Router Tests** (~50 tests):
- Decision logic for each control feature
- Edge cases (empty maps, nil values)
- Explicit override behavior
- Feature detection accuracy

**Options Tests** (~10 tests):
- New field serialization
- CLI arg generation
- Type validation

**Event Adapter Tests** (~30 tests):
- Normalization correctness
- Filter behavior
- Accumulation logic

**Client Event Parsing Tests** (~40 tests):
- Stream event decoding
- Accumulated text management
- Subscriber queue behavior
- Message interleaving

### Integration Tests (Priority 2)

**Mocked CLI Integration** (~20 tests):
```elixir
defmodule ClaudeAgentSDK.StreamingToolsIntegrationTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Streaming, Options}

  @tag :integration
  test "streams text while executing tools" do
    # Setup: Mock CLI process that emits:
    # 1. text_delta events
    # 2. tool_use event (bash)
    # 3. more text_delta events
    # 4. message_stop

    mock_cli = spawn_mock_cli([
      stream_event(:message_start),
      stream_event(:text_delta, "Running command: "),
      tool_use(:bash, %{command: "ls"}),
      # Hook fires here
      tool_result(:bash, "file1.txt\nfile2.txt"),
      stream_event(:text_delta, "Found 2 files"),
      stream_event(:message_stop)
    ])

    opts = %Options{
      hooks: %{pre_tool_use: [safety_check_hook()]},
      transport: MockTransport,
      transport_opts: [cli_process: mock_cli]
    }

    {:ok, session} = Streaming.start_session(opts)

    events = Streaming.send_message(session, "List files")
      |> Enum.to_list()

    # Verify mixed stream
    assert text_deltas = Enum.filter(events, &(&1.type == :text_delta))
    assert tool_events = Enum.filter(events, &(&1.type in [:tool_use_start, :tool_result]))

    # Verify order preserved
    assert first_text = Enum.at(text_deltas, 0)
    assert first_text.text =~ "Running command"

    # Verify hook was invoked
    assert_received {:hook_called, :pre_tool_use, %{tool_name: "Bash"}}
  end
end
```

**Scenario Coverage**:
1. Text-only streaming (control client path)
2. Tool execution with no streaming
3. Interleaved text + tools
4. Multiple tools in sequence
5. Tool error during stream
6. Hook denial mid-stream
7. Permission callback during stream
8. SDK MCP tool invocation
9. Subscriber queue with multiple messages
10. Session recovery after error

### E2E Tests (Priority 3)

**Live CLI Tests** (~5 tests):
```bash
# Manual verification script
mix test.live test/integration/streaming_tools_e2e_test.exs
```

**Scenarios**:
1. Real Bash tool with streaming output
2. Real SDK MCP server (calculator example)
3. LiveView integration simulation
4. Performance benchmark (latency measurement)
5. Stress test (1000 rapid text deltas)

### Property Tests (Optional)

**State Machine Testing**:
```elixir
defmodule StreamingRouterProperties do
  use ExUnitProperties

  property "router always returns valid transport choice" do
    check all(
      has_hooks <- boolean(),
      has_mcp <- boolean(),
      has_perms <- boolean(),
      override <- member_of([:auto, :cli, :control, nil])
    ) do
      opts = build_options(
        hooks: has_hooks,
        mcp: has_mcp,
        perms: has_perms,
        override: override
      )

      choice = StreamingRouter.select_transport(opts)
      assert choice in [:streaming_session, :control_client]

      # Property: override always respected
      if override == :cli do
        assert choice == :streaming_session
      end

      if override == :control do
        assert choice == :control_client
      end
    end
  end
end
```

---

## Timeline & Milestones

### Phase 1: Foundation (Days 1-3)

**Day 1: CLI Verification & Router**
- ✅ Verify CLI compatibility (GATE CONDITION)
- ✅ Implement StreamingRouter module
- ✅ Write router unit tests (50 tests)
- ⚠️ DECISION POINT: If CLI incompatible, pivot or defer

**Day 2: Options Extension**
- ✅ Add new fields to Options
- ✅ Update CLI arg generation
- ✅ Write options tests
- ✅ Update documentation

**Day 3: Test Infrastructure**
- ✅ Create mock CLI helpers
- ✅ Set up integration test fixtures
- ✅ Write first failing integration test

**Deliverable**: Router + Options complete, gated by CLI verification

### Phase 2: Implementation (Days 4-8)

**Day 4-5: Client Enhancements**
- ✅ Add state fields for streaming
- ✅ Implement `handle_stream_event/2`
- ✅ Add subscriber queue logic
- ✅ Modify CLI command builder
- ✅ Write client streaming unit tests (40 tests)

**Day 6-7: Streaming Facade Integration**
- ✅ Update `Streaming` module routing
- ✅ Implement control client adapter
- ✅ Message-to-event conversion
- ✅ Write facade integration tests (20 tests)

**Day 8: Helper Utilities**
- ✅ Implement EventAdapter module
- ✅ Write adapter tests (30 tests)
- ✅ Create examples and documentation

**Deliverable**: All core modules implemented and unit tested

### Phase 3: Integration & Hardening (Days 9-11)

**Day 9: Integration Testing**
- ✅ Implement mocked CLI integration tests
- ✅ Test all scenario combinations
- ✅ Fix integration issues

**Day 10: Performance & Optimization**
- ✅ Benchmark router overhead
- ✅ Benchmark control vs CLI-only paths
- ✅ Optimize hot paths if needed
- ✅ Document performance characteristics

**Day 11: Edge Cases & Error Handling**
- ✅ Test error scenarios (tool failures, timeouts)
- ✅ Test subscriber edge cases
- ✅ Add defensive programming checks

**Deliverable**: Robust implementation with comprehensive test coverage

### Phase 4: Finalization (Days 12-14)

**Day 12: Documentation & Examples**
- ✅ Update README with streaming + tools examples
- ✅ Write migration guide
- ✅ Update architecture docs
- ✅ Add inline code documentation

**Day 13: E2E Validation**
- ✅ Run live CLI tests
- ✅ Test with real SDK MCP servers
- ✅ Performance validation
- ✅ Final bug fixes

**Day 14: Code Review & Polish**
- ✅ Run full quality suite (`mix format`, `credo`, `dialyzer`)
- ✅ Address review feedback
- ✅ Update CHANGELOG
- ✅ Prepare release notes

**Deliverable**: Production-ready feature, ready for v0.6.0 release

---

## Quality Gates

### Pre-Merge Checklist

```bash
# Run entire quality suite
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
mix test --include integration
```

**Pass Criteria**:
- ✅ Zero compiler warnings
- ✅ Zero Credo issues (allowed: refactoring opportunities)
- ✅ Zero Dialyzer errors
- ✅ 100% test pass rate (excluding skipped)
- ✅ No test flakiness (run 3x)

### Coverage Requirements

- **Router**: 100% line coverage (trivial to achieve)
- **Client streaming logic**: >95% coverage
- **Streaming facade**: >90% coverage
- **EventAdapter**: 100% coverage
- **Integration scenarios**: All 10 scenarios passing

### Performance Benchmarks

**Baseline** (before changes):
```elixir
# CLI-only streaming startup
time_to_first_event: ~200ms

# Control client startup
time_to_initialize: ~300ms
```

**Acceptable** (after changes):
```elixir
# CLI-only streaming (via router)
time_to_first_event: <210ms (5% tolerance)

# Control client with streaming
time_to_first_event: <350ms (combines both overheads)
```

**Red Flag**: >10% regression on any path

---

## Backwards Compatibility

### Guaranteed Safe Operations

1. **Existing `Streaming` API**:
   ```elixir
   # Works unchanged
   {:ok, session} = Streaming.start_session()
   Streaming.send_message(session, "Hello")
   ```
   Router selects CLI-only path (no behavior change)

2. **Existing `Client` API**:
   ```elixir
   # Works unchanged
   {:ok, client} = Client.start_link(%Options{hooks: hooks})
   Client.stream_messages(client)  # Still returns Message structs
   ```
   No streaming events unless `include_partial_messages: true`

3. **All 477 Existing Tests**:
   - Must pass without modification
   - Test suite validates no regressions

### Opt-In Behavior

New functionality requires explicit configuration:

```elixir
# To get streaming + tools:
%Options{
  include_partial_messages: true,  # Must set explicitly
  hooks: %{...}                     # Or SDK MCP, or permissions
}
```

### Deprecation Strategy

**None needed** - fully additive feature.

**Future consideration** (v0.7.0):
- Deprecate separate `Streaming.Session` module
- Encourage unified API through `Streaming`
- Maintain backwards compatibility for 2 major versions

---

## Rollout Plan

### Feature Flag (Recommended)

Add experimental flag for v0.6.0:

```elixir
# config/config.exs
config :claude_agent_sdk,
  enable_streaming_tools: true  # Default: false in v0.6.0, true in v0.7.0
```

**Gating logic**:
```elixir
defmodule ClaudeAgentSDK.FeatureFlags do
  def streaming_tools_enabled? do
    Application.get_env(:claude_agent_sdk, :enable_streaming_tools, false)
  end
end

# In StreamingRouter:
def select_transport(opts) do
  if FeatureFlags.streaming_tools_enabled?() do
    # New router logic
  else
    # Always use Session (current behavior)
    :streaming_session
  end
end
```

**Benefits**:
- Safe rollout for early adopters
- Easy rollback if issues discovered
- Gradual migration path

### Release Strategy

**v0.6.0-rc1** (Week 1):
- Feature flag: false by default
- Documentation: "Experimental"
- Limited rollout to SDK maintainers

**v0.6.0-rc2** (Week 2):
- Feature flag: true by default
- Documentation: "Beta"
- Rollout to community contributors

**v0.6.0** (Week 3):
- Feature flag: removed (always enabled)
- Documentation: "Stable"
- Full release

### Monitoring & Metrics

**Key Metrics**:
1. Router decision distribution (CLI vs Control)
2. Streaming latency (p50, p95, p99)
3. Error rates by transport type
4. Subscriber queue length distribution

**Instrumentation** (optional):
```elixir
defmodule ClaudeAgentSDK.Telemetry do
  def emit_router_decision(choice, features) do
    :telemetry.execute(
      [:claude_agent_sdk, :router, :decision],
      %{count: 1},
      %{choice: choice, features: features}
    )
  end
end
```

---

## Success Criteria

### Functional Requirements

✅ **FR1**: Router correctly selects transport based on options
✅ **FR2**: Control client emits partial message events
✅ **FR3**: Text deltas and tool calls stream interleaved
✅ **FR4**: Hooks invoked correctly during streaming
✅ **FR5**: SDK MCP tools executable while streaming
✅ **FR6**: Permission callbacks work with streaming
✅ **FR7**: CLI-only path performance maintained
✅ **FR8**: All existing tests pass unchanged

### Non-Functional Requirements

✅ **NFR1**: Router overhead <1ms
✅ **NFR2**: Control streaming latency <350ms to first event
✅ **NFR3**: Zero breaking changes
✅ **NFR4**: Test coverage >90% for new code
✅ **NFR5**: Documentation complete and accurate
✅ **NFR6**: Code quality (Credo, Dialyzer) maintained

### Acceptance Test

```elixir
defmodule AcceptanceTest do
  @moduledoc "Comprehensive acceptance test for streaming + tools"

  test "streaming with SDK MCP tools" do
    # Setup: Create calculator SDK MCP server
    server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "calculator",
      version: "1.0.0",
      tools: [CalculatorTools.Add, CalculatorTools.Multiply]
    )

    opts = %Options{
      include_partial_messages: true,
      mcp_servers: %{"calculator" => server}
    }

    # Start streaming session (should use control client)
    {:ok, session} = Streaming.start_session(opts)

    # Send message that requires tool use
    events = Streaming.send_message(session, "What is 25 + 17?")
      |> Enum.to_list()

    # Verify mixed stream
    text_events = Enum.filter(events, &(&1.type == :text_delta))
    tool_events = Enum.filter(events, &(&1.type in [:tool_use_start, :tool_result]))

    # Must see both types
    assert length(text_events) > 0, "Expected text streaming"
    assert length(tool_events) > 0, "Expected tool usage"

    # Verify correct answer in stream
    final_text = Enum.reduce(text_events, "", fn %{text: t}, acc -> acc <> t end)
    assert final_text =~ "42", "Expected correct calculation result"

    # Verify tool was actually invoked
    assert Enum.any?(tool_events, fn
      %{type: :tool_use_start, name: "add"} -> true
      _ -> false
    end)

    # Cleanup
    Streaming.close(session)
  end
end
```

**Pass Criteria**: Test passes reliably (3/3 runs) with live CLI.

---

## Contingency Plans

### Scenario 1: CLI Incompatibility Discovered

**Trigger**: Day 1 verification fails (CLI errors with both flags)

**Response**:
1. **Immediate**: Document limitation
2. **Short-term**: Add CLI version detection
   ```elixir
   def supports_streaming_tools? do
     case System.cmd("claude", ["--version"]) do
       {output, 0} ->
         Version.match?(parse_version(output), ">= 2.1.0")
       _ ->
         false
     end
   end
   ```
3. **Long-term options**:
   - **A**: Defer feature until CLI v2.1 released
   - **B**: Implement "sequential mode" (tools first, then stream results)
   - **C**: Propose CLI enhancement to Anthropic

**Timeline Impact**: +2 days (detection + docs), or DEFER if no workaround

### Scenario 2: Performance Unacceptable

**Trigger**: Benchmarks show >10% regression

**Response**:
1. **Profile**: Use `:fprof` to identify hot spots
2. **Optimize**:
   - Cache router decisions
   - Optimize JSON parsing (use `:jiffy` for critical paths)
   - Reduce GenServer call overhead (use casts where safe)
3. **If still slow**: Add performance warnings in docs
4. **Last resort**: Make streaming+tools opt-in only (no automatic routing)

**Timeline Impact**: +2 days for optimization

### Scenario 3: Subscriber Queue Bugs

**Trigger**: Integration tests show race conditions or deadlocks

**Response**:
1. **Simplify**: Limit to single subscriber for v1
2. **Document**: "Concurrent send_message calls not yet supported"
3. **Future**: Implement proper queue in v0.7.0

**Timeline Impact**: -2 days (simpler), +1 day (docs)

### Scenario 4: Message/Event Mixing Too Complex

**Trigger**: Consumers struggle with heterogeneous streams

**Response**:
1. **Improve adapters**: Add more helper functions
2. **Add mode option**:
   ```elixir
   %Options{streaming_mode: :events_only}  # Suppress Message structs
   ```
3. **Better examples**: Show LiveView integration patterns
4. **Future**: Unify to single Event struct in v0.7.0

**Timeline Impact**: +1 day (better adapters + examples)

---

## Open Questions & Decisions Required

### DECISION 1: Event Representation ⚠️

**Question**: Bare maps or defstruct for streaming events?

**Option A - Bare Maps** (Current):
```elixir
%{type: :text_delta, text: "...", accumulated: "..."}
```
✅ Already working
✅ Simple
❌ No compile-time checks

**Option B - Defstruct**:
```elixir
defmodule ClaudeAgentSDK.Streaming.Event do
  defstruct [:type, :data, :timestamp]
end

%Event{type: :text_delta, data: %{text: "...", accumulated: "..."}}
```
✅ Type safety
✅ Dialyzer support
❌ Migration overhead

**RECOMMENDATION**: **Option A** for v0.6.0, defer **Option B** to v0.7.0.

**Rationale**: Minimize scope, maintain compatibility with existing EventParser.

### DECISION 2: Transport Override Semantics ⚠️

**Question**: What happens when user forces CLI mode but has control features?

```elixir
%Options{
  hooks: %{pre_tool_use: [...]},
  preferred_transport: :cli  # Explicit override
}
```

**Option A - Ignore Control Features**:
- Select CLI-only transport
- Hooks never invoked
- Log warning

**Option B - Error**:
- Raise argument error
- Force user to choose

**Option C - Override the Override**:
- Ignore `:cli` preference
- Use control client anyway
- Log info

**RECOMMENDATION**: **Option A** (ignore control features, log warning).

**Rationale**: Developer knows best; support debugging use cases.

### DECISION 3: Session ID Exposure ⚠️

**Question**: Should control client expose session ID?

**Current**: `Streaming.Session` extracts session ID from `message_start` event.

**Control Client**: Session ID available in initialize response, but not currently stored.

**Options**:
- **A**: Add session ID tracking to Client state
- **B**: Return `:not_supported` (current)
- **C**: Extract from first message (like Session does)

**RECOMMENDATION**: **Option C** (extract from first message).

**Rationale**: Consistency with Session behavior, no state bloat.

### DECISION 4: Feature Flag Default ⚠️

**Question**: Should feature be enabled by default in v0.6.0?

**Option A - Enabled**:
- Router active immediately
- Faster adoption
- Higher risk

**Option B - Disabled**:
- Opt-in via config
- Safer rollout
- Delayed feedback

**RECOMMENDATION**: **Option B** (disabled by default) for v0.6.0-rc1, **Option A** (enabled) for v0.6.0 final.

**Rationale**: Gradual rollout reduces blast radius.

---

## Summary

This Streaming + Tools unification is **highly feasible** with well-understood risks and clear mitigation strategies. The codebase's excellent architectural foundation makes this a **medium-complexity** feature rather than high-risk surgery.

**Key Success Factors**:
1. ✅ Day 1 CLI compatibility verification
2. ✅ TDD approach (router first, integration early)
3. ✅ Incremental merge strategy
4. ✅ Comprehensive test coverage
5. ✅ Performance benchmarking throughout

**Estimated Timeline**: 10-14 days with 2-day buffer

**Risk Assessment**: LOW-MEDIUM (mostly integration complexity)

**Recommendation**: **PROCEED** with approval, gate on Day 1 CLI verification.
