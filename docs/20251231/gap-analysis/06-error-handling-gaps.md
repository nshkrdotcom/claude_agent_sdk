# Error Handling Gap Analysis: Python SDK vs Elixir Port

**Date:** 2025-12-31
**Focus Area:** Error Handling
**Python SDK Version:** claude-agent-sdk-python (current main)
**Elixir Port Version:** claude_agent_sdk (current main)

---

## Executive Summary

The Elixir port demonstrates **strong parity** with the Python SDK's error handling model. All core error types have been faithfully implemented as exception structs with matching fields. The `AssistantMessageError` types are fully covered. Control protocol error handling is comprehensive, including proper timeout handling, cancellation, and error response encoding.

**Key Findings:**
- All 5 core error types implemented with matching fields
- All 6 `AssistantMessageError` types implemented with casting utilities
- Control protocol error handling includes timeout management for all request types
- Process exit and JSON parsing errors are handled equivalently
- Version check warnings implemented with equivalent thresholds

**Gaps Identified:**
- Missing base `ClaudeSDKError` parent type for error hierarchy
- Elixir errors lack inheritance relationship (uses separate modules instead)
- No explicit `CLIConnectionError` hierarchy to `CLINotFoundError`

---

## Error Type Comparison

### Core Error Types

| Python Error Type | Elixir Error Type | Parity | Notes |
|-------------------|-------------------|--------|-------|
| `ClaudeSDKError` | (none) | **MISSING** | Base exception class not implemented |
| `CLIConnectionError` | `Errors.CLIConnectionError` | **FULL** | Fields: message, cwd, reason |
| `CLINotFoundError` | `Errors.CLINotFoundError` | **FULL** | Fields: message, cli_path |
| `ProcessError` | `Errors.ProcessError` | **FULL** | Fields: message, exit_code, stderr |
| `CLIJSONDecodeError` | `Errors.CLIJSONDecodeError` | **FULL** | Fields: message, line, original_error |
| `MessageParseError` | `Errors.MessageParseError` | **FULL** | Fields: message, data |

### Error Field Comparison

#### CLIConnectionError

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| `message` | Yes | Yes | Required in both |
| `cwd` | Implicit in message | Yes | Explicit field in Elixir |
| `reason` | N/A | Yes | Additional context in Elixir |

#### CLINotFoundError

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| `message` | Yes | Yes | Required in both |
| `cli_path` | Yes (optional) | Yes | Optional path that was searched |

#### ProcessError

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| `message` | Yes | Yes | Required in both |
| `exit_code` | Yes (optional) | Yes | Process exit code |
| `stderr` | Yes (optional) | Yes | Captured stderr output |

#### CLIJSONDecodeError

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| `message` | Yes | Yes | Human-readable description |
| `line` | Yes | Yes | Raw line that failed to parse |
| `original_error` | Yes | Yes | Underlying JSON decode error |

#### MessageParseError

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| `message` | Yes | Yes | Human-readable description |
| `data` | Yes (optional) | Yes | Raw message data |

---

## AssistantMessageError Types

Both implementations define identical error type literals/atoms:

| Error Type | Python | Elixir | Description |
|------------|--------|--------|-------------|
| `authentication_failed` | Yes | Yes | API key invalid or missing |
| `billing_error` | Yes | Yes | Billing/payment issue |
| `rate_limit` | Yes | Yes | Rate limit exceeded |
| `invalid_request` | Yes | Yes | Invalid request parameters |
| `server_error` | Yes | Yes | Anthropic server error |
| `unknown` | Yes | Yes | Unrecognized error type |

**Elixir Implementation Advantages:**
- `AssistantError.cast/1` function for safe string/atom conversion
- `AssistantError.values/0` returns list of valid error codes
- Pattern matching on atoms vs string literals

**Python Implementation:**
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

**Elixir Implementation:**
```elixir
# assistant_error.ex
@type t ::
        :authentication_failed
        | :billing_error
        | :rate_limit
        | :invalid_request
        | :server_error
        | :unknown

@spec cast(String.t() | atom() | nil) :: t() | nil
def cast(error) when is_binary(error) do
  # String pattern matching with fallback to :unknown
end
```

---

## Control Protocol Error Handling

### Error Response Encoding

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Success response encoding | Yes | Yes | `Protocol.encode_hook_response/3` |
| Error response encoding | Yes | Yes | `Protocol.encode_hook_response/3` with :error |
| Error control response | Yes | Yes | `ControlErrorResponse` TypedDict / JSON encoding |

### Error Response Structure

**Python (types.py):**
```python
class ControlErrorResponse(TypedDict):
    subtype: Literal["error"]
    request_id: str
    error: str
```

