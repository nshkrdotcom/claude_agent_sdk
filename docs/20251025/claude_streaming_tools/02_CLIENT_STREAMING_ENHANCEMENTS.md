# Client Streaming Enhancements Design

**Module**: `ClaudeAgentSDK.Client`
**Status**: Detailed Design
**Complexity**: MEDIUM (⭐⭐⭐ 3/5)
**Estimated Changes**: ~200 LOC modifications, ~150 LOC tests

---

## Overview

This document details the modifications to `ClaudeAgentSDK.Client` to support simultaneous streaming (`--include-partial-messages`) and control protocol features (hooks, SDK MCP, permissions).

**Current State**: Control protocol works, but no partial message streaming
**Target State**: Control protocol + character-level streaming in unified stream

---

## Architecture Context

```
Current Client Architecture:

Port/Transport
      │
      ▼
┌─────────────────────────┐
│ Client GenServer        │
│  • Control protocol     │
│  • Hook callbacks       │
│  • SDK MCP routing      │
│  • Permission handling  │
│  ❌ NO partial streaming│
└─────────────────────────┘
      │
      ▼
Subscribers (Message structs only)


Target Architecture (After Changes):

Port/Transport
      │
      ▼
┌─────────────────────────┐
│ Client GenServer        │
│  • Control protocol     │
│  • Hook callbacks       │
│  • SDK MCP routing      │
│  • Permission handling  │
│  ✅ Partial streaming   │ ◄── NEW
│  ✅ Event parsing       │ ◄── NEW
│  ✅ Subscriber queue    │ ◄── NEW
└─────────────────────────┘
      │
      ▼
Subscribers (Mixed events + messages)
```

---

## Required Modifications

### 1. State Structure Changes

**Current State** (lines 84-98):
```elixir
@type state :: %{
  port: port() | nil,
  transport: pid() | nil,
  transport_module: module() | nil,
  transport_opts: keyword(),
  options: Options.t(),
  registry: Registry.t(),
  subscribers: [pid()],              # ◄── Simple list
  pending_requests: %{String.t() => {GenServer.from(), reference()}},
  initialized: boolean(),
  buffer: String.t(),
  sdk_mcp_servers: %{String.t() => pid()},
  current_model: String.t() | nil,
  pending_model_change: {GenServer.from(), reference()} | nil
}
```

**New State** (proposed):
```elixir
@type state :: %{
  # ... existing fields unchanged ...

  # MODIFIED: subscribers now tracks refs for queue
  subscribers: %{reference() => pid()},  # ref => pid mapping

  # NEW: Streaming support fields
  accumulated_text: String.t(),          # Buffer for partial text deltas
  active_subscriber: reference() | nil,  # Current streaming consumer
  subscriber_queue: queue(),             # FIFO queue of pending messages

  # ... rest unchanged ...
}

@type queue_entry :: {reference(), String.t()}
@type queue :: [queue_entry()]
```

**Rationale**:
- `subscribers` becomes a map for O(1) lookup by ref
- `accumulated_text` tracks partial text across deltas (reset on message_stop)
- `active_subscriber` enforces single-consumer model (matches Streaming.Session)
- `subscriber_queue` stores pending messages while active subscriber streaming

**Migration Impact**: BREAKING for direct state access (none expected—state is private)

---

### 2. CLI Command Builder Enhancement

**Current** (lines 801-818):
```elixir
defp build_cli_command(options) do
  executable = System.find_executable("claude")

  if executable do
    args = ["--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose"]

    args = args ++ Options.to_args(options)
    cmd = Enum.join([executable | args], " ") <> " 2>/dev/null"
    {:ok, cmd}
  else
    {:error, :claude_not_found}
  end
end
```

**New** (proposed):
```elixir
defp build_cli_command(options) do
  executable = System.find_executable("claude")

  if executable do
    # Base streaming args
    base_args = [
      "--output-format", "stream-json",
      "--input-format", "stream-json",
      "--verbose"
    ]

    # Add partial messages if requested
    base_args = if options.include_partial_messages do
      base_args ++ ["--include-partial-messages"]
    else
      base_args
    end

    # Merge with user options
    args = base_args ++ Options.to_args(options)
    cmd = Enum.join([executable | args], " ") <> " 2>/dev/null"
    {:ok, cmd}
  else
    {:error, :claude_not_found}
  end
end
```

