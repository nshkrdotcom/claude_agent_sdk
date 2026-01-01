# Elixir SDK Implementation Gaps - Technical Documentation

> **Generated:** 2025-12-31
> **SDK Version:** Elixir v0.7.3 vs Python v0.1.18
> **Overall Parity Score:** 96%

This document provides comprehensive technical specifications for implementing all missing or incorrect features in the Claude Agent SDK Elixir port to achieve full parity with the Python SDK.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Priority 1 Gaps (High)](#priority-1-gaps-high)
3. [Priority 2 Gaps (Medium)](#priority-2-gaps-medium)
4. [Priority 3 Gaps (Low)](#priority-3-gaps-low)
5. [Feature Comparison Matrix](#feature-comparison-matrix)
6. [Implementation Specifications](#implementation-specifications)
7. [Testing Requirements](#testing-requirements)
8. [Migration Guide](#migration-guide)

---

## Executive Summary

The Elixir SDK has achieved **96% parity** with the Python SDK. The remaining gaps are primarily:

- **4 High Priority (P1)** - Core functionality gaps requiring implementation
- **8 Medium Priority (P2)** - API enhancements and documentation
- **5 Low Priority (P3)** - Optional improvements and future enhancements

### Areas Exceeding Python SDK

The Elixir SDK provides additional features not present in Python:

| Feature | Description |
|---------|-------------|
| Dual Transport | Port (default) + Erlexec (user switching) |
| AbortSignal | Full implementation with atomics |
| Cancel Requests | Complete handling vs Python TODO |
| Agent Switching | `set_agent/2`, `get_agent/1`, `get_available_agents/1` |
| Session API | `resume/3`, `continue/2` at Query level |
| Streaming Events | Partial message accumulation with `accumulated` field |
| OTP Supervision | GenServer architecture with supervision |

---

## Priority 1 Gaps (High)

### P1-001: Base Error Hierarchy

**Area:** Error Handling
**Severity:** High
**Effort:** Medium
**Files:** `lib/claude_agent_sdk/errors.ex`

#### Current State (Elixir)

```elixir
defmodule ClaudeAgentSDK.Errors.ClaudeSDKError do
  defexception [:message, :cause]
end

defmodule ClaudeAgentSDK.Errors.CLIConnectionError do
  defexception [:message, :cwd, :reason]
end

# Each error is independent - no inheritance relationship
```

#### Target State (Python Parity)

```python
class ClaudeSDKError(Exception):
    """Base exception for all Claude SDK errors."""

class CLIConnectionError(ClaudeSDKError):
    """Inherits from base"""

class CLINotFoundError(CLIConnectionError):
    """Inherits from connection error"""
```

#### Implementation Specification

1. **Add base behavior module:**

```elixir
defmodule ClaudeAgentSDK.Errors do
  @moduledoc """
  Base module for all SDK errors. Provides common error utilities.
  """

  @type sdk_error ::
    ClaudeAgentSDK.Errors.ClaudeSDKError.t()
    | ClaudeAgentSDK.Errors.CLIConnectionError.t()
    | ClaudeAgentSDK.Errors.CLINotFoundError.t()
    | ClaudeAgentSDK.Errors.ProcessError.t()
    | ClaudeAgentSDK.Errors.CLIJSONDecodeError.t()
    | ClaudeAgentSDK.Errors.MessageParseError.t()

  @doc """
  Check if an exception is an SDK error.
  """
  @spec sdk_error?(Exception.t()) :: boolean()
  def sdk_error?(%ClaudeAgentSDK.Errors.ClaudeSDKError{}), do: true
  def sdk_error?(%ClaudeAgentSDK.Errors.CLIConnectionError{}), do: true
  def sdk_error?(%ClaudeAgentSDK.Errors.CLINotFoundError{}), do: true
  def sdk_error?(%ClaudeAgentSDK.Errors.ProcessError{}), do: true
  def sdk_error?(%ClaudeAgentSDK.Errors.CLIJSONDecodeError{}), do: true
  def sdk_error?(%ClaudeAgentSDK.Errors.MessageParseError{}), do: true
  def sdk_error?(_), do: false

  @doc """
  Get error category for an SDK error.
  """
  @spec category(sdk_error()) :: :connection | :process | :parse | :generic
  def category(%ClaudeAgentSDK.Errors.CLIConnectionError{}), do: :connection
  def category(%ClaudeAgentSDK.Errors.CLINotFoundError{}), do: :connection
  def category(%ClaudeAgentSDK.Errors.ProcessError{}), do: :process
  def category(%ClaudeAgentSDK.Errors.CLIJSONDecodeError{}), do: :parse
  def category(%ClaudeAgentSDK.Errors.MessageParseError{}), do: :parse
  def category(%ClaudeAgentSDK.Errors.ClaudeSDKError{}), do: :generic
end
```

2. **Add `is_sdk_error/1` guard macro:**

```elixir
defmodule ClaudeAgentSDK.Errors.Guards do
  defmacro is_sdk_error(error) do
    quote do
      is_struct(unquote(error), ClaudeAgentSDK.Errors.ClaudeSDKError) or
      is_struct(unquote(error), ClaudeAgentSDK.Errors.CLIConnectionError) or
      is_struct(unquote(error), ClaudeAgentSDK.Errors.CLINotFoundError) or
      is_struct(unquote(error), ClaudeAgentSDK.Errors.ProcessError) or
      is_struct(unquote(error), ClaudeAgentSDK.Errors.CLIJSONDecodeError) or
      is_struct(unquote(error), ClaudeAgentSDK.Errors.MessageParseError)
    end
  end
end
```

3. **Usage Example:**

```elixir
import ClaudeAgentSDK.Errors.Guards

try do
  ClaudeAgentSDK.query("prompt", opts)
rescue
  e when is_sdk_error(e) ->
    # Handle any SDK error
    Logger.error("SDK Error: #{Exception.message(e)}")

  e in [ClaudeAgentSDK.Errors.CLIConnectionError, ClaudeAgentSDK.Errors.CLINotFoundError] ->
    # Handle connection-specific errors
    Logger.error("Connection failed: #{e.reason}")
end
```

#### Testing Requirements

```elixir
# test/claude_agent_sdk/errors_test.exs
describe "sdk_error?/1" do
  test "returns true for all SDK error types" do
    assert Errors.sdk_error?(%Errors.ClaudeSDKError{message: "test"})
    assert Errors.sdk_error?(%Errors.CLIConnectionError{message: "test"})
    # ... test all error types
  end

  test "returns false for non-SDK exceptions" do
    refute Errors.sdk_error?(%RuntimeError{message: "test"})
  end
end

describe "category/1" do
  test "categorizes connection errors" do
    assert Errors.category(%Errors.CLIConnectionError{}) == :connection
    assert Errors.category(%Errors.CLINotFoundError{}) == :connection
  end
end
```

---

### P1-002: Simple Schema Conversion for MCP Tools

**Area:** MCP Integration
**Severity:** High
**Effort:** Low
**Files:** `lib/claude_agent_sdk/tool.ex`

#### Current State (Elixir)

Requires full JSON Schema:
```elixir
deftool :add, "Add two numbers", %{
  type: "object",
  properties: %{
    "a" => %{type: "number", description: "First number"},
    "b" => %{type: "number", description: "Second number"}
  },
  required: ["a", "b"]
} do
  # implementation
end
```

#### Target State (Python Parity)

Python allows simple type mappings:
```python
@tool("add", "Add two numbers", {"a": float, "b": float})
async def add(args):
    return args["a"] + args["b"]
```

#### Implementation Specification

The `simple_schema/1` helper already exists but needs enhancement:

```elixir
# lib/claude_agent_sdk/tool.ex

@doc """
Convert a simple type specification to a full JSON Schema.

## Examples

    # All strings, all required
    simple_schema([:name, :path])

    # With types
    simple_schema(a: :number, b: :number)

    # With descriptions
    simple_schema(name: {:string, "User name"}, age: {:number, "Age in years"})

    # With optional fields
    simple_schema(name: :string, email: {:string, optional: true})

    # NEW: Python-style type mapping
    simple_schema(%{a: :float, b: :float})
    simple_schema(%{"a" => Float, "b" => Float})

"""
@spec simple_schema(keyword() | [atom()] | map()) :: map()
def simple_schema(fields) when is_list(fields) do
  # Existing implementation
  {properties, required} = build_schema_fields(fields)
  %{
    "type" => "object",
    "properties" => properties,
    "required" => required
  }
end

# NEW: Support Python-style map syntax
def simple_schema(fields) when is_map(fields) do
  {properties, required} =
    fields
    |> Enum.map(fn {key, type} ->
      key_str = to_string(key)
      schema = type_to_json_schema(type)
      {key_str, {key_str, schema}}
    end)
    |> Enum.unzip()
    |> then(fn {keys, props} -> {Map.new(props), keys} end)

  %{
    "type" => "object",
    "properties" => properties,
    "required" => required
  }
end

# Type conversion matching Python SDK
defp type_to_json_schema(:string), do: %{"type" => "string"}
defp type_to_json_schema(:float), do: %{"type" => "number"}
defp type_to_json_schema(:number), do: %{"type" => "number"}
defp type_to_json_schema(:integer), do: %{"type" => "integer"}
defp type_to_json_schema(:boolean), do: %{"type" => "boolean"}
defp type_to_json_schema(:array), do: %{"type" => "array"}
defp type_to_json_schema(:object), do: %{"type" => "object"}
# Erlang/Elixir module types (for Python parity)
defp type_to_json_schema(String), do: %{"type" => "string"}
defp type_to_json_schema(Float), do: %{"type" => "number"}
defp type_to_json_schema(Integer), do: %{"type" => "integer"}
defp type_to_json_schema(type) when is_atom(type), do: %{"type" => to_string(type)}
```

#### Usage After Implementation

```elixir
# Python-equivalent syntax
deftool :add, "Add two numbers", Tool.simple_schema(%{a: :float, b: :float}) do
  {:ok, %{result: input["a"] + input["b"]}}
end

# More concise macro variant (optional enhancement)
deftool :add, "Add two numbers", {a: :float, b: :float} do
  {:ok, %{result: input["a"] + input["b"]}}
end
```

#### Testing Requirements

```elixir
describe "simple_schema/1 with map syntax" do
  test "converts map with atom types" do
    schema = Tool.simple_schema(%{a: :float, b: :float})
    assert schema["properties"]["a"]["type"] == "number"
    assert schema["properties"]["b"]["type"] == "number"
    assert "a" in schema["required"]
    assert "b" in schema["required"]
  end

  test "converts map with module types" do
    schema = Tool.simple_schema(%{"name" => String, "age" => Integer})
    assert schema["properties"]["name"]["type"] == "string"
    assert schema["properties"]["age"]["type"] == "integer"
  end
end
```

---

### P1-003: First Result Event Pattern for CLIStream

**Area:** Streaming Implementation
**Severity:** High
**Effort:** Medium
**Files:** `lib/claude_agent_sdk/query/cli_stream.ex`

#### Current State (Elixir)

CLIStream closes stdin immediately after sending user message:
```elixir
# Current implementation
defp stream_query(prompt, options) do
  # ... spawn subprocess
  Port.command(port, prompt_json)
  send(port, {self(), :close})  # Immediately closes stdin
  # ... read responses
end
```

#### Target State (Python Parity)

Python waits for first result before closing:
```python
# Python query.py lines 577-584
if self.sdk_mcp_servers or has_hooks:
    logger.debug(f"Waiting for first result before closing stdin")
    try:
        with anyio.move_on_after(self._stream_close_timeout):
            await self._first_result_event.wait()
            logger.debug("Received first result, closing input stream")
    except Exception:
        logger.debug("Timed out waiting for first result")
```

#### Implementation Specification

1. **Add result tracking to CLIStream:**

```elixir
# lib/claude_agent_sdk/query/cli_stream.ex

defmodule ClaudeAgentSDK.Query.CLIStream do
  @stream_close_timeout_env "CLAUDE_CODE_STREAM_CLOSE_TIMEOUT"
  @default_stream_close_timeout_ms 60_000

  defp stream_close_timeout_ms do
    case System.get_env(@stream_close_timeout_env) do
      nil -> @default_stream_close_timeout_ms
      val ->
        case Integer.parse(val) do
          {ms, _} when ms > 0 -> ms
          _ -> @default_stream_close_timeout_ms
        end
    end
  end

  defp has_control_features?(options) do
    has_sdk_mcp = options.mcp_servers
      |> Map.values()
      |> Enum.any?(&match?(%{type: :sdk}, &1))

    has_hooks = options.hooks != nil and map_size(options.hooks) > 0

    has_sdk_mcp or has_hooks
  end

  defp stream_query(prompt, options) do
    {:ok, port} = open_port(options)
    Port.command(port, encode_prompt(prompt))

    # NEW: Conditionally wait for first result
    if has_control_features?(options) do
      wait_for_first_result_then_close(port, stream_close_timeout_ms())
    else
      # No control features - close immediately (existing behavior)
      send(port, {self(), :close})
    end

    stream_responses(port)
  end

  defp wait_for_first_result_then_close(port, timeout_ms) do
    receive do
      {^port, {:data, data}} ->
        # Check if this is a result message
        case parse_for_result(data) do
          {:result, _} ->
            send(port, {self(), :close})
            # Re-emit this message to the stream
            send(self(), {:reemit, data})
          _ ->
            # Not a result, keep waiting
            send(self(), {:reemit, data})
            wait_for_first_result_then_close(port, timeout_ms)
        end
    after
      timeout_ms ->
        Logger.debug("Timed out waiting for first result, closing stdin")
        send(port, {self(), :close})
    end
  end

  defp parse_for_result(data) do
    case Jason.decode(data) do
      {:ok, %{"type" => "result"} = msg} -> {:result, msg}
      {:ok, msg} -> {:other, msg}
      _ -> :parse_error
    end
  end
end
```

2. **Alternative: Use Task for non-blocking wait:**

```elixir
defp wait_for_first_result_then_close(port, timeout_ms, parent) do
  Task.start(fn ->
    receive do
      {:first_result_received, ^port} ->
        send(port, {parent, :close})
    after
      timeout_ms ->
        Logger.debug("Timeout waiting for first result")
        send(port, {parent, :close})
    end
  end)
end
```

#### Testing Requirements

```elixir
describe "first result event pattern" do
  test "waits for result when SDK MCP servers present" do
    mcp_server = ClaudeAgentSDK.create_sdk_mcp_server(
      name: "test",
      tools: [TestTool]
    )

    options = %Options{mcp_servers: %{"test" => mcp_server}}

    # Verify stdin not closed before result
    # This requires mock transport or integration test
  end

  test "closes immediately when no control features" do
    options = %Options{}
    # Verify immediate close
  end

  test "respects CLAUDE_CODE_STREAM_CLOSE_TIMEOUT" do
    System.put_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", "5000")
    # Verify 5 second timeout
    System.delete_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT")
  end
end
```

---

### P1-004: Output.async/1 Helper

**Area:** Hooks Implementation
**Severity:** High
**Effort:** Low
**Files:** `lib/claude_agent_sdk/hooks/output.ex`

#### Current State (Elixir)

Async hooks work but require manual map construction:
```elixir
def my_async_hook(input, _tool_use_id, _context) do
  %{
    "async" => true,
    "asyncTimeout" => 30_000
  }
end
```

#### Target State (Python Parity)

```python
class AsyncHookJSONOutput(TypedDict):
    async_: Literal[True]
    asyncTimeout: NotRequired[int]
```

#### Implementation Specification

Add helpers to `lib/claude_agent_sdk/hooks/output.ex`:

```elixir
defmodule ClaudeAgentSDK.Hooks.Output do
  # ... existing code ...

  @doc """
  Mark a hook output for async execution.

  Async hooks allow long-running operations without blocking Claude.
  The hook will be executed in the background and Claude will continue
  processing while waiting for the result.

  ## Examples

      Output.allow("Processing")
      |> Output.async()
      |> Output.with_async_timeout(30_000)

      # Or directly
      Output.async()
      |> Output.with_async_timeout(60_000)

  """
  @spec async(map()) :: map()
  def async(output \\ %{}) when is_map(output) do
    Map.put(output, :async, true)
  end

  @doc """
  Set timeout for async hook execution.

  ## Parameters

    * `output` - The hook output map
    * `timeout_ms` - Timeout in milliseconds (default: 60000)

  ## Examples

      Output.async()
      |> Output.with_async_timeout(30_000)  # 30 seconds

  """
  @spec with_async_timeout(map(), pos_integer()) :: map()
  def with_async_timeout(output, timeout_ms)
      when is_map(output) and is_integer(timeout_ms) and timeout_ms > 0 do
    output
    |> ensure_async()
    |> Map.put(:asyncTimeout, timeout_ms)
  end

  defp ensure_async(output) do
    if Map.get(output, :async, false) do
      output
    else
      Map.put(output, :async, true)
    end
  end

  # Update serialization to handle async fields
  @doc false
  def to_cli_format(output) when is_map(output) do
    output
    |> maybe_convert_async_field()
    |> maybe_convert_continue_field()
    |> convert_keys_to_strings()
  end

  defp maybe_convert_async_field(output) do
    case Map.pop(output, :async) do
      {nil, output} -> output
      {value, output} -> Map.put(output, "async", value)
    end
  end
end
```

#### Usage Example

```elixir
defmodule MyHooks do
  alias ClaudeAgentSDK.Hooks.Output

  def slow_security_check(input, _tool_use_id, _context) do
    # This will run async with 30 second timeout
    Output.allow("Running security scan")
    |> Output.async()
    |> Output.with_async_timeout(30_000)
  end

  def background_audit(input, _tool_use_id, _context) do
    # Simple async with default timeout
    Output.async()
  end
end
```

#### Testing Requirements

```elixir
describe "async/1" do
  test "marks output for async execution" do
    output = Output.async()
    assert output[:async] == true
  end

  test "preserves existing output fields" do
    output = Output.allow("test") |> Output.async()
    assert output[:async] == true
    assert output.hookSpecificOutput.permissionDecision == "allow"
  end
end

describe "with_async_timeout/2" do
  test "sets async timeout" do
    output = Output.async() |> Output.with_async_timeout(30_000)
    assert output[:asyncTimeout] == 30_000
  end

  test "auto-enables async if not set" do
    output = %{} |> Output.with_async_timeout(5_000)
    assert output[:async] == true
    assert output[:asyncTimeout] == 5_000
  end
end
```

---

## Priority 2 Gaps (Medium)

### P2-001: Timeout Configuration Documentation

**Area:** Control Protocol
**Effort:** Low (documentation only)
**Files:** README.md, `lib/claude_agent_sdk/client.ex` @moduledoc

Add comprehensive documentation for timeout configuration:

```markdown
## Timeout Configuration

The SDK supports configurable timeouts for control protocol operations.

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` | Initialize request timeout (ms) | 60000 |

### Application Configuration

```elixir
# config/config.exs
config :claude_agent_sdk,
  control_request_timeout_ms: 60_000,
  initialize_timeout_ms: 60_000

### Per-Hook Timeouts

```elixir
Matcher.new("Bash", [&my_hook/3], timeout_ms: 30_000)
```
```

---

### P2-002: Discriminated Union Hook Input Types

**Area:** Hooks Implementation
**Effort:** Medium
**Files:** `lib/claude_agent_sdk/hooks/input.ex` (new file)

Add typed input structs for better IDE support:

```elixir
defmodule ClaudeAgentSDK.Hooks.Input do
  @moduledoc """
  Typed input structures for hook callbacks.
  """

  defmodule PreToolUse do
    @type t :: %__MODULE__{
      session_id: String.t(),
      transcript_path: String.t(),
      cwd: String.t(),
      tool_name: String.t(),
      tool_input: map()
    }
    defstruct [:session_id, :transcript_path, :cwd, :tool_name, :tool_input]

    def from_map(map) when is_map(map) do
      %__MODULE__{
        session_id: map["session_id"],
        transcript_path: map["transcript_path"],
        cwd: map["cwd"],
        tool_name: map["tool_name"],
        tool_input: map["tool_input"]
      }
    end
  end

  defmodule PostToolUse do
    @type t :: %__MODULE__{
      session_id: String.t(),
      transcript_path: String.t(),
      cwd: String.t(),
      tool_name: String.t(),
      tool_input: map(),
      tool_response: term()
    }
    defstruct [:session_id, :transcript_path, :cwd, :tool_name, :tool_input, :tool_response]
  end

  defmodule UserPromptSubmit do
    @type t :: %__MODULE__{
      session_id: String.t(),
      transcript_path: String.t(),
      cwd: String.t(),
      prompt: String.t()
    }
    defstruct [:session_id, :transcript_path, :cwd, :prompt]
  end

  defmodule Stop do
    @type t :: %__MODULE__{
      session_id: String.t(),
      transcript_path: String.t(),
      cwd: String.t(),
      stop_hook_active: boolean()
    }
    defstruct [:session_id, :transcript_path, :cwd, :stop_hook_active]
  end

  # ... SubagentStop, PreCompact structs
end
```

---

### P2-003: with_updated_input/2 Helper

**Area:** Hooks Implementation
**Effort:** Low
**Files:** `lib/claude_agent_sdk/hooks/output.ex`

```elixir
@doc """
Modify tool input before execution (PreToolUse hooks only).

## Examples

    Output.allow("Input sanitized")
    |> Output.with_updated_input(%{
      "path" => sanitize_path(input["path"])
    })

"""
@spec with_updated_input(map(), map()) :: map()
def with_updated_input(output, updated_input)
    when is_map(output) and is_map(updated_input) do
  hook_output = Map.get(output, :hookSpecificOutput, %{})
  updated_hook_output = Map.put(hook_output, :updatedInput, updated_input)
  Map.put(output, :hookSpecificOutput, updated_hook_output)
end
```

---

### P2-004: Add end_input/1 to Transport Behaviour

**Area:** Transport Layer
**Effort:** Low
**Files:** `lib/claude_agent_sdk/transport.ex`, `lib/claude_agent_sdk/transport/port.ex`

```elixir
# lib/claude_agent_sdk/transport.ex
@callback end_input(state :: term()) :: :ok | {:error, term()}

# lib/claude_agent_sdk/transport/port.ex
@impl Transport
def end_input(%{port: port} = state) do
  try do
    send(port, {self(), :close})
    :ok
  catch
    :error, _ -> {:error, :port_closed}
  end
end
```

---

### P2-005: MCP SSE and HTTP Server Types

**Area:** MCP Integration
**Effort:** Medium
**Files:** `lib/claude_agent_sdk/options.ex`

Currently missing SSE and HTTP MCP server types:

```elixir
# Add to options.ex type definitions

@type mcp_sse_server :: %{
  type: :sse,
  url: String.t(),
  headers: %{optional(String.t()) => String.t()}
}

@type mcp_http_server :: %{
  type: :http,
  url: String.t(),
  headers: %{optional(String.t()) => String.t()}
}

@type mcp_server ::
  sdk_mcp_server()
  | stdio_mcp_server()
  | mcp_sse_server()      # NEW
  | mcp_http_server()     # NEW

# Add serialization in prepare_servers_for_cli/1
defp prepare_server_for_cli(%{type: :sse} = server) do
  %{
    "type" => "sse",
    "url" => server.url,
    "headers" => server[:headers] || %{}
  }
end

defp prepare_server_for_cli(%{type: :http} = server) do
  %{
    "type" => "http",
    "url" => server.url,
    "headers" => server[:headers] || %{}
  }
end
```

---

## Priority 3 Gaps (Low)

### P3-001: Protocol Version Negotiation

Future enhancement for control protocol versioning.

### P3-002: Telemetry Integration

Add optional telemetry events for observability:

```elixir
:telemetry.execute(
  [:claude_agent_sdk, :control_request, :start],
  %{system_time: System.system_time()},
  %{request_id: id, subtype: subtype}
)
```

### P3-003: Architecture Documentation

Create ARCHITECTURE.md documenting:
- Python async/await vs Elixir GenServer patterns
- Transport layer abstraction
- Control protocol flow
- Message parsing pipeline

---

## Feature Comparison Matrix

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| **Core Client** | | | |
| start/connect | `__aenter__` | `start_link` | Match |
| stop/disconnect | `__aexit__` | `stop` | Match |
| send_message | `query()` | `send_message` | Match |
| receive_messages | `receive_messages()` | `stream_messages` | Match |
| receive_response | `receive_response()` | `receive_response` | Match |
| interrupt | `interrupt()` | `interrupt` | Match |
| set_model | `set_model()` | `set_model` | Match |
| set_permission_mode | `set_permission_mode()` | `set_permission_mode` | Match |
| rewind_files | `rewind_files()` | `rewind_files` | Match |
| set_agent | N/A | `set_agent` | Elixir Extra |
| get_agent | N/A | `get_agent` | Elixir Extra |
| **Session Management** | | | |
| resume | query-level only | `resume/3` | Elixir Extra |
| continue | N/A | `continue/2` | Elixir Extra |
| fork_session | option only | option only | Match |
| **Streaming** | | | |
| Partial messages | basic | accumulated text | Elixir Better |
| Text delta | manual | automatic | Elixir Better |
| **Error Handling** | | | |
| Base exception | `ClaudeSDKError` | modules only | Gap: P1-001 |
| Error hierarchy | inheritance | flat | Gap: P1-001 |
| **MCP** | | | |
| SDK servers | `@tool` decorator | `deftool` macro | Match |
| Stdio servers | Yes | Yes | Match |
| SSE servers | Yes | No | Gap: P2-005 |
| HTTP servers | Yes | No | Gap: P2-005 |
| Simple schema | type mapping | needs helper | Gap: P1-002 |
| **Hooks** | | | |
| All 6 events | Yes | Yes | Match |
| Output helpers | manual dict | helper functions | Elixir Better |
| Async helper | TypedDict | needs helper | Gap: P1-004 |
| Input types | discriminated | consolidated map | Gap: P2-002 |
| **Control Protocol** | | | |
| All subtypes | Yes | Yes | Match |
| Cancel requests | TODO | Full | Elixir Better |
| AbortSignal | placeholder | Full | Elixir Better |
| Timeouts | fixed 60s | configurable | Elixir Better |
| **Transport** | | | |
| Single impl | SubprocessCLI | Port + Erlexec | Elixir Better |
| User execution | N/A | erlexec | Elixir Extra |

---

## Testing Requirements

### Unit Tests Required

1. **Error handling tests** (`test/claude_agent_sdk/errors_test.exs`)
   - `sdk_error?/1` function
   - `category/1` function
   - Guard macro

2. **Simple schema tests** (`test/claude_agent_sdk/tool_test.exs`)
   - Map syntax support
   - Module type conversion
   - All primitive types

3. **Async hook tests** (`test/claude_agent_sdk/hooks/output_test.exs`)
   - `async/1` helper
   - `with_async_timeout/2` helper
   - Serialization to CLI format

4. **First result event tests** (`test/claude_agent_sdk/query/cli_stream_test.exs`)
   - Timeout behavior
   - Control feature detection
   - Environment variable handling

### Integration Tests Required

1. **MCP with SDK servers and hooks**
   - Verify stdin closure timing
   - Test with both features enabled

2. **Error propagation**
   - All error types through stack

---

## Migration Guide

### From v0.7.3 to v0.8.0 (After Implementation)

No breaking changes expected. All gaps are additive features.

### New Features Available

```elixir
# After P1-001: Unified error catching
import ClaudeAgentSDK.Errors.Guards
rescue e when is_sdk_error(e) -> handle(e)

# After P1-002: Simple schema syntax
deftool :calc, "Calculate", Tool.simple_schema(%{a: :float, b: :float})

# After P1-004: Async hooks
Output.allow() |> Output.async() |> Output.with_async_timeout(30_000)

# After P2-003: Updated input
Output.allow() |> Output.with_updated_input(%{"sanitized" => true})
```

---

## Implementation Checklist

### Phase 1: P1 Gaps (High Priority)

- [ ] P1-001: Base error hierarchy
  - [ ] Add `Errors` base module
  - [ ] Add `sdk_error?/1` function
  - [ ] Add guard macro
  - [ ] Write tests
  - [ ] Update documentation

- [ ] P1-002: Simple schema conversion
  - [ ] Add map syntax to `simple_schema/1`
  - [ ] Add type conversion functions
  - [ ] Write tests
  - [ ] Update tool documentation

- [ ] P1-003: First result event pattern
  - [ ] Add timeout configuration
  - [ ] Implement wait logic in CLIStream
  - [ ] Add control feature detection
  - [ ] Write integration tests

- [ ] P1-004: Output.async/1 helper
  - [ ] Add `async/1` function
  - [ ] Add `with_async_timeout/2` function
  - [ ] Update serialization
  - [ ] Write tests and documentation

### Phase 2: P2 Gaps (Medium Priority)

- [ ] P2-001: Timeout documentation
- [ ] P2-002: Discriminated union input types
- [ ] P2-003: with_updated_input/2 helper
- [ ] P2-004: end_input/1 in Transport behaviour
- [ ] P2-005: MCP SSE/HTTP server types

### Phase 3: P3 Gaps (Low Priority)

- [ ] P3-001: Protocol version negotiation
- [ ] P3-002: Telemetry integration
- [ ] P3-003: Architecture documentation

---

## Appendix: File References

### Python SDK Files
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/__init__.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/client.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_errors.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py`

### Elixir SDK Files
- `lib/claude_agent_sdk.ex`
- `lib/claude_agent_sdk/client.ex`
- `lib/claude_agent_sdk/options.ex`
- `lib/claude_agent_sdk/tool.ex`
- `lib/claude_agent_sdk/errors.ex`
- `lib/claude_agent_sdk/hooks/output.ex`
- `lib/claude_agent_sdk/hooks/hooks.ex`
- `lib/claude_agent_sdk/query/cli_stream.ex`
- `lib/claude_agent_sdk/control_protocol/protocol.ex`
- `lib/claude_agent_sdk/transport.ex`

---

*Document generated by comprehensive gap analysis using parallel research agents.*