**Elixir (protocol.ex):**
```elixir
def encode_hook_response(request_id, error_message, :error) when is_binary(error_message) do
  response = %{
    "type" => "control_response",
    "response" => %{
      "subtype" => "error",
      "request_id" => request_id,
      "error" => error_message
    }
  }
  Jason.encode!(response)
end
```

### Timeout Handling

| Request Type | Python Timeout | Elixir Timeout | Notes |
|--------------|----------------|----------------|-------|
| Initialize | 60s (env configurable) | 60s (env configurable) | `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` |
| Control request | 60s default | 60s default | Configurable via application env |
| Hook callback | 60s default | 60s default per matcher | Matcher-level timeout support |

**Elixir Additional Features:**
- Per-request timeout tracking with `Process.send_after/3`
- `schedule_control_request_timeout/1` for all control requests
- `cancel_control_request_timeout/1` on successful response
- `fail_pending_control_requests/2` on transport exit

---

## Process Exit Error Handling

### Python Implementation (subprocess_cli.py)

```python
# Lines 616-628
try:
    returncode = await self._process.wait()
except Exception:
    returncode = -1

if returncode is not None and returncode != 0:
    self._exit_error = ProcessError(
        f"Command failed with exit code {returncode}",
        exit_code=returncode,
        stderr="Check stderr output for details",
    )
    raise self._exit_error
```

### Elixir Implementation (transport/port.ex)

```elixir
# Lines 191-209
def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
  new_state =
    state
    |> broadcast_exit(status)
    |> Map.put(:status, :disconnected)
    |> Map.put(:port, nil)

  {:noreply, new_state}
end

def handle_info({:EXIT, port, reason}, %{port: port} = state) do
  new_state =
    state
    |> broadcast_exit(reason)
    |> Map.put(:status, :disconnected)
    |> Map.put(:port, nil)

  {:noreply, new_state}
end
```

### Comparison

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Exit code capture | Yes | Yes | Via `:exit_status` message |
| Process termination detection | Yes | Yes | Via `{:EXIT, port, reason}` |
| Broadcast to subscribers | N/A | Yes | Elixir broadcasts to all subscribers |
| Error stored for later | Yes (`_exit_error`) | No | Elixir uses message passing instead |

---

## JSON Parsing Error Handling

### Buffer Overflow Protection

Both implementations protect against malicious/oversized JSON:

**Python (subprocess_cli.py):**
```python
if len(json_buffer) > self._max_buffer_size:
    buffer_length = len(json_buffer)
    json_buffer = ""
    raise SDKJSONDecodeError(
        f"JSON message exceeded maximum buffer size of {self._max_buffer_size} bytes",
        ValueError(f"Buffer size {buffer_length} exceeds limit {self._max_buffer_size}")
    )
```

**Elixir (transport/port.ex):**
```elixir
defp handle_buffer_overflow(state, data) do
  error =
    %ClaudeAgentSDK.Errors.CLIJSONDecodeError{
      message: "JSON message exceeded maximum buffer size of #{state.max_buffer_size} bytes",
      line: truncate_line(data),
      original_error: {:buffer_overflow, byte_size(data), state.max_buffer_size}
    }

  Enum.each(state.subscribers, fn {pid, _ref} ->
    Kernel.send(pid, {:transport_error, error})
  end)

  %{state | buffer: "", overflowed?: true}
end
```

### Comparison

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Default buffer size | 1MB | 1MB | Identical |
| Configurable | Yes (`max_buffer_size` option) | Yes (`max_buffer_size` option) | Matching |
| Line truncation | Yes (100 chars) | Yes (100 chars) | Identical |
| Recovery after overflow | Yes (clears buffer) | Yes (sets `overflowed?` flag) | Equivalent |

---

## Version Check Warnings

### Python Implementation (subprocess_cli.py)

```python
MINIMUM_CLAUDE_CODE_VERSION = "2.0.0"

async def _check_claude_version(self) -> None:
    # ...
    if version_parts < min_parts:
        warning = (
            f"Warning: Claude Code version {version} is unsupported in the Agent SDK. "
            f"Minimum required version is {MINIMUM_CLAUDE_CODE_VERSION}. "
            "Some features may not work correctly."
        )
        logger.warning(warning)
        print(warning, file=sys.stderr)
```

### Elixir Implementation (cli.ex)

```elixir
@minimum_version "2.0.0"
@recommended_version "2.0.75"

@spec warn_if_outdated() :: :ok
def warn_if_outdated do
  if System.get_env(@skip_version_check_env) do
    :ok
  else
    do_warn_if_outdated()
  end
end

defp warn_for_installed_version(installed) do
  case {Version.parse(installed), Version.parse(@minimum_version)} do
    {{:ok, installed_version}, {:ok, minimum_version}} ->
      if Version.compare(installed_version, minimum_version) == :lt do
        Logger.warning(
          "Claude CLI version #{installed} is below minimum #{@minimum_version}. Please upgrade."
        )
      end
    # ...
  end
end
```

