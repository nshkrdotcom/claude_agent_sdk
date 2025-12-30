# Error Handling Comparison: Python vs Elixir Claude Agent SDK

## Overview

Both SDKs implement structured error handling for CLI connection, process management, and message parsing. This document compares exception hierarchies, error codes, timeout handling, and validation approaches.

## Parity Status

| Feature | Python SDK | Elixir SDK | Parity |
|---------|------------|------------|--------|
| Exception Hierarchy | Yes | Yes | Full |
| CLIConnectionError | Yes | Yes | Full |
| CLINotFoundError | Yes | Yes | Full |
| ProcessError | Yes | Yes | Full |
| CLIJSONDecodeError | Yes | Yes | Full |
| MessageParseError | Yes | Yes | Full |
| AssistantError | No | Yes | Elixir-only |
| Timeout Handling | anyio-based | Process-based | Different approach |
| Validation | Runtime | Compile + Runtime | Different approach |

## Exception Hierarchies

### Python Hierarchy

```python
# _errors.py
class ClaudeSDKError(Exception):
    """Base exception for all Claude SDK errors."""

class CLIConnectionError(ClaudeSDKError):
    """Raised when unable to connect to Claude Code."""

class CLINotFoundError(CLIConnectionError):
    """Raised when Claude Code is not found or not installed."""

    def __init__(
        self, message: str = "Claude Code not found", cli_path: str | None = None
    ):
        if cli_path:
            message = f"{message}: {cli_path}"
        super().__init__(message)

class ProcessError(ClaudeSDKError):
    """Raised when the CLI process fails."""

    def __init__(
        self, message: str, exit_code: int | None = None, stderr: str | None = None
    ):
        self.exit_code = exit_code
        self.stderr = stderr
        # Build detailed message
        super().__init__(message)

class CLIJSONDecodeError(ClaudeSDKError):
    """Raised when unable to decode JSON from CLI output."""

    def __init__(self, line: str, original_error: Exception):
        self.line = line
        self.original_error = original_error
        super().__init__(f"Failed to decode JSON: {line[:100]}...")

class MessageParseError(ClaudeSDKError):
    """Raised when unable to parse a message from CLI output."""

    def __init__(self, message: str, data: dict[str, Any] | None = None):
        self.data = data
        super().__init__(message)
```

### Elixir Exception Modules

```elixir
# errors.ex
defmodule ClaudeAgentSDK.Errors do
  @moduledoc """
  Structured error types for programmatic handling.
  """
end

defmodule ClaudeAgentSDK.Errors.CLIConnectionError do
  @enforce_keys [:message]
  defexception [:message, :cwd, :reason]

  @type t :: %__MODULE__{
    message: String.t(),
    cwd: String.t() | nil,
    reason: term()
  }
end

defmodule ClaudeAgentSDK.Errors.CLINotFoundError do
  @enforce_keys [:message]
  defexception [:message, :cli_path]

  @type t :: %__MODULE__{
    message: String.t(),
    cli_path: String.t() | nil
  }
end

defmodule ClaudeAgentSDK.Errors.ProcessError do
  @enforce_keys [:message]
  defexception [:message, :exit_code, :stderr]

  @type t :: %__MODULE__{
    message: String.t(),
    exit_code: integer() | nil,
    stderr: String.t() | nil
  }
end

defmodule ClaudeAgentSDK.Errors.CLIJSONDecodeError do
  @enforce_keys [:message, :line]
  defexception [:message, :line, :original_error]

  @type t :: %__MODULE__{
    message: String.t(),
    line: String.t(),
    original_error: term()
  }
end

defmodule ClaudeAgentSDK.Errors.MessageParseError do
  @enforce_keys [:message]
  defexception [:message, :data]

  @type t :: %__MODULE__{
    message: String.t(),
    data: map() | nil
  }
end
```

### Elixir-Only: AssistantError

```elixir
# assistant_error.ex
defmodule ClaudeAgentSDK.AssistantError do
  @moduledoc """
  Represents errors returned by the Claude assistant in message responses.
  """

  @type error_type ::
    :authentication_failed
    | :billing_error
    | :rate_limit
    | :invalid_request
    | :server_error
    | :unknown

  @type t :: %__MODULE__{
    type: error_type(),
    message: String.t() | nil
  }

  defstruct [:type, :message]

  @spec cast(map() | nil) :: t() | nil
  def cast(nil), do: nil
  def cast(%{"type" => type} = error) do
    %__MODULE__{
      type: String.to_existing_atom(type),
      message: error["message"]
    }
  end
end
```

## Error Codes

### Python Assistant Message Errors

```python
# types.py
AssistantMessageError = Literal[
    "authentication_failed",
    "billing_error",
    "rate_limit",
    "invalid_request",
    "server_error",
    "unknown",
]
```

### Elixir Error Types

```elixir
# assistant_error.ex
@type error_type ::
  :authentication_failed
  | :billing_error
  | :rate_limit
  | :invalid_request
  | :server_error
  | :unknown
```

### JSONRPC Error Codes (Both SDKs)