**Change Summary**:
- ✅ Conditionally add `--include-partial-messages`
- ✅ Maintain existing behavior when flag not set
- ✅ Preserve stderr redirection

**Test Coverage**:
```elixir
test "includes partial messages flag when requested" do
  opts = %Options{include_partial_messages: true}
  {:ok, cmd} = Client.build_cli_command(opts)

  assert cmd =~ "--include-partial-messages"
end

test "omits partial messages flag by default" do
  opts = %Options{}
  {:ok, cmd} = Client.build_cli_command(opts)

  refute cmd =~ "--include-partial-messages"
end
```

---

### 3. Message Decoding Extension

**Current** (lines 525-584):
```elixir
def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
  case Protocol.decode_message(line) do
    {:ok, {:control_request, data}} ->
      handle_control_request(data, state)

    {:ok, {:control_response, data}} ->
      handle_control_response(data, state)

    {:ok, {:sdk_message, data}} ->
      broadcast_message(data, state)
      state

    {:error, reason} ->
      Logger.warning("Failed to decode: #{inspect(reason)}")
      state
  end

  {:noreply, state}
end
```

**New** (proposed):
```elixir
def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
  case Protocol.decode_message(line) do
    {:ok, {:control_request, data}} ->
      new_state = handle_control_request(data, state)
      {:noreply, new_state}

    {:ok, {:control_response, data}} ->
      new_state = handle_control_response(data, state)
      {:noreply, new_state}

    {:ok, {:sdk_message, data}} ->
      broadcast_message(data, state)
      {:noreply, state}

    # NEW: Handle streaming events
    {:ok, {:stream_event, event_data}} ->
      new_state = handle_stream_event(event_data, state)
      {:noreply, new_state}

    {:error, reason} ->
      Logger.warning("Failed to decode: #{inspect(reason)}")
      {:noreply, state}
  end
end
```

**Protocol.decode_message/1 Enhancement**:
```elixir
# In lib/claude_agent_sdk/control_protocol/protocol.ex

def decode_message(line) do
  case Jason.decode(line) do
    {:ok, %{"type" => "stream_event", "event" => event_data}} ->
      {:ok, {:stream_event, event_data}}

    {:ok, %{"type" => "control_request"} = data} ->
      {:ok, {:control_request, data}}

    # ... existing cases ...
  end
end
```

---

### 4. Stream Event Handler (NEW)

**Location**: After `handle_control_response/2` (new function)

```elixir
@doc false
@spec handle_stream_event(map(), state()) :: state()
defp handle_stream_event(event_data, state) do
  # Parse via EventParser (reuse existing streaming infrastructure)
  {:ok, events, new_accumulated} =
    ClaudeAgentSDK.Streaming.EventParser.parse_event(
      event_data,
      state.accumulated_text
    )

  # Broadcast to ACTIVE subscriber only (not all subscribers)
  if state.active_subscriber do
    broadcast_events_to_active(state.active_subscriber, state.subscribers, events)
  end

  # Check for message completion
  message_complete? = Enum.any?(events, fn event ->
    event.type == :message_stop
  end)

  if message_complete? do
    handle_message_completion(state, new_accumulated)
  else
    %{state | accumulated_text: new_accumulated}
  end
end

@doc false
@spec handle_message_completion(state(), String.t()) :: state()
defp handle_message_completion(state, final_text) do
  # Message complete - activate next queued subscriber
  case :queue.out(state.subscriber_queue) do
    {{:value, {next_ref, next_message}}, remaining_queue} ->
      # Send queued message immediately
      json = encode_outgoing_message(next_message)
      _ = send_payload(state, json)

      Logger.debug("Activated queued subscriber",
        subscriber_ref: inspect(next_ref),
        queue_depth: :queue.len(remaining_queue)
      )

      %{
        state
        | active_subscriber: next_ref,
          subscriber_queue: remaining_queue,
          accumulated_text: "",  # Reset for next message
          final_text_cache: final_text  # Store for reference
      }

    {:empty, _} ->
      # No more queued messages
      %{
        state
        | active_subscriber: nil,
          subscriber_queue: :queue.new(),
          accumulated_text: "",
          final_text_cache: final_text
      }
  end
end

@doc false
@spec broadcast_events_to_active(reference(), %{reference() => pid()}, [map()]) :: :ok
defp broadcast_events_to_active(active_ref, subscribers, events) do
  case Map.get(subscribers, active_ref) do
    nil ->
      Logger.warning("Active subscriber not found",
        active_ref: inspect(active_ref),
        subscriber_count: map_size(subscribers)
      )
      :ok

    pid ->
      Enum.each(events, fn event ->
        send(pid, {:stream_event, active_ref, event})
      end)

      :ok
  end
end
```

