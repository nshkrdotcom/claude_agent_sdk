# Streaming Comparison: Python vs Elixir Claude Agent SDK

## Overview

Both SDKs support streaming responses from Claude, including partial message updates, tool use deltas, and thinking blocks. This document compares message types, event parsing, control protocol, and session management.

## Parity Status

| Feature | Python SDK | Elixir SDK | Parity |
|---------|------------|------------|--------|
| Partial Messages | Yes | Yes | Full |
| Text Streaming | Yes | Yes | Full |
| Tool Use Streaming | Yes | Yes | Full |
| Thinking Blocks | Yes | Yes | Full |
| Control Protocol | Yes | Yes | Full |
| Session Management | Via Client | Via Session/Client | Full |
| Stream Events | AsyncIterator | Elixir Stream | Full |
| Event Types | Message types | Parsed event maps | Similar |

## Message Types

### Python Message Types

```python
# types.py
@dataclass
class UserMessage:
    content: str | list[ContentBlock]
    uuid: str | None = None
    parent_tool_use_id: str | None = None

@dataclass
class AssistantMessage:
    content: list[ContentBlock]
    model: str
    parent_tool_use_id: str | None = None
    error: AssistantMessageError | None = None

@dataclass
class SystemMessage:
    subtype: str
    data: dict[str, Any]

@dataclass
class ResultMessage:
    subtype: str
    duration_ms: int
    duration_api_ms: int
    is_error: bool
    num_turns: int
    session_id: str
    total_cost_usd: float | None = None
    usage: dict[str, Any] | None = None
    result: str | None = None
    structured_output: Any = None

@dataclass
class StreamEvent:
    uuid: str
    session_id: str
    event: dict[str, Any]  # Raw Anthropic API stream event
    parent_tool_use_id: str | None = None

Message = UserMessage | AssistantMessage | SystemMessage | ResultMessage | StreamEvent
```

### Elixir Message Types

```elixir
# message.ex (conceptual - parsed from JSON)
%Message{
  type: :user | :assistant | :system | :result | :stream_event,
  subtype: String.t() | nil,
  data: map(),
  raw: map()
}

# Streaming events from EventParser
%{type: :text_delta, text: "...", accumulated: "..."}
%{type: :message_start, model: "...", role: "...", usage: %{}}
%{type: :message_stop, final_text: "..."}
%{type: :tool_use_start, name: "...", id: "..."}
%{type: :tool_input_delta, json: "..."}
%{type: :thinking_start}
%{type: :thinking_delta, thinking: "..."}
%{type: :message_delta, stop_reason: "...", stop_sequence: "..."}
%{type: :content_block_start}
%{type: :content_block_stop, final_text: "..."}
%{type: :error, error_type: "...", message: "..."}
```

### Content Block Types

| Type | Python | Elixir |
|------|--------|--------|
| Text | `TextBlock(text: str)` | `%{type: :text_delta, text: "..."}` |
| Thinking | `ThinkingBlock(thinking: str, signature: str)` | `%{type: :thinking_delta, thinking: "..."}` |
| Tool Use | `ToolUseBlock(id: str, name: str, input: dict)` | `%{type: :tool_use_start, ...}` |
| Tool Result | `ToolResultBlock(tool_use_id: str, ...)` | N/A (handled separately) |

## Event Parsing

### Python: Message Parser

```python
# message_parser.py
def parse_message(data: dict) -> Message:
    msg_type = data.get("type")

    if msg_type == "user":
        return UserMessage(...)
    elif msg_type == "assistant":
        return AssistantMessage(...)
    elif msg_type == "system":
        return SystemMessage(...)
    elif msg_type == "result":
        return ResultMessage(...)
    elif msg_type == "stream_event":
        return StreamEvent(...)
```

### Elixir: EventParser Module

```elixir
# streaming/event_parser.ex
defmodule ClaudeAgentSDK.Streaming.EventParser do
  @spec parse_event(map(), accumulated_text()) ::
    {:ok, [event()], accumulated_text()}

  def parse_event(%{"type" => "message_start"} = event, accumulated_text) do
    model = get_in(event, ["message", "model"])
    events = [%{type: :message_start, model: model, ...}]
    {:ok, events, accumulated_text}
  end

  def parse_event(%{"type" => "content_block_delta", "delta" => delta}, accumulated_text) do
    case delta["type"] do
      "text_delta" ->
        text = delta["text"] || ""
        new_accumulated = accumulated_text <> text
        events = [%{type: :text_delta, text: text, accumulated: new_accumulated}]
        {:ok, events, new_accumulated}

      "input_json_delta" ->
        events = [%{type: :tool_input_delta, json: delta["partial_json"]}]
        {:ok, events, accumulated_text}

      "thinking_delta" ->
        events = [%{type: :thinking_delta, thinking: delta["thinking"]}]
        {:ok, events, accumulated_text}
    end
  end

  def parse_event(%{"type" => "message_stop"} = event, accumulated_text) do
    events = [%{type: :message_stop, final_text: accumulated_text}]
    {:ok, events, ""}  # Reset for next message
  end
end
```