| Code | Meaning | Usage |
|------|---------|-------|
| -32601 | Method not found | Unknown MCP method |
| -32603 | Internal error | Tool execution failed |

## Timeout Handling

### Python: anyio-based

```python
# query.py
async def _send_control_request(
    self, request: dict, timeout: float = 60.0
) -> dict:
    try:
        with anyio.fail_after(timeout):
            await event.wait()
    except TimeoutError as e:
        self.pending_control_responses.pop(request_id, None)
        raise Exception(f"Control request timeout: {request.get('subtype')}") from e

# Initialize timeout (configurable via env)
self._initialize_timeout = initialize_timeout  # Default 60.0

# Stream close timeout
self._stream_close_timeout = (
    float(os.environ.get("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT", "60000")) / 1000.0
)
```

### Elixir: Process.send_after

```elixir
# client.ex
@default_init_timeout_ms 60_000
@default_control_request_timeout_ms 60_000
@init_timeout_env_var "CLAUDE_CODE_STREAM_CLOSE_TIMEOUT"

defp schedule_control_request_timeout(request_id) when is_binary(request_id) do
  Process.send_after(
    self(),
    {:control_request_timeout, request_id},
    control_request_timeout_ms()
  )
end

def handle_info({:control_request_timeout, request_id}, state) do
  {pending_entry, pending_requests} = Map.pop(state.pending_requests, request_id)
  state = %{state | pending_requests: pending_requests}

  case pending_entry do
    {:set_model, from, _requested_model, _timer_ref} ->
      GenServer.reply(from, {:error, :timeout})
      {:noreply, %{state | pending_model_change: nil}}
    # ... other cases
  end
end

# Initialize timeout from env
def init_timeout_seconds_from_env do
  env_value = System.get_env(@init_timeout_env_var)

  parsed_ms = case env_value do
    value when is_binary(value) ->
      case Integer.parse(value) do
        {int, _} when int > 0 -> int
        _ -> @default_init_timeout_ms
      end
    _ -> @default_init_timeout_ms
  end

  max(parsed_ms, @default_init_timeout_ms) / 1_000
end
```

### Timeout Comparison

| Aspect | Python | Elixir |
|--------|--------|--------|
| Mechanism | `anyio.fail_after` context | `Process.send_after` + handle_info |
| Cancellation | Automatic on context exit | Manual `Process.cancel_timer` |
| Error Type | `TimeoutError` exception | `{:error, :timeout}` tuple |
| Init Timeout | 60s default | 60s default (env configurable) |
| Request Timeout | 60s default | 60s default (app config) |

## Validation Approaches

### Python: Runtime Type Hints

```python
# types.py - uses dataclasses and type hints
@dataclass
class ClaudeAgentOptions:
    tools: list[str] | ToolsPreset | None = None
    allowed_tools: list[str] = field(default_factory=list)
    system_prompt: str | SystemPromptPreset | None = None
    # ... many more fields

# Runtime validation in client
if options.can_use_tool:
    if isinstance(prompt, str):
        raise ValueError(
            "can_use_tool callback requires streaming mode. "
            "Please provide prompt as an AsyncIterable instead of a string."
        )

    if options.permission_prompt_tool_name:
        raise ValueError(
            "can_use_tool callback cannot be used with permission_prompt_tool_name. "
            "Please use one or the other."
        )
```

### Elixir: Compile-Time + Runtime

```elixir
# options.ex - uses defstruct with types
defmodule ClaudeAgentSDK.Options do
  @type t :: %__MODULE__{
    model: String.t() | nil,
    system_prompt: String.t() | nil,
    max_turns: pos_integer() | nil,
    allowed_tools: [String.t()],
    disallowed_tools: [String.t()],
    # ...
  }

  defstruct [
    model: nil,
    system_prompt: nil,
    max_turns: nil,
    allowed_tools: [],
    disallowed_tools: [],
    # ...
  ]
end

# Runtime validation in Client.init
defp validate_hooks(nil), do: :ok
defp validate_hooks(hooks), do: Hooks.validate_config(hooks)

defp validate_permission_callback(nil), do: :ok
defp validate_permission_callback(callback) do
  ClaudeAgentSDK.Permission.validate_callback(callback)
end

# Model validation
defmodule ClaudeAgentSDK.Model do
  @spec validate(String.t()) :: {:ok, String.t()} | {:error, :invalid_model}
  def validate(model) do
    # Check against known model patterns
  end

  @spec suggest(String.t()) :: [String.t()]
  def suggest(invalid_model) do
    # Return similar valid model names
  end
end
```

### Validation Comparison

| Aspect | Python | Elixir |
|--------|--------|--------|
| Type Checking | mypy (optional) | Dialyzer (optional) |
| Runtime Types | type hints | @type specs |
| Struct Validation | dataclass | defstruct + validate functions |
| Error Format | Raise ValueError | Return {:error, reason} |

## Error Handling Patterns

### Python: Exception-Based