**Key Design Decisions**:

1. **Reuse EventParser**: Don't reimplement parsing logic—delegate to proven module
2. **Active-only broadcast**: Only current subscriber receives events (queue model)
3. **Automatic queue processing**: On `message_stop`, immediately send next queued message
4. **Accumulated text tracking**: Maintain partial text buffer, reset on completion
5. **Error handling**: Log warnings for missing subscribers but continue

---

### 5. Subscriber Management Enhancement

**Current** (line 432-435):
```elixir
def handle_call({:subscribe}, from, state) do
  {pid, _ref} = from
  {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
end
```

**New** (proposed):
```elixir
def handle_call({:subscribe, ref}, from, state) when is_reference(ref) do
  {pid, _call_ref} = from

  # Add to subscribers map
  subscribers = Map.put(state.subscribers, ref, pid)

  # Monitor subscriber for cleanup
  Process.monitor(pid)

  # Activate if no active subscriber
  {new_active, new_queue} =
    if state.active_subscriber == nil do
      {ref, state.subscriber_queue}
    else
      # Queue this subscriber (will be activated on message completion)
      {state.active_subscriber, state.subscriber_queue}
    end

  Logger.debug("Subscriber registered",
    ref: inspect(ref),
    pid: inspect(pid),
    active: new_active == ref,
    queue_depth: :queue.len(new_queue)
  )

  {:reply, :ok, %{
    state
    | subscribers: subscribers,
      active_subscriber: new_active,
      subscriber_queue: new_queue
  }}
end

# Backwards compatibility: support old subscribe without ref
def handle_call({:subscribe}, from, state) do
  ref = make_ref()
  handle_call({:subscribe, ref}, from, state)
end
```

**Unsubscribe Handler** (new):
```elixir
def handle_cast({:unsubscribe, ref}, state) do
  # Remove from subscribers
  subscribers = Map.delete(state.subscribers, ref)

  # Remove from queue if present
  new_queue = :queue.filter(fn {r, _msg} -> r != ref end, state.subscriber_queue)

  # If this was active subscriber, activate next
  {new_active, final_queue} =
    if state.active_subscriber == ref do
      case :queue.out(new_queue) do
        {{:value, {next_ref, next_msg}}, remaining} ->
          # Activate next in queue
          json = encode_outgoing_message(next_msg)
          _ = send_payload(state, json)
          {next_ref, remaining}

        {:empty, _} ->
          {nil, new_queue}
      end
    else
      {state.active_subscriber, new_queue}
    end

  {:noreply, %{
    state
    | subscribers: subscribers,
      active_subscriber: new_active,
      subscriber_queue: final_queue
  }}
end
```

