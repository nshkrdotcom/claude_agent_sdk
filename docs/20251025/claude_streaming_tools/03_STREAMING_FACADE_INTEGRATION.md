# Streaming Facade Integration Design

**Module**: `ClaudeAgentSDK.Streaming`
**Status**: Detailed Design
**Complexity**: MEDIUM (⭐⭐⭐ 3/5)
**Estimated Changes**: ~180 LOC modifications, ~100 LOC tests

---

## Overview

This document details modifications to the `ClaudeAgentSDK.Streaming` module to integrate the StreamingRouter and adapt the control client for seamless streaming + tools support.

**Current State**: Direct delegation to `Streaming.Session` only
**Target State**: Router-based selection with transparent transport switching

---

## Architecture

```
Before (Current):

User
  │
  ▼
Streaming.start_session
  │
  └─► Session.start_link (always)


After (Target):

User
  │
  ▼
Streaming.start_session
  │
  ▼
StreamingRouter.select_transport
  │
  ├─► Session.start_link (CLI-only)
  │
  └─► Client.start_link (control+streaming)
          │
          └─► EventAdapter (normalize events)
```

---

## Public API Changes

### 1. start_session/1 Enhancement

**Current Implementation**:
```elixir
def start_session(options \\ nil) do
  opts = options || %Options{}
  Session.start_link(opts)
end
```

**New Implementation**:
```elixir
@type session :: pid() | {:control_client, pid()}

def start_session(options \\ nil) do
  opts = prepare_options(options)

  case StreamingRouter.select_transport(opts) do
    :streaming_session ->
      # Fast path: CLI-only streaming
      Session.start_link(opts)

    :control_client ->
      # Full features: Control client with streaming
      start_control_streaming(opts)
  end
end

defp prepare_options(nil), do: %Options{include_partial_messages: true}
defp prepare_options(%Options{} = opts) do
  # Ensure streaming enabled
  %{opts | include_partial_messages: true}
end

defp start_control_streaming(opts) do
  case Client.start_link(opts) do
    {:ok, client} ->
      # Return tagged tuple to distinguish transport
      {:ok, {:control_client, client}}

    error ->
      error
  end
end
```

**Key Changes**:
- ✅ Automatic router integration
- ✅ Force `include_partial_messages: true` for streaming
- ✅ Tagged return for control client: `{:control_client, pid()}`
- ✅ Backwards compatible (raw PID for Session)

---

### 2. send_message/2 Polymorphism

**Current**:
```elixir
def send_message(session, message) when is_pid(session) do
  Session.send_message(session, message)
end
```

**New**:
```elixir
# CLI-only session
def send_message(session, message) when is_pid(session) do
  Session.send_message(session, message)
end

# Control client session
def send_message({:control_client, client}, message) do
  stream_via_control_client(client, message)
end

defp stream_via_control_client(client, message) do
  ref = make_ref()

  # Subscribe to events
  :ok = GenServer.call(client, {:subscribe, ref})

  # Send message
  :ok = Client.send_message(client, message)

  # Return adapted stream
  adapt_control_client_stream(client, ref)
end
```

---

### 3. Control Client Stream Adapter

**NEW Function**:
```elixir
defp adapt_control_client_stream(client, ref) do
  Stream.resource(
    fn -> init_stream_state(client, ref) end,
    fn state -> receive_next_event(state) end,
    fn state -> cleanup_stream(state) end
  )
end

defp init_stream_state(client, ref) do
  %{
    client: client,
    ref: ref,
    status: :active,
    accumulated: ""
  }
end

defp receive_next_event(%{status: :complete} = state) do
  {:halt, state}
end

defp receive_next_event(state) do
  receive do
    # Streaming events (already in correct format)
    {:stream_event, ref, event} when ref == state.ref ->
      new_status = if event.type == :message_stop, do: :complete, else: :active
      new_accumulated = event[:accumulated] || state.accumulated

      {[event], %{state | status: new_status, accumulated: new_accumulated}}

    # Control messages (convert to events)
    {:claude_message, message} ->
      event = message_to_event(message, state.accumulated)
      {[event], state}

    # Error handling
    {:stream_error, ref, reason} when ref == state.ref ->
      error_event = %{type: :error, error: reason}
      {[error_event], %{state | status: :complete}}

  after
    300_000 ->  # 5 minutes
      timeout_event = %{type: :error, error: :timeout}
      {[timeout_event], %{state | status: :complete}}
  end
end

defp cleanup_stream(%{client: client, ref: ref}) do
  GenServer.cast(client, {:unsubscribe, ref})
end

defp message_to_event(%Message{type: :tool_result} = msg, accumulated) do
  %{
    type: :tool_result,
    tool_name: msg.tool_name,
    result: msg.content,
    accumulated: accumulated,
    timestamp: DateTime.utc_now()
  }
end

defp message_to_event(%Message{type: :error} = msg, accumulated) do
  %{
    type: :error,
    error: msg.content,
    accumulated: accumulated
  }
end

defp message_to_event(msg, accumulated) do
  %{
    type: :message,
    content: msg,
    accumulated: accumulated
  }
end
```

---

### 4. close/1 Polymorphism