```python
# Raising errors
raise CLINotFoundError(
    "Claude Code not found. Install with:\n"
    "  npm install -g @anthropic-ai/claude-code"
)

raise ProcessError(
    f"Command failed with exit code {returncode}",
    exit_code=returncode,
    stderr="Check stderr output for details",
)

# Catching errors
try:
    async for message in query(prompt="Hello"):
        print(message)
except CLINotFoundError:
    print("Please install Claude Code CLI")
except ProcessError as e:
    print(f"Process failed: {e.exit_code}")
except CLIJSONDecodeError as e:
    print(f"Invalid JSON: {e.line}")
```

### Elixir: Tagged Tuples

```elixir
# Returning errors
{:error, %CLINotFoundError{
  message: "Claude Code not found",
  cli_path: "/usr/local/bin/claude"
}}

{:error, %ProcessError{
  message: "Command failed",
  exit_code: 1,
  stderr: "Error output"
}}

# Pattern matching on errors
case ClaudeAgentSDK.query("Hello") do
  {:ok, response} ->
    IO.inspect(response)

  {:error, %CLINotFoundError{}} ->
    IO.puts("Please install Claude Code CLI")

  {:error, %ProcessError{exit_code: code}} ->
    IO.puts("Process failed with code: #{code}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

# With exceptions (when needed)
try do
  result = ClaudeAgentSDK.query!("Hello")
rescue
  e in [CLINotFoundError, ProcessError] ->
    IO.puts("CLI error: #{Exception.message(e)}")
end
```

## Error Context

### Python: Error Attributes

```python
class ProcessError(ClaudeSDKError):
    def __init__(
        self, message: str, exit_code: int | None = None, stderr: str | None = None
    ):
        self.exit_code = exit_code
        self.stderr = stderr

        if exit_code is not None:
            message = f"{message} (exit code: {exit_code})"
        if stderr:
            message = f"{message}\nError output: {stderr}"

        super().__init__(message)
```

### Elixir: Struct Fields

```elixir
defmodule ClaudeAgentSDK.Errors.ProcessError do
  defexception [:message, :exit_code, :stderr]

  # Access via struct fields
  # error.exit_code
  # error.stderr
end

# Exception.message/1 returns the message field
# Logger includes struct inspection for context
Logger.error("Process failed",
  exit_code: error.exit_code,
  stderr: error.stderr
)
```

## Logging Differences

### Python

```python
import logging
logger = logging.getLogger(__name__)

logger.warning(
    f"Warning: Claude Code version {version} is unsupported. "
    f"Minimum required: {MINIMUM_CLAUDE_CODE_VERSION}."
)

logger.error(f"Fatal error in message reader: {e}")
```

### Elixir

```elixir
require Logger

Logger.warning("Failed to decode message: #{inspect(reason)}")

Logger.error("Hook callback failed",
  request_id: request_id,
  reason: reason
)

# Structured logging with metadata
Logger.info("Model changed successfully",
  request_id: request_id,
  model: model
)
```

## Hook Error Handling

### Python

```python
# Timeout formatting
def hook_timeout_error_message(timeout_ms):
    return f"Hook callback timeout after {format_timeout(timeout_ms)}"

# Hook callback execution
try:
    result = await callback(input, tool_use_id, context)
except Exception as e:
    return {"error": str(e)}
```

### Elixir

```elixir
# Timeout formatting
defp hook_timeout_error_message(timeout_ms) do
  "Hook callback timeout after #{format_timeout_ms(timeout_ms)}"
end

defp format_timeout_ms(timeout_ms) when is_integer(timeout_ms) do
  cond do
    timeout_ms >= 1_000 and rem(timeout_ms, 1_000) == 0 ->
      "#{div(timeout_ms, 1_000)}s"
    timeout_ms >= 1_000 ->
      "#{Float.round(timeout_ms / 1_000, 1)}s"
    true ->
      "#{timeout_ms}ms"
  end
end

# Hook callback execution
defp execute_hook_callback(callback_fn, input, tool_use_id, signal, timeout_ms) do
  task = Task.async(fn ->
    try do
      result = callback_fn.(input, tool_use_id, %{signal: signal})
      {:ok, Output.to_json_map(result)}
    rescue
      e -> {:error, "Hook exception: #{Exception.message(e)}"}
    end
  end)

  case Task.yield(task, timeout_ms) do
    {:ok, result} -> result
    nil ->
      Task.shutdown(task, :brutal_kill)
      {:error, hook_timeout_error_message(timeout_ms)}
  end
end
```

## Differences Summary

| Aspect | Python | Elixir |
|--------|--------|--------|
| Base Class | `ClaudeSDKError` | No common base (defexception) |
| Hierarchy Depth | 2 levels | 1 level (flat) |
| Error Return | Raise exception | `{:error, reason}` tuple |
| Timeout Mechanism | anyio context manager | Process messages |
| Validation Style | Runtime ValueError | Compile specs + runtime |
| Logging | Standard logging | Elixir Logger with metadata |
| Assistant Errors | In Message dataclass | Separate AssistantError module |

## Recommendations

1. **Python**: Consider adding AssistantError class for parity with Elixir
2. **Elixir**: Consider adding a common base exception type
3. **Both**: Standardize timeout environment variable names
4. **Both**: Add error code constants for common failures
5. **Both**: Document error handling best practices with examples