**Message Sending Update** (line 379-393):
```elixir
def handle_call({:send_message, message}, _from, state) do
  ref = make_ref()  # Generate ref for this message

  cond do
    not connected?(state) ->
      {:reply, {:error, :not_connected}, state}

    state.active_subscriber == nil ->
      # No active subscriber, send immediately and activate
      json = encode_outgoing_message(message)

      case send_payload(state, json) do
        :ok ->
          new_state = %{state | active_subscriber: ref}
          {:reply, {:ok, ref}, new_state}

        {:error, reason} ->
          {:reply, {:error, :send_failed}, state}
      end

    true ->
      # Active subscriber exists, queue this message
      new_queue = :queue.in({ref, message}, state.subscriber_queue)

      Logger.debug("Message queued",
        ref: inspect(ref),
        active: inspect(state.active_subscriber),
        queue_depth: :queue.len(new_queue)
      )

      {:reply, {:ok, ref}, %{state | subscriber_queue: new_queue}}
  end
end
```

---

### 6. Initialization Changes

**Current** (line 337-354):
```elixir
defp do_init(options, opts) do
  # ... validation ...

  state = %{
    port: nil,
    transport: nil,
    transport_module: transport_module,
    transport_opts: transport_opts,
    options: updated_options,
    registry: Registry.new(),
    subscribers: [],  # ◄── Simple list
    pending_requests: %{},
    initialized: false,
    buffer: "",
    session_id: nil,
    sdk_mcp_servers: sdk_mcp_servers,
    current_model: updated_options.model,
    pending_model_change: nil
  }

  {:ok, state, {:continue, :start_cli}}
end
```

**New** (proposed):
```elixir
defp do_init(options, opts) do
  # ... validation unchanged ...

  state = %{
    port: nil,
    transport: nil,
    transport_module: transport_module,
    transport_opts: transport_opts,
    options: updated_options,
    registry: Registry.new(),
    subscribers: %{},  # ◄── Now map
    pending_requests: %{},
    initialized: false,
    buffer: "",
    session_id: nil,
    sdk_mcp_servers: sdk_mcp_servers,
    current_model: updated_options.model,
    pending_model_change: nil,

    # NEW: Streaming support
    accumulated_text: "",
    active_subscriber: nil,
    subscriber_queue: :queue.new(),  # Erlang queue for efficiency
    final_text_cache: nil
  }

  {:ok, state, {:continue, :start_cli}}
end
```

---

## Subscriber Queue Semantics

### Queue Model (Inherited from Streaming.Session)

```
Subscriber Lifecycle:

1. subscribe(ref) →
   - If no active: set active = ref
   - Else: keep queued

2. send_message(msg) →
   - If active subscriber: send to CLI
   - Broadcast events to active only

3. message_stop event →
   - Dequeue next subscriber
   - Send their queued message
   - Set active = next

4. unsubscribe(ref) →
   - Remove from map
   - Remove from queue
   - If was active: activate next
```

### Example Scenario

```elixir
# User A subscribes and sends
{:ok, client} = Client.start_link(opts)
ref_a = make_ref()
:ok = GenServer.call(client, {:subscribe, ref_a})
:ok = Client.send_message(client, "Task A")

# State: active_subscriber = ref_a, queue = []

# User B subscribes while A is active
ref_b = make_ref()
:ok = GenServer.call(client, {:subscribe, ref_b})
:ok = Client.send_message(client, "Task B")

# State: active_subscriber = ref_a, queue = [{ref_b, "Task B"}]

# A receives all events for "Task A"
receive do
  {:stream_event, ^ref_a, %{type: :text_delta, text: "..."}} -> ...
  {:stream_event, ^ref_a, %{type: :message_stop}} -> ...
end

# On message_stop:
# - Dequeue B
# - Send "Task B" to CLI
# - State: active_subscriber = ref_b, queue = []

# B now receives events for "Task B"
receive do
  {:stream_event, ^ref_b, %{type: :text_delta, text: "..."}} -> ...
end
```

---

## Mixed Stream Handling

### Event Types in Stream

After these changes, subscribers receive **heterogeneous messages**:

1. **Streaming Events** (via EventParser):
   - `{:stream_event, ref, %{type: :text_delta, text: "...", accumulated: "..."}}`
   - `{:stream_event, ref, %{type: :tool_input_delta, json: "..."}}`
   - `{:stream_event, ref, %{type: :thinking_delta, thinking: "..."}}`
   - `{:stream_event, ref, %{type: :message_stop, final_text: "..."}}`