### Comparison

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Minimum version | 2.0.0 | 2.0.0 | Identical |
| Skip env var | `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK` | `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK` | Identical |
| Logging | Logger + stderr | Logger only | Minor difference |
| Version parsing | Regex + manual split | `Version.parse/1` | Elixir uses standard library |
| Recommended version | N/A | 2.0.75 | Elixir adds recommended version |

---

## Missing Error Types/Fields

### Missing Base Error Type

**Gap:** Python has `ClaudeSDKError` as a base class for all SDK errors, enabling unified exception handling:

```python
class ClaudeSDKError(Exception):
    """Base exception for all Claude SDK errors."""

class CLIConnectionError(ClaudeSDKError):
    """Raised when unable to connect to Claude Code."""

class CLINotFoundError(CLIConnectionError):
    """Raised when Claude Code is not found or not installed."""
```

**Elixir:** Each error is a separate module without inheritance relationship. This is idiomatic Elixir but loses the ability to catch all SDK errors with a single pattern.

### Inheritance Hierarchy

Python has `CLINotFoundError(CLIConnectionError(ClaudeSDKError))` inheritance, allowing:
```python
try:
    # ...
except CLIConnectionError:
    # Catches both CLIConnectionError and CLINotFoundError
```

Elixir requires explicit pattern matching on each type.

---

## Priority Recommendations

### High Priority

1. **Document error handling patterns** - Create a guide showing how to handle each error type in Elixir applications, compensating for the lack of inheritance.

2. **Add error type grouping helper** - Consider adding a helper module to group related errors:
   ```elixir
   defmodule ClaudeAgentSDK.Errors do
     @connection_errors [CLIConnectionError, CLINotFoundError]

     @spec connection_error?(term()) :: boolean()
     def connection_error?(%mod{}) when mod in @connection_errors, do: true
     def connection_error?(_), do: false
   end
   ```

### Medium Priority

3. **Add stderr to version warnings** - Python outputs version warnings to both Logger and stderr. Consider adding `:stderr` output for consistency.

4. **Enhance ProcessError with full stderr capture** - Currently the Elixir implementation broadcasts exit reason but doesn't always capture the full stderr. Consider enhancing to match Python's stderr capture.

### Low Priority

5. **Add base behavior** - Consider adding a behavior that all errors implement for consistent error handling:
   ```elixir
   defmodule ClaudeAgentSDK.Error do
     @callback message(t()) :: String.t()
     @callback to_map(t()) :: map()
   end
   ```

6. **Type derivation** - Implement `Jason.Encoder` for all error structs to enable easy serialization for logging/debugging.

---

## Implementation Status Summary

| Category | Python | Elixir | Parity |
|----------|--------|--------|--------|
| Core error types | 5 types | 5 types | **100%** |
| Error fields | All present | All present | **100%** |
| AssistantMessageError | 6 types | 6 types | **100%** |
| Control protocol errors | Full | Full | **100%** |
| Process exit handling | Yes | Yes | **100%** |
| JSON parsing errors | Yes | Yes | **100%** |
| Buffer overflow | Yes | Yes | **100%** |
| Version warnings | Yes | Yes | **95%** (minor logging diff) |
| Error hierarchy | Yes | No | **0%** (idiomatic difference) |

**Overall Parity:** ~95% functional parity, with differences being idiomatic (Elixir doesn't use class inheritance for errors)

---

## Appendix: File Reference

### Python SDK Files
- `/anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_errors.py` - Core error definitions
- `/anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py` - AssistantMessageError type
- `/anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py` - Transport error handling
- `/anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py` - Control protocol errors

### Elixir Port Files
- `/lib/claude_agent_sdk/errors.ex` - All error type definitions
- `/lib/claude_agent_sdk/assistant_error.ex` - AssistantMessageError types
- `/lib/claude_agent_sdk/transport/port.ex` - Port transport error handling
- `/lib/claude_agent_sdk/transport/erlexec.ex` - Erlexec transport error handling
- `/lib/claude_agent_sdk/control_protocol/protocol.ex` - Control protocol error encoding
- `/lib/claude_agent_sdk/cli.ex` - CLI discovery and version warnings
- `/lib/claude_agent_sdk/client.ex` - Client error handling and control protocol
- `/lib/claude_agent_sdk/query/cli_stream.ex` - CLI stream error handling
- `/lib/claude_agent_sdk/query/client_stream.ex` - Client stream error handling
