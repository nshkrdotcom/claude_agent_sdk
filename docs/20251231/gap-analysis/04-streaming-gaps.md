# Streaming Implementation Gap Analysis

**Date**: 2025-12-31
**Scope**: Python SDK vs Elixir Port streaming implementation comparison

## Executive Summary

The Elixir port has achieved substantial parity with the Python SDK's streaming implementation, but several architectural differences and gaps remain. Both implementations support bidirectional streaming with control protocol, partial message streaming, and SDK MCP server integration. However, the Python SDK uses `anyio` for sophisticated async coordination (memory streams, task groups), while Elixir leverages OTP patterns (GenServer, message passing, Stream.resource).

**Key Findings:**
- **Streaming Mode Detection**: Both SDKs support automatic detection - Elixir via `StreamingRouter`, Python via `is_streaming_mode` flag
- **Partial Messages**: Both support `include_partial_messages` option with event parsing
- **Memory Streams**: Python uses `anyio.create_memory_object_stream`; Elixir uses process mailboxes (adequate substitute)
- **Task Group Management**: Python uses `anyio.TaskGroup`; Elixir uses supervised tasks with OTP patterns
- **First Result Event Pattern**: Python has explicit `_first_result_event` for SDK MCP; Elixir handles implicitly

**Overall Parity**: ~85% - Core streaming works, but some advanced patterns differ architecturally.

---

## Architecture Comparison

### Python SDK Streaming Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         query.py (Query)                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────────────────┐ │
│  │   stream_input()    │    │      receive_messages()         │ │
│  │  AsyncIterable →    │    │     ← AsyncIterator            │ │
│  │  transport.write()  │    │     _message_receive            │ │
│  └─────────────────────┘    └─────────────────────────────────┘ │
│            │                              ↑                      │
│            ▼                              │                      │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              _read_messages() Task                          ││
│  │  ┌─────────────────┐    ┌────────────────────┐             ││
│  │  │ Control routing │    │ _message_send      │             ││
│  │  │ (responses,     │    │ (memory stream)    │             ││
│  │  │  requests)      │    │                    │             ││
│  │  └─────────────────┘    └────────────────────┘             ││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                subprocess_cli.py (Transport)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────────────┐│
│  │ stdin_stream │  │ stdout_stream│  │ stderr_stream (Task)    ││
│  │ TextSend     │  │ TextReceive  │  │                         ││
│  └──────────────┘  └──────────────┘  └─────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   Claude CLI    │
                    │  Subprocess     │
                    └─────────────────┘
```

### Elixir Port Streaming Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   ClaudeAgentSDK.Client (GenServer)              │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────────────────┐ │
│  │   send_message/2    │    │    stream_messages/1            │ │
│  │   query/3           │    │    receive_response_stream/1    │ │
│  │  → GenServer.call   │    │    ← Stream.resource            │ │
│  └─────────────────────┘    └─────────────────────────────────┘ │
│            │                              ↑                      │
│            ▼                              │                      │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              handle_info callbacks (OTP messages)           ││
│  │  ┌─────────────────┐    ┌────────────────────┐             ││
│  │  │ Control routing │    │ subscribers map    │             ││
│  │  │ (Protocol mod)  │    │ (ref => pid)       │             ││
│  │  └─────────────────┘    └────────────────────┘             ││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                 Transport.Port / Transport.Erlexec              │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────────────┐│
│  │ Port stdin   │  │ Port stdout  │  │ stderr (callback)       ││
│  │ :exec.send   │  │ {:stdout,..} │  │                         ││
│  └──────────────┘  └──────────────┘  └─────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   Claude CLI    │
                    │  Port/Erlexec   │
                    └─────────────────┘
```

---

## Implementation Gaps

### 1. Streaming Mode vs String Mode Handling