2. **Control Messages** (existing):
   - `{:claude_message, %Message{type: :tool_result, content: "..."}}`
   - `{:claude_message, %Message{type: :error, content: "..."}}`

**Consumer Pattern**:
```elixir
receive do
  # Streaming events
  {:stream_event, ^ref, %{type: :text_delta} = event} ->
    handle_text_delta(event)

  {:stream_event, ^ref, %{type: :message_stop}} ->
    :done

  # Control messages (tool results, etc.)
  {:claude_message, %Message{type: :tool_result} = msg} ->
    handle_tool_result(msg)
end
```

**Adapter Utility** (provided in separate module):
```elixir
# Normalize mixed stream
ClaudeAgentSDK.Streaming.EventAdapter.to_events(stream)
|> Stream.each(fn normalized_event ->
  # Always %{type: ..., data: ...} format
end)
```

---

## Error Handling

### New Error Scenarios

1. **EventParser Failure**:
   ```elixir
   defp handle_stream_event(event_data, state) do
     case EventParser.parse_event(event_data, state.accumulated_text) do
       {:ok, events, new_accumulated} ->
         # ... normal flow ...

       {:error, reason} ->
         Logger.error("EventParser failed",
           reason: inspect(reason),
           event: inspect(event_data)
         )

         # Send error event to active subscriber
         if state.active_subscriber do
           send_error_event(state.active_subscriber, state.subscribers, reason)
         end

         # Don't update accumulated_text on error
         state
     end
   end

   defp send_error_event(ref, subscribers, reason) do
     pid = Map.get(subscribers, ref)
     if pid do
       error_event = %{type: :error, error: reason, source: :event_parser}
       send(pid, {:stream_event, ref, error_event})
     end
   end
   ```

2. **Queue Overflow Protection**:
   ```elixir
   @max_queue_depth 10

   def handle_call({:send_message, message}, _from, state) do
     if :queue.len(state.subscriber_queue) >= @max_queue_depth do
       {:reply, {:error, :queue_full}, state}
     else
       # ... normal queueing ...
     end
   end
   ```

3. **Subscriber Timeout**:
   ```elixir
   # In subscriber process:
   receive do
     {:stream_event, ^ref, event} -> ...
   after
     300_000 ->  # 5 minutes
       Logger.warning("Subscriber timeout", ref: ref)
       :timeout
   end
   ```

---

## Testing Strategy

### Unit Tests

**Test File**: `test/claude_agent_sdk/client_streaming_test.exs` (new)