### Key Parsing Differences

| Aspect | Python | Elixir |
|--------|--------|--------|
| Return Type | Single `Message` | List of events |
| Accumulation | In StreamEvent.event | Tracked in `accumulated_text` |
| Text Assembly | Client responsibility | EventParser tracks |
| Unknown Events | Raises error | Returns empty list |

## Control Protocol

Both SDKs implement the same control protocol for bidirectional communication.

### Message Types

```
SDK -> CLI:
  - control_request (initialize, interrupt, set_model, set_permission_mode, ...)
  - user messages

CLI -> SDK:
  - control_response (success, error)
  - control_request (hook_callback, can_use_tool, mcp_message)
  - stream_event / message data
```

### Python Control Protocol

```python
# query.py
class Query:
    async def initialize(self) -> dict | None:
        request = {
            "subtype": "initialize",
            "hooks": hooks_config if hooks_config else None,
        }
        response = await self._send_control_request(request, timeout=60.0)
        return response

    async def _send_control_request(
        self, request: dict, timeout: float = 60.0
    ) -> dict:
        request_id = f"req_{self._request_counter}_{os.urandom(4).hex()}"

        control_request = {
            "type": "control_request",
            "request_id": request_id,
            "request": request,
        }

        await self.transport.write(json.dumps(control_request) + "\n")

        # Wait for response
        with anyio.fail_after(timeout):
            await event.wait()
        return result
```

### Elixir Control Protocol

```elixir
# control_protocol/protocol.ex
defmodule ClaudeAgentSDK.ControlProtocol.Protocol do
  def encode_initialize_request(hooks_config, sdk_mcp_servers, request_id) do
    req_id = request_id || generate_request_id()

    request = %{
      "type" => "control_request",
      "request_id" => req_id,
      "request" => %{
        "subtype" => "initialize",
        "hooks" => hooks_config,
        "sdkMcpServers" => sdk_mcp_servers
      }
    }

    {req_id, Jason.encode!(request)}
  end

  def generate_request_id do
    counter = System.unique_integer([:positive])
    random_hex = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "req_#{counter}_#{random_hex}"
  end
end
```

### Control Request Handling

```elixir
# client.ex
defp handle_control_request(request_data, state) do
  request_id = request_data["request_id"]
  request = request_data["request"]

  case request["subtype"] do
    "hook_callback" ->
      handle_hook_callback(request_id, request, state)

    "can_use_tool" ->
      handle_can_use_tool_request(request_id, request, state)

    "mcp_message" ->
      handle_sdk_mcp_request(request_id, request, state)
  end
end
```

## Session Management

### Python: Query-Based

```python
# Single query (stateless)
async for message in query(prompt="Hello"):
    print(message)

# Streaming with AsyncIterable
async def prompts():
    yield {"type": "user", "message": {...}}

async for message in query(prompt=prompts()):
    print(message)
```

### Python: Client-Based (Interactive)

```python
# ClaudeSDKClient for persistent sessions
client = ClaudeSDKClient()
await client.connect()

# Send message and receive stream
async for message in client.send("Hello"):
    print(message)

# Continue conversation
async for message in client.send("Tell me more"):
    print(message)

await client.disconnect()
```

### Elixir: Streaming Session

```elixir
# Start streaming session
{:ok, session} = ClaudeAgentSDK.Streaming.start_session()

# Send message and get stream
ClaudeAgentSDK.Streaming.send_message(session, "Hello")
|> Stream.each(fn
  %{type: :text_delta, text: text} ->
    IO.write(text)

  %{type: :message_stop} ->
    IO.puts("")
end)
|> Stream.run()

# Continue conversation
ClaudeAgentSDK.Streaming.send_message(session, "Tell me more")
|> Enum.to_list()

# Close session
ClaudeAgentSDK.Streaming.close_session(session)
```

### Elixir: Client-Based

