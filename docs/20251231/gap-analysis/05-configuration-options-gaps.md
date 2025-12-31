# Configuration and Options Gap Analysis

## Python Claude Agent SDK vs Elixir Port

**Analysis Date:** 2025-12-31
**Python SDK Version:** Latest (claude-agent-sdk-python)
**Elixir Port Version:** 0.7.2+

---

## Executive Summary

The Elixir port demonstrates **excellent parity** with the Python SDK's configuration options. All 38+ ClaudeAgentOptions fields are either:

1. **Fully implemented** with matching semantics
2. **Implemented with idiomatic Elixir enhancements** (e.g., atoms vs strings)
3. **Documented as intentional differences** for the Elixir ecosystem

Key findings:
- **Core options**: Full parity achieved
- **Session options**: Full parity achieved
- **Model options**: Full parity achieved
- **Sandbox options**: Full parity achieved via settings merge
- **Hooks/Permissions**: Full parity with timeout serialization matching Python
- **MCP servers**: Full parity with SDK and external server support

**Minor gaps identified**: 3 low-priority items (debug_stderr deprecation handling, cwd Path type coercion, disallowed_tools naming)

---

## Complete Option Field Comparison Table

### 1. Core Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `tools: list[str] \| ToolsPreset \| None` | `tools: tools_option()` | `--tools` | **MATCH** | Both support list, empty list (`""`), and preset map (`:claude_code` -> `"default"`) |
| `allowed_tools: list[str]` | `allowed_tools: [String.t()]` | `--allowedTools` | **MATCH** | Comma-separated list |
| `disallowed_tools: list[str]` | `disallowed_tools: [String.t()]` | `--disallowedTools` | **MATCH** | Comma-separated list |
| `system_prompt: str \| SystemPromptPreset \| None` | `system_prompt: String.t() \| map()` | `--system-prompt` | **MATCH** | Both emit `--system-prompt ""` when nil; preset with append uses `--append-system-prompt` |
| `mcp_servers: dict[str, McpServerConfig] \| str \| Path` | `mcp_servers: map() \| String.t()` | `--mcp-config` | **MATCH** | Both wrap in `{"mcpServers": ...}` for dict; strip `registry_pid`/`instance` from SDK servers |
| `permission_mode: PermissionMode \| None` | `permission_mode: permission_mode()` | `--permission-mode` | **MATCH** | Elixir uses atoms (`:accept_edits` -> `"acceptEdits"`) |

### 2. Session Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `continue_conversation: bool` | `continue_conversation: boolean()` | `--continue` | **MATCH** | Boolean flag |
| `resume: str \| None` | `resume: String.t()` | `--resume` | **MATCH** | Session ID to resume |
| `max_turns: int \| None` | `max_turns: integer()` | `--max-turns` | **MATCH** | Integer value |
| `max_budget_usd: float \| None` | `max_budget_usd: number()` | `--max-budget-usd` | **MATCH** | Float value |
| `fork_session: bool` | `fork_session: boolean()` | `--fork-session` | **MATCH** | Boolean flag |

### 3. Model Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `model: str \| None` | `model: String.t()` | `--model` | **MATCH** | Model name/alias |
| `fallback_model: str \| None` | `fallback_model: String.t()` | `--fallback-model` | **MATCH** | Fallback model |
| `betas: list[SdkBeta]` | `betas: [String.t()]` | `--betas` | **MATCH** | Comma-separated beta flags |

### 4. Directory/Path Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `cwd: str \| Path \| None` | `cwd: String.t()` | N/A (process cwd) | **MATCH** | Set via process environment |
| `cli_path: str \| Path \| None` | `path_to_claude_code_executable: String.t()` | N/A | **MATCH** | CLI executable override |
| `add_dirs: list[str \| Path]` | `add_dirs: [String.t()]` + `add_dir: [String.t()]` | `--add-dir` | **MATCH** | Elixir supports both singular and plural forms |
| `settings: str \| None` | `settings: String.t()` | `--settings` | **MATCH** | JSON string or file path; merged with sandbox |
| `setting_sources: list[SettingSource] \| None` | `setting_sources: [String.t() \| atom()]` | `--setting-sources` | **MATCH** | Both emit `--setting-sources ""` when nil (no filesystem settings) |

### 5. Environment Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `env: dict[str, str]` | `env: %{String.t() => String.t()}` | N/A (process env) | **MATCH** | Environment variables for CLI process |
| `extra_args: dict[str, str \| None]` | `extra_args: %{String.t() => String.t() \| boolean() \| nil}` | Various | **MATCH** | Boolean/nil -> flag only; value -> flag + value |