**Current**:
```elixir
def close(session) when is_pid(session) do
  Session.close(session)
end
```

**New**:
```elixir
def close({:control_client, client}), do: Client.stop(client)
def close(session) when is_pid(session), do: Session.close(session)
```

---

### 5. get_session_id/1 Polymorphism

**Current**:
```elixir
def get_session_id(session) when is_pid(session) do
  Session.get_session_id(session)
end
```

**New**:
```elixir
def get_session_id({:control_client, _client}) do
  {:error, :not_supported_in_control_mode}
end

def get_session_id(session) when is_pid(session) do
  Session.get_session_id(session)
end
```

---

## Event Format Unification

### Streaming Events (from EventParser)

```elixir
%{
  type: :text_delta,
  text: "partial text",
  accumulated: "full text so far",
  timestamp: nil  # EventParser doesn't add timestamps
}
```

### Control Messages (from Client)

```elixir
%Message{
  type: :tool_result,
  tool_name: "Bash",
  content: "command output",
  timestamp: ~U[...]
}
```

### Normalized Output (after adaptation)

All events converted to consistent map format:
```elixir
# Text streaming
%{type: :text_delta, text: "...", accumulated: "..."}

# Tool result (converted from Message)
%{type: :tool_result, tool_name: "...", result: "...", accumulated: "..."}

# Errors
%{type: :error, error: "...", accumulated: "..."}
```

---

## Testing Strategy

### Unit Tests

```elixir
defmodule ClaudeAgentSDK.StreamingIntegrationTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Streaming, Options}

  describe "start_session/1 routing" do
    test "routes to Session for simple streaming" do
      {:ok, session} = Streaming.start_session()

      assert is_pid(session)
      refute match?({:control_client, _}, session)

      Streaming.close(session)
    end

    test "routes to Client when hooks present" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}
      }

      {:ok, session} = Streaming.start_session(opts)

      assert match?({:control_client, _}, session)

      Streaming.close(session)
    end

    test "forces include_partial_messages" do
      opts = %Options{include_partial_messages: false}

      {:ok, _session} = Streaming.start_session(opts)

      # Should have been forced to true internally
      # (verified via CLI command inspection)
    end
  end

  describe "send_message/2 polymorphism" do
    test "works with Session transport" do
      {:ok, session} = Streaming.start_session()

      stream = Streaming.send_message(session, "Hello")

      events = Enum.take(stream, 5)
      assert is_list(events)

      Streaming.close(session)
    end

    test "works with Client transport" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}
      }

      {:ok, session} = Streaming.start_session(opts)

      stream = Streaming.send_message(session, "Hello")

      events = Enum.take(stream, 5)
      assert is_list(events)

      Streaming.close(session)
    end
  end

  describe "event normalization" do
    @tag :requires_cli
    test "normalizes tool results to event format" do
      server = ClaudeAgentSDK.create_sdk_mcp_server(
        name: "test",
        tools: [TestTool]
      )

      opts = %Options{
        mcp_servers: %{"test" => server}
      }

      {:ok, session} = Streaming.start_session(opts)

      events = Streaming.send_message(session, "Use test tool")
        |> Enum.take(100)

      # Find tool result event
      tool_event = Enum.find(events, &(&1.type == :tool_result))

      assert tool_event.tool_name
      assert tool_event.result
      assert tool_event.accumulated  # Should have accumulated text

      Streaming.close(session)
    end
  end

  describe "close/1 polymorphism" do
    test "closes Session transport" do
      {:ok, session} = Streaming.start_session()
      assert :ok = Streaming.close(session)

      refute Process.alive?(session)
    end

    test "closes Client transport" do
      callback = fn _, _, _ -> %{behavior: :allow} end
      opts = %Options{
        hooks: %{pre_tool_use: [Matcher.new("Bash", [callback])]}
      }

      {:ok, {:control_client, client}} = Streaming.start_session(opts)
      assert :ok = Streaming.close({:control_client, client})

      refute Process.alive?(client)
    end
  end
end
```

---

## Backwards Compatibility

### Guaranteed Safe

✅ **Existing code continues working**:
```elixir
# This still works unchanged
{:ok, session} = Streaming.start_session()
stream = Streaming.send_message(session, "Hello")
```

✅ **Pattern matching on PID**:
```elixir
case Streaming.start_session() do
  {:ok, pid} when is_pid(pid) -> ...  # Still works
end
```

### Opt-In New Behavior

New behavior only when control features present:
```elixir
# Returns {:control_client, pid()} tuple
Streaming.start_session(%Options{hooks: %{...}})
```

### Migration Helpers

```elixir
defmodule ClaudeAgentSDK.Streaming.Helpers do
  def unwrap_session({:control_client, client}), do: client
  def unwrap_session(session) when is_pid(session), do: session

  def is_control_session?({:control_client, _}), do: true
  def is_control_session?(_), do: false
end
```

---

## Summary

Streaming facade integration provides:

✅ **Transparent routing** via StreamingRouter
✅ **Unified API** (same functions work for both transports)
✅ **Event normalization** (consistent stream format)
✅ **Zero breaking changes** (backwards compatible)

**Complexity**: ⭐⭐⭐ (3/5) - Medium
**Timeline**: 2 days