| Aspect | Python SDK | Elixir Port | Gap |
|--------|-----------|-------------|-----|
| Mode Detection | `is_streaming_mode = not isinstance(prompt, str)` | `StreamingRouter.select_transport/1` | Equivalent |
| String Mode | Uses `--print` with prompt as arg | Uses `--print` with `--` prompt | Equivalent |
| Stream Mode | Uses `--input-format stream-json` | Uses `--input-format stream-json` | Equivalent |
| Mode Switching | Determined at Query construction | Determined at session/query creation | Equivalent |

**Status**: COMPLETE - Both SDKs correctly differentiate between string prompts and streaming prompts.

**Python Implementation** (subprocess_cli.py:329-334):
```python
if self._is_streaming:
    cmd.extend(["--input-format", "stream-json"])
else:
    cmd.extend(["--print", "--", str(self._prompt)])
```

**Elixir Implementation** (Query.CLIStream:59-67):
```elixir
defp build_prompt_args(prompt, %Options{} = options) when is_binary(prompt) do
  base_args = base_stream_args(options)
  {["--print"] ++ base_args ++ ["--", prompt], nil}
end

defp build_prompt_args(prompt, %Options{} = options) do
  base_args = base_stream_args(options)
  {["--print", "--input-format", "stream-json"] ++ base_args, prompt}
end
```

---

### 2. AsyncIterable Prompt Support

| Aspect | Python SDK | Elixir Port | Gap |
|--------|-----------|-------------|-----|
| Input Type | `AsyncIterable[dict[str, Any]]` | `Enumerable.t()` | Equivalent |
| Streaming Input | `stream_input()` method | Task spawned in `maybe_stream_input/3` | Equivalent |
| Input Task | Part of TaskGroup | Separate Task process | Architectural difference |

**Status**: COMPLETE - Both support streaming prompts.

**Python Implementation** (query.py:557-589):
```python
async def stream_input(self, stream: AsyncIterable[dict[str, Any]]) -> None:
    try:
        async for message in stream:
            if self._closed:
                break
            await self.transport.write(json.dumps(message) + "\n")
        # Wait for first result if SDK MCP/hooks present
        if self.sdk_mcp_servers or has_hooks:
            await self._first_result_event.wait()
        await self.transport.end_input()
```

**Elixir Implementation** (Query.CLIStream:173-181):
```elixir
defp maybe_stream_input(module, transport, input) do
  {:ok, pid} = Task.start(fn -> stream_input_messages(module, transport, input) end)
  pid
end

defp stream_input_messages(module, transport, input) do
  Enum.each(input, fn message -> module.send(transport, message) end)
  module.end_input(transport)
end
```

**Gap**: Elixir lacks the `_first_result_event` synchronization pattern for SDK MCP servers. The Python SDK waits for the first result before closing stdin when hooks/SDK MCP are present. See Gap #5.

---

### 3. Bidirectional Communication (stdin/stdout)

| Aspect | Python SDK | Elixir Port | Gap |
|--------|-----------|-------------|-----|
| Write to stdin | `transport.write()` | `Transport.send/2` | Equivalent |
| Read from stdout | `transport.read_messages()` | `handle_info/{:stdout,...}` | Equivalent |
| Write Lock | `_write_lock: anyio.Lock` | GenServer serialization | Equivalent (different pattern) |
| End Input | `transport.end_input()` | `Transport.Erlexec.end_input/1` | Partial - Port lacks |

**Status**: MOSTLY COMPLETE

**Python Implementation** (subprocess_cli.py:524-548):
```python
async def write(self, data: str) -> None:
    async with self._write_lock:
        if not self._ready or not self._stdin_stream:
            raise CLIConnectionError("ProcessTransport is not ready")
        await self._stdin_stream.send(data)

async def end_input(self) -> None:
    async with self._write_lock:
        if self._stdin_stream:
            await self._stdin_stream.aclose()
            self._stdin_stream = None
```

