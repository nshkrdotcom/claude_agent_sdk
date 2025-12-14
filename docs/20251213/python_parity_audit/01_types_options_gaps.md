# Python → Elixir Parity Audit: Types & Options Gaps

---

Gap: `system_prompt` preset object support (`SystemPromptPreset`)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py:27-33`, `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py:621-622`

Python Code:
```py
class SystemPromptPreset(TypedDict):
    """System prompt preset configuration."""

    type: Literal["preset"]
    preset: Literal["claude_code"]
    append: NotRequired[str]

@dataclass
class ClaudeAgentOptions:
    system_prompt: str | SystemPromptPreset | None = None
```

Elixir Status: Not implemented

Elixir Location: `lib/claude_agent_sdk/options.ex:73-77`, `lib/claude_agent_sdk/options.ex:436-444`

Priority: High

Suggested Implementation:
Support `system_prompt` as either a string or preset map (e.g., `%{type: :preset, preset: :claude_code, append: "..."}`), mapping preset+append to CLI flags consistent with Python (`--append-system-prompt` for the append case).

Complexity: Moderate

---

Gap: Default “no system prompt” behavior (`--system-prompt ""` when unset)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:176-180`

Python Code:
```py
if self._options.system_prompt is None:
    cmd.extend(["--system-prompt", ""])
elif isinstance(self._options.system_prompt, str):
    cmd.extend(["--system-prompt", self._options.system_prompt])
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/options.ex:436-440`

Priority: Critical

Suggested Implementation:
Match Python’s explicit “empty system prompt” default when `system_prompt` is unset (and no preset is provided). This likely means emitting `--system-prompt ""` by default (or making the default `%Options{system_prompt: ""}` in the relevant transports).

Complexity: Simple

---

Gap: Settings isolation default (`--setting-sources ""` always emitted)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:287-293`

Python Code:
```py
sources_value = (
    ",".join(self._options.setting_sources)
    if self._options.setting_sources is not None
    else ""
)
cmd.extend(["--setting-sources", sources_value])
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/options.ex:561-567`

Priority: Critical

Suggested Implementation:
Emit `--setting-sources ""` even when `setting_sources` is `nil` so Elixir defaults to the same “load no filesystem settings unless explicitly requested” behavior as Python.

Complexity: Simple

---

Gap: Options-level `stderr` streaming callback

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py:646-647`, `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:394-423`, `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:449-463`

Python Code:
```py
stderr: Callable[[str], None] | None = None  # Callback for stderr output from CLI

should_pipe_stderr = (
    self._options.stderr is not None
    or "debug-to-stderr" in self._options.extra_args
)

async for line in self._stderr_stream:
    if self._options.stderr:
        self._options.stderr(line_str)
```

Elixir Status: Not implemented

Elixir Location: N/A (no Options field; no transport-side callback)

Priority: Medium

Suggested Implementation:
Add an `Options` field (e.g., `stderr: (String.t() -> any()) | nil`) and, in the streaming transport, route CLI stderr lines to that callback when requested.

Complexity: Moderate

---

Gap: Async hook deferral output type (`async`/`asyncTimeout`)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py:286-299`

Python Code:
```py
class AsyncHookJSONOutput(TypedDict):
    async_: Literal[True]
    asyncTimeout: NotRequired[int]
```

Elixir Status: Not implemented

Elixir Location: `lib/claude_agent_sdk/hooks/output.ex:53-120` (no async deferral fields)

Priority: Medium

Suggested Implementation:
Extend hook output typing/validation to support `async` deferral (`%{async: true, asyncTimeout: 60000}`) and ensure the control protocol encoder forwards those fields to the CLI.

Complexity: Moderate