```elixir
# Start client with hooks
{:ok, client} = ClaudeAgentSDK.Client.start_link(options)

# Send message
:ok = ClaudeAgentSDK.Client.send_message(client, "Hello")

# Stream messages
ClaudeAgentSDK.Client.stream_messages(client)
|> Stream.each(&IO.inspect/1)
|> Stream.run()

# Or collect until result
{:ok, messages} = ClaudeAgentSDK.Client.receive_response(client)

# Stop client
ClaudeAgentSDK.Client.stop(client)
```

## Stream Implementation

### Python: AsyncIterator

```python
# query.py
async def query(...) -> AsyncIterator[Message]:
    client = InternalClient()
    async for message in client.process_query(prompt, options, transport):
        yield message

# Internal streaming
async def receive_messages(self) -> AsyncIterator[dict]:
    async for message in self._message_receive:
        if message.get("type") == "end":
            break
        yield message
```

### Elixir: Stream.resource

```elixir
# streaming.ex
def send_message(session, message) when is_pid(session) do
  Session.send_message(session, message)
end

# client.ex
def stream_messages(client) when is_pid(client) do
  Stream.resource(
    fn -> subscribe(client) end,
    fn state -> receive_next_message(state) end,
    fn {client, ref} ->
      GenServer.cast(client, {:unsubscribe, ref})
    end
  )
end

defp receive_next_message({client, ref}) do
  receive do
    {:claude_message, message} ->
      {[message], {client, ref}}

    {:stream_event, ^ref, event} ->
      {[%Message{type: :stream_event, data: %{event: event}}], {client, ref}}
  after
    30_000 ->
      if Process.alive?(client) do
        receive_next_message({client, ref})
      else
        {:halt, {client, ref}}
      end
  end
end
```

## Partial Message Handling

Both SDKs use `--include-partial-messages` CLI flag.

### Python

```python
# types.py
include_partial_messages: bool = False

# subprocess_cli.py
if self._options.include_partial_messages:
    cmd.append("--include-partial-messages")
```

### Elixir

```elixir
# options.ex
defstruct include_partial_messages: false

# streaming.ex
def start_session(options \\ nil) do
  opts = options || %Options{}
  # Force partial messages enabled for streaming
  opts = %{opts | include_partial_messages: true}
  Session.start_link(opts)
end
```

## Event Flow Comparison

### Python Flow

```
CLI Output -> SubprocessCLITransport.read_messages()
           -> Query._read_messages()
           -> Route by type:
              - control_response -> pending_control_responses
              - control_request -> _handle_control_request
              - stream_event -> _message_send
           -> parse_message()
           -> AsyncIterator yield
```

### Elixir Flow

```
CLI Output -> Port/Transport
           -> Client.handle_info()
           -> Protocol.decode_message()
           -> handle_decoded_message():
              - :control_response -> handle_control_response
              - :control_request -> handle_control_request
              - :stream_event -> handle_stream_event
                               -> EventParser.parse_event
                               -> broadcast_events_to_subscriber
           -> Stream.resource
```

## Timeout Handling

### Python

```python
# query.py
async def _send_control_request(
    self, request: dict, timeout: float = 60.0
) -> dict:
    try:
        with anyio.fail_after(timeout):
            await event.wait()
    except TimeoutError as e:
        raise Exception(f"Control request timeout: {request.get('subtype')}")
```

### Elixir

```elixir
# client.ex
@default_init_timeout_ms 60_000
@default_control_request_timeout_ms 60_000

defp schedule_control_request_timeout(request_id) do
  Process.send_after(
    self(),
    {:control_request_timeout, request_id},
    control_request_timeout_ms()
  )
end

def handle_info({:control_request_timeout, request_id}, state) do
  # Reply with {:error, :timeout}
end
```

## Differences Summary

| Aspect | Python | Elixir |
|--------|--------|--------|
| Stream Type | AsyncIterator | Elixir Stream |
| Event Parsing | Single Message return | List of events |
| Text Accumulation | Client-side | EventParser tracks |
| Session State | Client class | GenServer |
| Timeout Mechanism | anyio.fail_after | Process.send_after |
| Subscription Model | Implicit | Explicit ref-based |

## Recommendations

1. **Python**: Consider exposing accumulated text in StreamEvent for easier consumption
2. **Elixir**: Add helper functions for common stream patterns (collect text, etc.)
3. **Both**: Document event type guarantees and ordering
4. **Both**: Add stream cancellation support