### 6. Buffer/Debug Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `max_buffer_size: int \| None` | `max_buffer_size: pos_integer()` | N/A | **MATCH** | Internal buffer limit; CLIJSONDecodeError on overflow |
| `debug_stderr: Any` | N/A | N/A | **DEPRECATED** | Python deprecated; use `stderr` callback instead |
| `stderr: Callable[[str], None] \| None` | `stderr: (String.t() -> any())` | N/A | **MATCH** | Callback for CLI stderr output |

### 7. Advanced Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `permission_prompt_tool_name: str \| None` | `permission_prompt_tool: String.t()` | `--permission-prompt-tool` | **MATCH** | Auto-set when `can_use_tool` configured |
| `can_use_tool: CanUseTool \| None` | `can_use_tool: callback()` | N/A | **MATCH** | Permission callback; async in Python, sync in Elixir |
| `hooks: dict[HookEvent, list[HookMatcher]] \| None` | `hooks: hook_config()` | N/A | **MATCH** | Timeout serialized to seconds; same events supported |

### 8. Feature Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `include_partial_messages: bool` | `include_partial_messages: boolean()` | `--include-partial-messages` | **MATCH** | Enable streaming character-level updates |
| `agents: dict[str, AgentDefinition] \| None` | `agents: %{atom() => Agent.t()}` | `--agents` | **MATCH** | JSON-encoded; Elixir uses atom keys internally |
| `plugins: list[SdkPluginConfig]` | `plugins: [plugin_config()]` | `--plugin-dir` | **MATCH** | Local plugins only; `type: "local"` |

### 9. Sandbox Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `sandbox: SandboxSettings \| None` | `sandbox: map()` | Via `--settings` | **MATCH** | Merged into settings JSON |

**SandboxSettings sub-fields:**

| Python Field | Elixir Equivalent | Status |
|--------------|-------------------|--------|
| `enabled: bool` | `"enabled"` | **MATCH** |
| `autoAllowBashIfSandboxed: bool` | `"autoAllowBashIfSandboxed"` | **MATCH** |
| `excludedCommands: list[str]` | `"excludedCommands"` | **MATCH** |
| `allowUnsandboxedCommands: bool` | `"allowUnsandboxedCommands"` | **MATCH** |
| `network: SandboxNetworkConfig` | `"network"` map | **MATCH** |
| `ignoreViolations: SandboxIgnoreViolations` | `"ignoreViolations"` map | **MATCH** |
| `enableWeakerNestedSandbox: bool` | `"enableWeakerNestedSandbox"` | **MATCH** |

**SandboxNetworkConfig:**

| Python Field | Status |
|--------------|--------|
| `allowUnixSockets: list[str]` | **MATCH** |
| `allowAllUnixSockets: bool` | **MATCH** |
| `allowLocalBinding: bool` | **MATCH** |
| `httpProxyPort: int` | **MATCH** |
| `socksProxyPort: int` | **MATCH** |

**SandboxIgnoreViolations:**

| Python Field | Status |
|--------------|--------|
| `file: list[str]` | **MATCH** |
| `network: list[str]` | **MATCH** |

### 10. Output Options

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `max_thinking_tokens: int \| None` | `max_thinking_tokens: pos_integer()` | `--max-thinking-tokens` | **MATCH** | Integer value |
| `output_format: dict[str, Any] \| None` | `output_format: output_format()` | `--output-format` + `--json-schema` | **MATCH** | Structured outputs via json_schema type |
| `enable_file_checkpointing: bool` | `enable_file_checkpointing: boolean()` | N/A (env var) | **MATCH** | Sets `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING` |

### 11. User Option

| Python Field | Elixir Field | CLI Flag | Status | Notes |
|--------------|--------------|----------|--------|-------|
| `user: str \| None` | `user: String.t()` | N/A | **MATCH** | Process user via erlexec/port |

---

## SystemPromptPreset and ToolsPreset Handling

### SystemPromptPreset

**Python Definition:**
```python
class SystemPromptPreset(TypedDict):
    type: Literal["preset"]
    preset: Literal["claude_code"]
    append: NotRequired[str]
```

**Elixir Handling:**
```elixir
# In Options.ex - normalize_system_prompt_preset/1
# Accepts both atom and string keys:
%{type: :preset, preset: :claude_code, append: "Additional context"}
%{"type" => "preset", "preset" => "claude_code", "append" => "Additional context"}
```