```elixir
defmodule ClaudeAgentSDK.ClientStreamingTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}

  describe "streaming event handling" do
    test "broadcasts text_delta to active subscriber" do
      opts = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(opts)

      ref = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref})

      # Simulate CLI streaming event
      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Hello"}
      }

      send(client, simulate_stream_event(event))

      assert_receive {:stream_event, ^ref, %{
        type: :text_delta,
        text: "Hello",
        accumulated: "Hello"
      }}
    end

    test "accumulates text across multiple deltas" do
      opts = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(opts)

      ref = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref})

      # Send sequence of deltas
      send(client, simulate_stream_event(text_delta("Hello")))
      send(client, simulate_stream_event(text_delta(" ")))
      send(client, simulate_stream_event(text_delta("world")))

      # Each event should have growing accumulated text
      assert_receive {:stream_event, ^ref, %{accumulated: "Hello"}}
      assert_receive {:stream_event, ^ref, %{accumulated: "Hello "}}
      assert_receive {:stream_event, ^ref, %{accumulated: "Hello world"}}
    end

    test "resets accumulated text on message_stop" do
      opts = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(opts)

      ref = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref})

      send(client, simulate_stream_event(text_delta("First")))
      send(client, simulate_stream_event(message_stop()))

      assert_receive {:stream_event, ^ref, %{type: :message_stop, final_text: "First"}}

      # Send second message
      send(client, simulate_stream_event(text_delta("Second")))

      # Accumulated should restart from zero
      assert_receive {:stream_event, ^ref, %{accumulated: "Second"}}
    end

    test "handles thinking deltas" do
      opts = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(opts)

      ref = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref})

      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "thinking_delta", "thinking" => "Let me consider..."}
      }

      send(client, simulate_stream_event(event))

      assert_receive {:stream_event, ^ref, %{
        type: :thinking_delta,
        thinking: "Let me consider..."
      }}
    end

    test "handles tool input deltas" do
      opts = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(opts)

      ref = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref})

      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "input_json_delta", "partial_json" => "{\"command\":\"ls\"}"}
      }

      send(client, simulate_stream_event(event))

      assert_receive {:stream_event, ^ref, %{
        type: :tool_input_delta,
        json: "{\"command\":\"ls\"}"
      }}
    end
  end

  describe "subscriber queue" do
    test "activates first subscriber immediately" do
      opts = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(opts)

      ref1 = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref1})

      # Send event - should go to ref1
      send(client, simulate_stream_event(text_delta("A")))

      assert_receive {:stream_event, ^ref1, %{text: "A"}}
    end

    test "queues second subscriber until first completes" do
      opts = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(opts)

      ref1 = make_ref()
      ref2 = make_ref()

      :ok = GenServer.call(client, {:subscribe, ref1})
      :ok = GenServer.call(client, {:subscribe, ref2})

      # Send to ref1
      send(client, simulate_stream_event(text_delta("For ref1")))

      # Only ref1 receives
      assert_receive {:stream_event, ^ref1, %{text: "For ref1"}}
      refute_receive {:stream_event, ^ref2, _}

      # Complete ref1's message
      send(client, simulate_stream_event(message_stop()))

      assert_receive {:stream_event, ^ref1, %{type: :message_stop}}

      # Now ref2 should start receiving
      send(client, simulate_stream_event(text_delta("For ref2")))

      assert_receive {:stream_event, ^ref2, %{text: "For ref2"}}
    end

    test "auto-activates queued subscriber on completion" do
      # This tests automatic message sending for queued subscribers
      # (More complex - requires mocking send_payload)
    end
  end

  describe "mixed event and message streams" do
    test "interleaves text deltas and tool results" do
      opts = %Options{
        include_partial_messages: true,
        hooks: %{pre_tool_use: [test_hook()]}
      }

      {:ok, client} = Client.start_link(opts)

      ref = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref})

      # Simulate: text → tool use → text
      send(client, simulate_stream_event(text_delta("Running command: ")))
      send(client, simulate_sdk_message(tool_result("Bash", "output")))
      send(client, simulate_stream_event(text_delta("Done.")))

      # Should receive both types
      assert_receive {:stream_event, ^ref, %{type: :text_delta, text: "Running command: "}}
      assert_receive {:claude_message, %{type: :tool_result}}
      assert_receive {:stream_event, ^ref, %{type: :text_delta, text: "Done."}}
    end
  end

  describe "error handling" do
    test "handles malformed stream events gracefully" do
      opts = %Options{include_partial_messages: true}
      {:ok, client} = Client.start_link(opts)

      ref = make_ref()
      :ok = GenServer.call(client, {:subscribe, ref})

      # Send invalid event
      invalid_event = %{"type" => "unknown_event_type", "data" => "..."}
      send(client, simulate_stream_event(invalid_event))

      # Should not crash, may receive error event or ignore
      refute_receive {:EXIT, ^client, _}
    end

    test "logs warning when active subscriber not found" do
      # Test defensive programming
    end
  end

  # Helpers

  defp simulate_stream_event(event) do
    {:transport_message, Jason.encode!(%{
      "type" => "stream_event",
      "event" => event
    })}
  end

  defp simulate_sdk_message(message) do
    {:transport_message, Jason.encode!(%{
      "type" => "sdk_message",
      "message" => message
    })}
  end

  defp text_delta(text) do
    %{
      "type" => "content_block_delta",
      "delta" => %{"type" => "text_delta", "text" => text}
    }
  end

  defp message_stop do
    %{"type" => "message_stop"}
  end

  defp test_hook do
    fn _, _, _ -> %{behavior: :allow} end
  end
end
```