**Elixir Implementation** (Transport.Erlexec:126-147):
```elixir
def handle_call({:send, message}, _from, %{subprocess: {pid, _os_pid}} = state) do
  payload = message |> normalize_payload() |> ensure_newline()
  :exec.send(pid, payload)
  {:reply, :ok, state}
end

def handle_call(:end_input, _from, %{subprocess: {pid, _os_pid}} = state) do
  :exec.send(pid, :eof)
  {:reply, :ok, state}
end
```

**Gap**: `Transport.Port` module does not implement `end_input/1`. Only `Transport.Erlexec` supports it. This is why `CLIStream` always defaults to Erlexec:

```elixir
# Always use Erlexec - Port transport can't close stdin independently
defp normalize_transport(nil, _options, _input) do
  {ClaudeAgentSDK.Transport.Erlexec, []}
end
```

---

### 4. Stream Termination and Cleanup

| Aspect | Python SDK | Elixir Port | Gap |
|--------|-----------|-------------|-----|
| Task Cancellation | `_tg.cancel_scope.cancel()` | `Process.exit(task, :kill)` | Equivalent |
| Resource Cleanup | `close()` method | `terminate/2` callback | Equivalent |
| Graceful Shutdown | Waits for task group exit | Handles `:DOWN` messages | Equivalent |
| Temp File Cleanup | `_temp_files` list cleanup | `AgentsFile.cleanup_temp_files/1` | Equivalent |

**Status**: COMPLETE

**Python Implementation** (query.py:602-610):
```python
async def close(self) -> None:
    self._closed = True
    if self._tg:
        self._tg.cancel_scope.cancel()
        with suppress(anyio.get_cancelled_exc_class()):
            await self._tg.__aexit__(None, None, None)
    await self.transport.close()
```

**Elixir Implementation** (Client:1097-1163):
```elixir
def terminate(reason, %{transport: transport, transport_module: module} = state)
    when is_pid(transport) do
  state = state |> cancel_init_timeout() |> cancel_pending_callbacks()
  try do
    module.close(transport)
  catch
    :exit, _ -> :ok
  end
  terminate(reason, %{state | transport: nil})
end
```

---

### 5. StreamEvent Partial Message Support

| Aspect | Python SDK | Elixir Port | Gap |
|--------|-----------|-------------|-----|
| CLI Flag | `--include-partial-messages` | `--include-partial-messages` | Equivalent |
| StreamEvent Type | `StreamEvent` dataclass | Map with `:type` key | Equivalent (different structure) |
| Event Parsing | Part of Message handling | `EventParser.parse_event/2` | Equivalent |
| Accumulated Text | Manual concatenation | `accumulated_text` field | Equivalent |

**Status**: COMPLETE

**Python StreamEvent Type** (types.py:604-611):
```python
@dataclass
class StreamEvent:
    uuid: str
    session_id: str
    event: dict[str, Any]  # Raw Anthropic API stream event
    parent_tool_use_id: str | None = None
```

**Elixir Event Parsing** (Streaming.EventParser:113-160):
```elixir
def parse_event(%{"type" => "content_block_delta", "delta" => delta}, accumulated_text) do
  case delta["type"] do
    "text_delta" ->
      text = delta["text"] || ""
      new_accumulated = accumulated_text <> text
      events = [%{type: :text_delta, text: text, accumulated: new_accumulated}]
      {:ok, events, new_accumulated}

    "input_json_delta" ->
      json_part = delta["partial_json"] || ""
      events = [%{type: :tool_input_delta, json: json_part}]
      {:ok, events, accumulated_text}

    "thinking_delta" ->
      thinking = delta["thinking"] || ""
      events = [%{type: :thinking_delta, thinking: thinking}]
      {:ok, events, accumulated_text}
  end
end
```

---

### 6. Memory Stream / Buffering (anyio.create_memory_object_stream equivalent)

