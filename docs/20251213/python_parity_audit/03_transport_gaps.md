# Python → Elixir Parity Audit: Transport & Subprocess Gaps

---

Gap: Bundled CLI discovery (`_bundled/claude[.exe]`) and expanded search paths

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:70-116`

Python Code:
```py
def _find_cli(self) -> str:
    # First, check for bundled CLI
    bundled_cli = self._find_bundled_cli()
    if bundled_cli:
        return bundled_cli
    ...
    locations = [
        Path.home() / ".npm-global/bin/claude",
        Path("/usr/local/bin/claude"),
        Path.home() / ".local/bin/claude",
        Path.home() / "node_modules/.bin/claude",
        Path.home() / ".yarn/bin/claude",
        Path.home() / ".claude/local/claude",
    ]

def _find_bundled_cli(self) -> str | None:
    cli_name = "claude.exe" if platform.system() == "Windows" else "claude"
    bundled_path = Path(__file__).parent.parent.parent / "_bundled" / cli_name
    if bundled_path.exists() and bundled_path.is_file():
        return str(bundled_path)
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/cli.ex:12-33`

Priority: High

Suggested Implementation:
Extend `ClaudeAgentSDK.CLI` discovery to match Python’s behavior (bundled CLI, `~/.claude/local/claude`, common Node locations), and ensure the SDK can prefer a bundled CLI when present.

Complexity: Moderate

---

Gap: Minimum Claude Code version check parity (`>= 2.0.0`) + skip knob

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:32-33`, `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:374-376`

Python Code:
```py
MINIMUM_CLAUDE_CODE_VERSION = "2.0.0"
...
if not os.environ.get("CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK"):
    await self._check_claude_version()
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/cli.ex:12-119` (minimum is `1.0.0`, and the checker isn’t obviously enforced by transports)

Priority: Medium

Suggested Implementation:
Update the minimum version to match Python and enforce (or at least warn) during CLI boot for both `Process` and streaming transports; add an opt-out env var consistent with Python (`CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK`).

Complexity: Moderate

---

Gap: Non-existent `cwd` handling (Python errors; Elixir creates directories)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:433-440`

Python Code:
```py
except FileNotFoundError as e:
    if self._cwd and not Path(self._cwd).exists():
        error = CLIConnectionError(
            f"Working directory does not exist: {self._cwd}"
        )
        raise error from e
```

Elixir Status: Different approach

Elixir Location: `lib/claude_agent_sdk/transport/port.ex:264-270`

Priority: High

Suggested Implementation:
Align with Python by rejecting a non-existent `cwd` rather than creating it implicitly (at minimum for the streaming transport).

Complexity: Simple

---

Gap: `PWD` env var set when `cwd` is specified

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:391-393`

Python Code:
```py
if self._cwd:
    process_env["PWD"] = self._cwd
```

Elixir Status: Not implemented

Elixir Location: N/A (env builders don’t set `PWD`)

Priority: Low

Suggested Implementation:
When `Options.cwd` is set, add `PWD` to the child environment to mirror Python. (This can matter when downstream tooling assumes `PWD` is accurate even if `cd` is set.)

Complexity: Simple

---

Gap: Agent JSON size mitigation on Windows (`--agents @tempfile`)

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:34-37`, `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:336-367`

Python Code:
```py
_CMD_LENGTH_LIMIT = 8000 if platform.system() == "Windows" else 100000
...
if len(cmd_str) > _CMD_LENGTH_LIMIT and self._options.agents:
    agents_idx = cmd.index("--agents")
    ...
    cmd[agents_idx + 1] = f"@{temp_file.name}"
```

Elixir Status: Not implemented

Elixir Location: `lib/claude_agent_sdk/options.ex:330-336` (always inlines agents JSON)

Priority: Medium

Suggested Implementation:
When `--agents` payload is large (or on Windows), write agents JSON to a temp file and pass `--agents @/path/to/file.json`, matching Python.

Complexity: Moderate

---

Gap: OS-level `user` execution (setuid) in streaming transport

Python Location: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:403-411`

Python Code:
```py
self._process = await anyio.open_process(
    cmd,
    ...
    env=process_env,
    user=self._options.user,
)
```

Elixir Status: Partial

Elixir Location: `lib/claude_agent_sdk/process.ex:132-136` (supports `:user` via erlexec), `lib/claude_agent_sdk/transport/port.ex:334-338` (only sets `USER`/`LOGNAME` env)

Priority: Medium

Suggested Implementation:
If true setuid is desired for parity, implement `user` for the Port-based transport (may require switching streaming transport to erlexec or another mechanism that supports setuid).

Complexity: Complex