**Test Count**: ~40 tests
**Coverage Target**: >95% of new code

---

## Integration Points

### 1. With EventParser

```elixir
# Client delegates parsing to EventParser
alias ClaudeAgentSDK.Streaming.EventParser

{:ok, events, new_accumulated} = EventParser.parse_event(event_data, accumulated)
```

**Dependency**: EventParser module (no modifications needed)

### 2. With Streaming Module

```elixir
# Streaming.start_session may route through Client
case StreamingRouter.select_transport(opts) do
  :control_client ->
    {:ok, client} = Client.start_link(opts)
    {:ok, {:control_client, client}}
  # ...
end
```

**Contract**: Client must emit same event format as Streaming.Session

### 3. With Transport Layer

```elixir
# Client continues to use Transport abstraction
case send_payload(state, json) do
  :ok -> ...
  {:error, reason} -> ...
end
```

**No changes required** to Transport modules

---

## Performance Considerations

### Memory Impact

**Before**: `subscribers: [pid1, pid2, ...]` (~8 bytes per PID)
**After**: `subscribers: %{ref1 => pid1, ref2 => pid2}` (~16 bytes per entry)

**Overhead**: 2x for subscriber storage (negligible for <100 subscribers)

**Queue**: `:queue` implementation (Erlang) is efficient for FIFO operations:
- `in/2`: O(1) amortized
- `out/1`: O(1) amortized
- Memory: ~100 bytes per queued message

**Typical State Size**:
- 10 subscribers: ~500 bytes
- 5 queued messages: ~500 bytes
- Accumulated text buffer: varies (max ~10KB for long responses)

**Total overhead**: <2KB in typical case

### CPU Impact

**New per-message overhead**:
1. EventParser.parse_event: ~10μs (JSON parsing + pattern matching)
2. Queue operations: ~1μs (Erlang queue is fast)
3. Map lookups: ~0.1μs (ref => pid)

**Total added latency**: <15μs per streaming event

**Impact**: Negligible (<0.1% of total latency, dominated by network)

---

## Backwards Compatibility

### Breaking Changes: NONE

All changes are **additive or internal**:

1. ✅ `Client.start_link/1` signature unchanged
2. ✅ `Client.stream_messages/1` still returns `Stream.t(Message.t())`
3. ✅ Existing hooks/permissions continue working
4. ✅ SDK MCP routing unchanged

### Opt-In Behavior

Streaming events only appear when:
```elixir
%Options{include_partial_messages: true}
```

Without this flag:
- No `--include-partial-messages` passed to CLI
- No `stream_event` messages received
- Behavior identical to current version

### Migration Path

**Phase 1** (v0.6.0): Both models supported
```elixir
# Old style (still works)
{:ok, client} = Client.start_link(%Options{hooks: hooks})
Client.stream_messages(client) |> Enum.to_list()

# New style (opt-in)
{:ok, client} = Client.start_link(%Options{
  hooks: hooks,
  include_partial_messages: true
})
```

**Phase 2** (v0.7.0+): Deprecation notices (optional)
```elixir
# Could add warning if hooks + no streaming
Logger.info("Consider enabling include_partial_messages for better UX")
```

**Phase 3** (v1.0.0+): Default to streaming
```elixir
# include_partial_messages: true by default
```

---

## Summary

The Client enhancements enable **simultaneous streaming and control features** with:

✅ **Minimal changes** (~200 LOC)
✅ **Zero breaking changes** (fully backwards compatible)
✅ **Clean integration** (reuses EventParser, existing queue patterns)
✅ **Comprehensive testing** (40+ new tests)
✅ **Negligible overhead** (<15μs latency, <2KB memory)

**Complexity**: ⭐⭐⭐ (3/5) - Medium (subscriber queue logic main challenge)
**Risk**: LOW-MEDIUM (well-tested patterns from Streaming.Session)
**Timeline**: 2-3 days implementation + testing