| Aspect | Python SDK | Elixir Port | Gap |
|--------|-----------|-------------|-----|
| Message Buffer | `anyio.create_memory_object_stream` | Process mailbox | Architectural difference |
| Buffer Size | `max_buffer_size=100` | Unlimited (OTP mailbox) | Different semantics |
| Producer/Consumer | `_message_send` / `_message_receive` | `send/2` / `receive` | Equivalent patterns |
| Backpressure | Built into stream | Not explicitly handled | Minor gap |

**Status**: ADEQUATE - Different patterns, same effect

**Python Implementation** (query.py:102-104):
```python
self._message_send, self._message_receive = anyio.create_memory_object_stream[
    dict[str, Any]
](max_buffer_size=100)
```

**Elixir Equivalent**: Process mailboxes with message passing. The `subscribers` map in `Client` state serves as the routing mechanism:

```elixir
# Client state has subscribers map: ref => pid
subscribers: %{reference() => pid()}

# Broadcasting to subscribers
defp broadcast_events_to_subscriber(ref, subscribers, events) do
  case Map.get(subscribers, ref) do
    nil -> :ok
    pid -> Enum.each(events, fn event -> send(pid, {:stream_event, ref, event}) end)
  end
end
```

**Gap**: Python's memory object stream has a bounded buffer (100 messages) providing natural backpressure. Elixir uses unbounded process mailboxes. This is typically not an issue due to OTP's efficient mailbox handling, but could theoretically cause memory issues under extreme load.

---

### 7. Task Group Management for Concurrent Read/Write

| Aspect | Python SDK | Elixir Port | Gap |
|--------|-----------|-------------|-----|
| Task Group | `anyio.create_task_group()` | GenServer + supervised Tasks | Equivalent pattern |
| Read Task | `_tg.start_soon(self._read_messages)` | `handle_info` callbacks | Equivalent |
| Write Task | `_tg.start_soon(...)` for control requests | `Task.start` for callbacks | Equivalent |
| Cancellation | `cancel_scope.cancel()` | `Process.exit(:kill)` | Equivalent |

**Status**: COMPLETE - Different async patterns, same semantics

**Python Implementation** (query.py:160-165):
```python
async def start(self) -> None:
    if self._tg is None:
        self._tg = anyio.create_task_group()
        await self._tg.__aenter__()
        self._tg.start_soon(self._read_messages)
```

**Elixir Implementation**: Uses OTP patterns - GenServer handles the main loop, Tasks for async callbacks:

```elixir
# Hook callback execution (Client:1820-1827)
{:ok, pid} = Task.start(fn ->
  result = execute_hook_callback(callback_fn, input, tool_use_id, signal, timeout_ms)
  send(server, {:callback_result, request_id, :hook, signal, result})
end)

# Permission callback execution (Client:1888-1901)
{:ok, pid} = Task.start(fn ->
  result = execute_permission_callback(callback, tool_name, tool_input, ...)
  send(server, {:callback_result, request_id, :permission, signal, tool_input, result})
end)
```

---

### 8. _first_result_event Pattern for SDK MCP/Hooks

| Aspect | Python SDK | Elixir Port | Gap |
|--------|-----------|-------------|-----|
| First Result Tracking | `_first_result_event = anyio.Event()` | Not implemented | GAP |
| Stdin Close Delay | Waits for first result | No waiting | GAP |
| Timeout | `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` env | N/A | GAP |
| Purpose | Keep stdin open for SDK MCP responses | N/A | GAP |

**Status**: GAP - Elixir does not implement this pattern

**Python Implementation** (query.py:111-114, 569-584):
```python
# Initialization
self._first_result_event = anyio.Event()
self._stream_close_timeout = (
    float(os.environ.get("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", "60000")) / 1000.0
)

# In stream_input()
if self.sdk_mcp_servers or has_hooks:
    logger.debug("Waiting for first result before closing stdin")
    try:
        with anyio.move_on_after(self._stream_close_timeout):
            await self._first_result_event.wait()
    except Exception:
        logger.debug("Timed out waiting for first result")
await self.transport.end_input()
```