**CLI Mapping:**
- Preset without `append`: No flags emitted (uses CLI default prompt)
- Preset with `append`: Emits `--append-system-prompt <value>`
- String prompt: Emits `--system-prompt <value>`
- `nil`: Emits `--system-prompt ""` (force empty)

**Status:** **MATCH** - Both SDKs handle presets identically.

### ToolsPreset

**Python Definition:**
```python
class ToolsPreset(TypedDict):
    type: Literal["preset"]
    preset: Literal["claude_code"]
```

**Elixir Handling:**
```elixir
# In Options.ex - add_tools_args/2
# Any map with type: :preset maps to "default"
%{type: :preset, preset: :claude_code}  # -> --tools default
```

**CLI Mapping:**
- Preset map: Emits `--tools default`
- Empty list `[]`: Emits `--tools ""`
- Tool list: Emits `--tools tool1,tool2,...`
- `nil`: No flag emitted

**Status:** **MATCH** - Both SDKs map presets to `"default"`.

---

## CLI Flag Mapping Verification

### Python `_build_command()` vs Elixir `to_args()`

| CLI Flag | Python Source | Elixir Source | Match |
|----------|---------------|---------------|-------|
| `--output-format stream-json` | Default for SDK | Default for stream_json | YES |
| `--verbose` | Added with stream-json | Added with stream_json | YES |
| `--system-prompt ""` | When None | When nil | YES |
| `--system-prompt <value>` | String prompt | String prompt | YES |
| `--append-system-prompt` | Preset with append | Preset with append | YES |
| `--tools` | List or "default" | List or "default" | YES |
| `--tools ""` | Empty list | Empty list | YES |
| `--allowedTools` | Comma-separated | Comma-separated | YES |
| `--disallowedTools` | Comma-separated | Comma-separated | YES |
| `--max-turns` | Integer | Integer | YES |
| `--max-budget-usd` | Float | Number | YES |
| `--model` | String | String | YES |
| `--fallback-model` | String | String | YES |
| `--betas` | Comma-separated | Comma-separated | YES |
| `--permission-prompt-tool` | String | String | YES |
| `--permission-mode` | String | Atom->String | YES |
| `--continue` | Flag only | Flag only | YES |
| `--resume` | Session ID | Session ID | YES |
| `--settings` | JSON or path | JSON or path | YES |
| `--setting-sources` | Always emitted | Always emitted | YES |
| `--add-dir` | Per directory | Per directory | YES |
| `--mcp-config` | JSON wrapped | JSON wrapped | YES |
| `--include-partial-messages` | Flag only | Flag only | YES |
| `--fork-session` | Flag only | Flag only | YES |
| `--agents` | JSON string | JSON string | YES |
| `--plugin-dir` | Per plugin path | Per plugin path | YES |
| `--max-thinking-tokens` | Integer | Integer | YES |
| `--json-schema` | From output_format | From output_format | YES |
| `--print --` | String prompt mode | N/A (different) | N/A |
| `--input-format stream-json` | Streaming mode | N/A (different) | N/A |

**Note:** The `--print` and `--input-format` flags differ by design. Elixir uses different transport mechanisms (Process, Streaming, Client) that handle prompt injection differently.

---

## Identified Gaps

### Gap 1: debug_stderr Deprecation (LOW PRIORITY)

**Python:**
```python
debug_stderr: Any = sys.stderr  # Deprecated
```

**Elixir:**
- Field not present (correct - deprecated in Python)

**Resolution:** No action needed. Python deprecated this in favor of `stderr` callback.

### Gap 2: Path Type Coercion (LOW PRIORITY)

**Python:**
```python
cwd: str | Path | None  # Accepts pathlib.Path
cli_path: str | Path | None  # Accepts pathlib.Path
add_dirs: list[str | Path]  # Accepts pathlib.Path
```

**Elixir:**
```elixir
cwd: String.t() | nil  # String only
path_to_claude_code_executable: String.t() | nil  # String only
add_dirs: [String.t()]  # String only
```

**Resolution:** Elixir idiomatically uses strings for paths. No action needed.

### Gap 3: Agent Key Types (LOW PRIORITY)

**Python:**
```python
agents: dict[str, AgentDefinition]  # String keys
```

**Elixir:**
```elixir
agents: %{atom() => Agent.t()}  # Atom keys
```

**Resolution:** Elixir idiomatically uses atoms for map keys. Converted to strings during JSON serialization. No action needed.

---

## Elixir-Only Features (Extras)

The Elixir port includes additional features not in Python:

| Feature | Description |
|---------|-------------|
| `abort_ref: reference()` | Erlang reference for cooperative abort signaling |
| `session_id: String.t()` | Explicit session ID (Python uses internal management) |
| `agent: atom()` | Active agent selection (Python manages differently) |
| `strict_mcp_config: boolean()` | MCP strictness flag |
| `mcp_config: String.t()` | Backward-compatible file path option |
| `verbose: boolean()` | Explicit verbose toggle |
| `executable: String.t()` | Alternative to path_to_claude_code_executable |
| `executable_args: [String.t()]` | Custom executable arguments |
| `timeout_ms: integer()` | Command execution timeout |
| `preferred_transport: :auto \| :cli \| :control` | Transport selection override |

---

## Type Comparison Summary

### Python Types -> Elixir Types

| Python Type | Elixir Type | Notes |
|-------------|-------------|-------|
| `str` | `String.t()` | Direct mapping |
| `int` | `integer()` | Direct mapping |
| `float` | `number()` | Includes integers |
| `bool` | `boolean()` | Direct mapping |
| `None` | `nil` | Direct mapping |
| `list[T]` | `[T]` | Direct mapping |
| `dict[K, V]` | `%{K => V}` | Direct mapping |
| `Path` | `String.t()` | Coerced to string |
| `Literal["a", "b"]` | `:a \| :b` | Atoms for literals |
| `TypedDict` | `%{}` with type specs | Struct or map |
| `Callable[[...], T]` | `(... -> T)` | Function type |
| `Awaitable[T]` | `T` | Elixir is sync |
| `AsyncIterable[T]` | `Enumerable.t()` | Lazy sequences |

### Permission Modes

| Python | Elixir | CLI |
|--------|--------|-----|
| `"default"` | `:default` | `"default"` |
| `"acceptEdits"` | `:accept_edits` | `"acceptEdits"` |
| `"plan"` | `:plan` | `"plan"` |
| `"bypassPermissions"` | `:bypass_permissions` | `"bypassPermissions"` |

### Hook Events

| Python | Elixir | CLI |
|--------|--------|-----|
| `"PreToolUse"` | `:pre_tool_use` | `"PreToolUse"` |
| `"PostToolUse"` | `:post_tool_use` | `"PostToolUse"` |
| `"UserPromptSubmit"` | `:user_prompt_submit` | `"UserPromptSubmit"` |
| `"Stop"` | `:stop` | `"Stop"` |
| `"SubagentStop"` | `:subagent_stop` | `"SubagentStop"` |
| `"PreCompact"` | `:pre_compact` | `"PreCompact"` |

---

## Priority Recommendations

### Already Resolved (No Action Needed)

1. **All core options** - Full parity achieved
2. **All session options** - Full parity achieved
3. **All model options** - Full parity achieved
4. **Sandbox settings** - Full parity via settings merge
5. **Hooks configuration** - Timeout seconds parity confirmed
6. **MCP servers** - SDK and external server handling matches
7. **Structured outputs** - json_schema type supported
8. **File checkpointing** - Environment variable set correctly

### Low Priority (Documentation Only)

1. **Document debug_stderr deprecation** - Python deprecated, Elixir correctly omits
2. **Document Path coercion** - Elixir strings work identically
3. **Document agent key types** - Atom->String conversion transparent

### Future Considerations

1. **Async permission callbacks** - Python uses `Awaitable`, Elixir is synchronous
   - Current behavior acceptable; could add Task-based async if needed
2. **Hook callback async support** - Similar to permission callbacks
   - Could leverage Elixir processes for concurrent hook execution

---

## Verification Checklist

- [x] All ClaudeAgentOptions fields mapped
- [x] All CLI flags verified
- [x] SystemPromptPreset handling verified
- [x] ToolsPreset handling verified
- [x] SandboxSettings merge verified
- [x] Hook timeout serialization verified
- [x] MCP server stripping verified
- [x] Permission mode conversion verified
- [x] Extra Elixir features documented
- [x] Type mappings documented

---

## Conclusion

The Elixir Claude Agent SDK port achieves **complete functional parity** with the Python SDK's configuration options. All 38+ option fields are properly implemented with correct CLI flag mappings. The identified gaps are minor (deprecated fields, path type idioms, key type idioms) and require no remediation.

The port also provides Elixir-idiomatic enhancements such as:
- Atom-based enums for type safety
- Reference-based abort signaling
- Configurable transport selection
- Structured option building via `OptionBuilder`

**Recommendation:** The configuration and options implementation is production-ready. Focus future development on new Python SDK features as they are released.
