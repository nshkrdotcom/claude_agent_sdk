# Python → Elixir Parity Audit: Error Handling Gaps

---

Gap: Structured error types (connection, not-found, process exit, JSON decode, message parse)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_errors.py:6-55`

Python Code:
```py
class CLIConnectionError(ClaudeSDKError): ...
class CLINotFoundError(CLIConnectionError): ...
class ProcessError(ClaudeSDKError):
    def __init__(self, message: str, exit_code: int | None = None, stderr: str | None = None):
        self.exit_code = exit_code
        self.stderr = stderr
...
class CLIJSONDecodeError(ClaudeSDKError):
    def __init__(self, line: str, original_error: Exception):
        self.line = line
        self.original_error = original_error
...
class MessageParseError(ClaudeSDKError):
    def __init__(self, message: str, data: dict[str, Any] | None = None):
        self.data = data
```

Elixir Status: Not implemented (uses tuples/strings and embeds errors in `%Message{type: :result, ...}`)

Elixir Location: `lib/claude_agent_sdk/process.ex:548-573`, `lib/claude_agent_sdk/message.ex:105-120`, `lib/claude_agent_sdk/cli.ex:39-47`

Priority: Medium

Suggested Implementation:
Introduce a small set of consistent error structs (or tagged tuples) carrying structured metadata (exit code, stderr, failing line, raw message) so callers can programmatically react (e.g., distinguish missing CLI vs JSON corruption vs process exit).

Complexity: Moderate

---

Gap: JSON decode failures are raised (Python) vs silently treated as assistant text (Elixir)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:567-607` (buffered JSON decode loop + raising `CLIJSONDecodeError`)

Python Code:
```py
json_buffer += json_line
...
if len(json_buffer) > self._max_buffer_size:
    ...
    raise SDKJSONDecodeError(...)
try:
    data = json.loads(json_buffer)
    json_buffer = ""
    yield data
except json.JSONDecodeError:
    continue
```

Elixir Status: Different approach

Elixir Location: `lib/claude_agent_sdk/process.ex:488-517`, `lib/claude_agent_sdk/message.ex:105-120`

Priority: Medium

Suggested Implementation:
Consider returning an explicit decode error (with the offending line/buffer) instead of converting unknown/non-JSON output into an assistant message. This improves correctness for structured-output and control-protocol use cases.

Complexity: Moderate

---

Gap: CLI start errors include explicit `cwd`-missing vs `cli not found` distinction

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:433-443`

Python Code:
```py
except FileNotFoundError as e:
    if self._cwd and not Path(self._cwd).exists():
        raise CLIConnectionError(f"Working directory does not exist: {self._cwd}") from e
    raise CLINotFoundError(f"Claude Code not found at: {self._cli_path}") from e
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/transport/port.ex:264-270`, `lib/claude_agent_sdk/cli.ex:39-47`

Priority: Low

Suggested Implementation:
When CLI boot fails, standardize on a structured error that distinguishes “cwd missing” from “binary missing” from “process start failed”, matching Python’s categorization.

Complexity: Simple