**Elixir Gap**: The `Query.CLIStream` module closes stdin immediately after sending all input messages, without waiting for any result:

```elixir
defp stream_input_messages(module, transport, input) do
  Enum.each(input, fn message -> module.send(transport, message) end)
  module.end_input(transport)  # Closes immediately, no wait
end
```

**Impact**: For SDK MCP servers that require bidirectional communication during the response, the Elixir implementation might close stdin prematurely. However, when using the `Client` GenServer (which is used for control protocol features), stdin remains open for the duration of the GenServer's lifecycle.

**Workaround**: The `Client` GenServer handles this implicitly by keeping the connection open until explicitly stopped. The `ClientStream` module wraps `Client` for queries requiring control protocol, which keeps the connection alive.

---

## Priority Recommendations

### Critical (P0)

None - Core streaming functionality is complete.

### High Priority (P1)

1. **Implement `_first_result_event` Pattern in CLIStream**
   - Add synchronization before `end_input` when SDK MCP servers or hooks are configured
   - Implement configurable timeout via `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` environment variable
   - Location: `lib/claude_agent_sdk/query/cli_stream.ex`

   ```elixir
   # Proposed implementation
   defp stream_input_messages(module, transport, input, has_control_features?) do
     Enum.each(input, fn message -> module.send(transport, message) end)

     if has_control_features? do
       # Wait for first result before closing
       timeout = stream_close_timeout_ms()
       receive do
         {:first_result, _} -> :ok
       after
         timeout -> Logger.debug("Timed out waiting for first result")
       end
     end

     module.end_input(transport)
   end
   ```

2. **Add `end_input/1` to Transport.Port**
   - For consistency with Erlexec transport
   - Would require platform-specific stdin closing via Port API
   - Location: `lib/claude_agent_sdk/transport/port.ex`

### Medium Priority (P2)

3. **Add Backpressure Mechanism**
   - Consider implementing bounded mailbox semantics for high-volume streaming
   - Could use `GenStage` or demand-based flow control
   - Low priority as OTP mailboxes handle most practical loads

4. **Unified StreamEvent Type**
   - Consider creating an `%EventParser.Event{}` struct for consistency with Python's `StreamEvent` dataclass
   - Would provide better type safety and documentation

### Low Priority (P3)

5. **Document Architectural Differences**
   - Add developer documentation explaining Python `anyio` patterns vs Elixir OTP patterns
   - Help contributors understand the mapping between implementations

---

## Appendix: Key File Mappings

| Python SDK | Elixir Port | Purpose |
|-----------|-------------|---------|
| `_internal/query.py` | `lib/claude_agent_sdk/client.ex` | Control protocol handling |
| `_internal/transport/subprocess_cli.py` | `lib/claude_agent_sdk/transport/erlexec.ex` | CLI subprocess management |
| `types.py:StreamEvent` | Inline maps in `streaming/event_parser.ex` | Streaming event types |
| N/A | `lib/claude_agent_sdk/streaming/session.ex` | GenServer for persistent sessions |
| N/A | `lib/claude_agent_sdk/query/cli_stream.ex` | Unidirectional CLI queries |
| N/A | `lib/claude_agent_sdk/query/client_stream.ex` | Control protocol query wrapper |
| N/A | `lib/claude_agent_sdk/transport/streaming_router.ex` | Transport selection logic |

---

## Conclusion

The Elixir port provides a robust streaming implementation that achieves functional parity with the Python SDK. The architectural differences (OTP patterns vs async/await) are appropriate for each language ecosystem. The main gap is the `_first_result_event` synchronization pattern, which should be addressed for full compatibility with SDK MCP servers in the `CLIStream` path. The `Client` GenServer path already handles this implicitly through its persistent connection lifecycle.
