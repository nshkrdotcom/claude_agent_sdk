# Gap Analysis: Agent Definitions and Plugins

**Date:** 2025-12-31
**Focus Area:** Agent Definitions and Plugins
**Python SDK:** `./anthropics/claude-agent-sdk-python/`
**Elixir Port:** `./`

---

## Executive Summary

The Elixir port achieves **near-complete parity** with the Python SDK for agent definitions and plugins. All core features are implemented:

- **AgentDefinition structure**: Fully implemented as `ClaudeAgentSDK.Agent` with matching required/optional fields
- **Agent JSON serialization**: Correct mapping to CLI expected format (`allowed_tools` -> `tools`)
- **Temp file handling**: Matching implementation for large agent payloads via `@file` syntax
- **SdkPluginConfig**: Implemented with identical `type: "local", path:` structure
- **SettingSource options**: Full support for `["user", "project", "local"]`
- **CLI flag handling**: All relevant flags (`--agents`, `--agent`, `--plugin-dir`, `--setting-sources`) correctly generated

**Status:** Production-ready. No blocking gaps identified.

---

## Feature Comparison Table

| Feature | Python SDK | Elixir Port | Status | Notes |
|---------|------------|-------------|--------|-------|
| **AgentDefinition Structure** |||||
| `description` (required) | `AgentDefinition.description: str` | `Agent.description: String.t()` | Match | Enforced key in both |
| `prompt` (required) | `AgentDefinition.prompt: str` | `Agent.prompt: String.t()` | Match | Enforced key in both |
| `tools` (optional) | `list[str] \| None` | `allowed_tools: [String.t()] \| nil` | Match | Elixir uses `allowed_tools` internally, serializes to `"tools"` |
| `model` (optional) | `Literal["sonnet", "opus", "haiku", "inherit"] \| None` | `model: String.t() \| nil` | Match | Elixir accepts any string (more permissive) |
| **Agent Serialization** |||||
| CLI JSON format | `--agents '{"name": {...}}'` | `--agents '{"name": {...}}'` | Match | Same JSON structure |
| Field mapping | `tools` key in JSON | `allowed_tools` -> `"tools"` | Match | Correct transformation |
| Nil field omission | Omits nil fields | Omits nil fields | Match | `put_if_present/3` helper |
| **Temp File Handling** |||||
| Command length limit (Windows) | 8,000 chars | 8,000 chars | Match | Platform-specific |
| Command length limit (Other) | 100,000 chars | 100,000 chars | Match | Generous limit |
| File syntax | `@filepath` | `@filepath` | Match | Same CLI protocol |
| Cleanup | `self._temp_files` list | `cleanup_temp_files/1` | Match | Automatic cleanup |
| **Plugin Configuration** |||||
| `SdkPluginConfig` type | `type: Literal["local"]` | `type: :local \| "local"` | Match | Elixir accepts atom or string |
| `path` field | `path: str` | `path: String.t()` | Match | Required field |
| CLI flag | `--plugin-dir path` | `--plugin-dir path` | Match | Per-plugin flag |
| Multiple plugins | Loop over list | Loop over list | Match | Same iteration pattern |
| **SettingSource** |||||
| Type values | `Literal["user", "project", "local"]` | `[String.t() \| atom()]` | Match | Elixir more permissive |
| Default behavior | Emits `--setting-sources ""` | Emits `--setting-sources ""` | Match | Explicit empty = no filesystem settings |
| CLI format | Comma-separated | Comma-separated | Match | e.g., `"user,project"` |

---

## Detailed Implementation Analysis

### 1. AgentDefinition Structure

#### Python SDK (`types.py:42-49`)

```python
@dataclass
class AgentDefinition:
    """Agent definition configuration."""

    description: str
    prompt: str
    tools: list[str] | None = None
    model: Literal["sonnet", "opus", "haiku", "inherit"] | None = None
```

#### Elixir Port (`agent.ex:61-77`)

```elixir
@type t :: %__MODULE__{
        name: atom() | nil,
        description: String.t(),
        prompt: String.t(),
        allowed_tools: [String.t()] | nil,
        model: String.t() | nil
      }

@enforce_keys [:description, :prompt]
defstruct [
  :name,
  :description,
  :prompt,
  :allowed_tools,
  :model
]
```

**Analysis:**
- Both have `description` and `prompt` as required fields
- Elixir adds an optional `name` field for internal agent identification (not serialized to CLI)
- Field naming: Python `tools` maps to Elixir `allowed_tools` (transformed during serialization)
- Model type: Python restricts to literal values; Elixir accepts any string (valid for full model names like "claude-opus-4")

**Verdict:** Complete parity with idiomatic Elixir enhancements.

---

### 2. Agent JSON Serialization

#### Python SDK (`subprocess_cli.py:279-285`)

```python
if self._options.agents:
    agents_dict = {
        name: {k: v for k, v in asdict(agent_def).items() if v is not None}
        for name, agent_def in self._options.agents.items()
    }
    agents_json = json.dumps(agents_dict)
    cmd.extend(["--agents", agents_json])
```

#### Elixir Port (`options.ex:773-786`)

```elixir
defp add_agents_args(args, %{agents: agents}) when is_map(agents) do
  agents_json =
    agents
    |> Enum.map(fn {name, agent} ->
      {to_string(name), ClaudeAgentSDK.Agent.to_cli_map(agent)}
    end)
    |> Map.new()
    |> Jason.encode!()

  args ++ ["--agents", agents_json]
end
```

#### Agent.to_cli_map (`agent.ex:207-214`)

```elixir
def to_cli_map(%__MODULE__{} = agent) do
  %{}
  |> put_if_present("description", agent.description)
  |> put_if_present("prompt", agent.prompt)
  |> put_if_present("tools", agent.allowed_tools)  # Note: allowed_tools -> "tools"
  |> put_if_present("model", agent.model)
end
```

**Analysis:**
- Both produce identical JSON structure: `{"agent_name": {"description": ..., "prompt": ..., "tools": [...], "model": ...}}`
- Nil fields are omitted in both implementations
- Elixir correctly transforms `allowed_tools` to `"tools"` key for CLI compatibility

**Verdict:** Exact functional parity.

---

### 3. Temp File Handling for Large Agent Definitions

#### Python SDK (`subprocess_cli.py:337-366`)

```python
# Check if command line is too long (Windows limitation)
cmd_str = " ".join(cmd)
if len(cmd_str) > _CMD_LENGTH_LIMIT and self._options.agents:
    # Command is too long - use temp file for agents
    try:
        agents_idx = cmd.index("--agents")
        agents_json_value = cmd[agents_idx + 1]

        temp_file = tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False, encoding="utf-8"
        )
        temp_file.write(agents_json_value)
        temp_file.close()

        self._temp_files.append(temp_file.name)
        cmd[agents_idx + 1] = f"@{temp_file.name}"
```

#### Elixir Port (`transport/agents_file.ex:10-22`)

```elixir
def externalize_agents_if_needed(args, opts) when is_list(args) and is_list(opts) do
  cmd_length = args |> Enum.join(" ") |> String.length()

  if cmd_length > cmd_length_limit(opts) do
    maybe_externalize_agents_arg(args)
  else
    {args, []}
  end
end

defp maybe_externalize_agents_arg(args) do
  case Enum.find_index(args, &(&1 == "--agents")) do
    nil -> {args, []}
    agents_idx ->
      # ... write to temp file and replace with @path
      path = write_temp_agents_file(value)
      {List.replace_at(args, agents_idx + 1, "@#{path}"), [path]}
  end
end
```

**Analysis:**
- Both use identical command length limits: 8,000 (Windows) / 100,000 (other)
- Both use the same `@filepath` syntax for file references
- Cleanup handled: Python via `self._temp_files`, Elixir via `cleanup_temp_files/1`
- Test coverage exists for Elixir implementation (`agents_file_test.exs`)

**Verdict:** Complete parity.

---

### 4. SdkPluginConfig Structure

#### Python SDK (`types.py:425-433`)

```python
class SdkPluginConfig(TypedDict):
    """SDK plugin configuration.

    Currently only local plugins are supported via the 'local' type.
    """

    type: Literal["local"]
    path: str
```

#### Elixir Port (`options.ex:208-213`)

```elixir
@typedoc """
Plugin configuration supported by the SDK (currently local directories only).
"""
@type plugin_config :: %{
        required(:type) => :local | String.t(),
        required(:path) => String.t()
      }
```

**Analysis:**
- Both define identical structure with `type` and `path` fields
- Both only support `"local"` type currently
- Elixir accepts both atom (`:local`) and string (`"local"`) for flexibility

**Verdict:** Complete parity.

---

### 5. Plugin Directory Registration (--plugin-dir)

#### Python SDK (`subprocess_cli.py:294-300`)

```python
if self._options.plugins:
    for plugin in self._options.plugins:
        if plugin["type"] == "local":
            cmd.extend(["--plugin-dir", plugin["path"]])
        else:
            raise ValueError(f"Unsupported plugin type: {plugin['type']}")
```

#### Elixir Port (`options.ex:827-839`)

```elixir
defp add_plugins_args(args, %{plugins: plugins}) when is_list(plugins) do
  Enum.reduce(plugins, args, fn plugin, acc ->
    case normalize_plugin(plugin) do
      {:ok, %{path: path}} ->
        acc ++ ["--plugin-dir", path]

      {:error, reason} ->
        raise ArgumentError, "Invalid plugin configuration: #{reason}"
    end
  end)
end
```

**Analysis:**
- Both iterate over plugins and emit `--plugin-dir` for each local plugin
- Both raise errors for unsupported plugin types
- Elixir adds normalization layer to handle atom/string keys uniformly

**Verdict:** Complete parity with additional robustness.

---

### 6. SettingSource Options

#### Python SDK (`types.py:24`)

```python
SettingSource = Literal["user", "project", "local"]
```

#### Elixir Port (`options.ex:227`)

```elixir
setting_sources: [String.t() | atom()] | nil,
```

**Analysis:**
- Python restricts to literal string values
- Elixir accepts both atoms and strings (e.g., `:user` or `"user"`)
- Both accept lists: `["user", "project", "local"]`

**Verdict:** Elixir is more permissive (superset).

---

### 7. --setting-sources CLI Flag Handling

#### Python SDK (`subprocess_cli.py:287-292`)

```python
sources_value = (
    ",".join(self._options.setting_sources)
    if self._options.setting_sources is not None
    else ""
)
cmd.extend(["--setting-sources", sources_value])
```

#### Elixir Port (`options.ex:659-666`)

```elixir
# Python parity: always emit setting sources, defaulting to empty (load no filesystem settings).
defp add_setting_sources_args(args, %{setting_sources: nil}),
  do: args ++ ["--setting-sources", ""]

defp add_setting_sources_args(args, %{setting_sources: sources}) when is_list(sources) do
  value = Enum.map_join(sources, ",", &to_string/1)
  args ++ ["--setting-sources", value]
end
```

**Analysis:**
- Both ALWAYS emit `--setting-sources` flag
- Default when nil: empty string `""` (disables filesystem settings loading)
- Values are comma-joined: `"user,project,local"`

**Verdict:** Exact parity (explicitly documented in Elixir code comments).

---

## Implementation Gaps

### No Gaps Identified

All analyzed features have complete or better-than-parity implementations in the Elixir port:

1. **AgentDefinition**: Full implementation with validation
2. **Agent serialization**: Correct JSON format with field mapping
3. **Temp file handling**: Cross-platform support with cleanup
4. **Plugin configuration**: Type and path with error handling
5. **Setting sources**: Always-emit behavior matching Python

---

## Test Coverage Comparison

| Test Area | Python SDK | Elixir Port | Notes |
|-----------|------------|-------------|-------|
| Agent struct creation | Examples only | `agent_test.exs` | Comprehensive unit tests |
| Agent validation | N/A | `agent_test.exs` | Elixir adds validation layer |
| Agent CLI args | Examples only | `options_agents_test.exs` | Full coverage |
| Agent + Options integration | `agents.py` example | `options_agents_test.exs` | Test + example |
| Temp file externalization | Implicit | `agents_file_test.exs` | Explicit unit test |
| Plugin args | `plugin_example.py` | `options_extended_test.exs` | Both have coverage |
| Setting sources | Examples | `options_extended_test.exs` | Full flag testing |
| Filesystem agents | `filesystem_agents.py` | `filesystem_agents_live.exs` | Integration examples |

---

## Priority Recommendations

### No Action Required

The Elixir port achieves full parity for agent definitions and plugins. The implementation is:

1. **Feature-complete**: All Python SDK features are implemented
2. **Well-tested**: Comprehensive unit and integration tests exist
3. **Documented**: Module docs and examples cover all use cases
4. **Validated**: Agent structs include validation that Python lacks

### Future Enhancements (Optional, Low Priority)

1. **Model validation**: Consider adding validation for known model values (`"sonnet"`, `"opus"`, `"haiku"`, `"inherit"`) while still allowing full model names
2. **Plugin type expansion**: When Python adds new plugin types (e.g., `"remote"`), add corresponding support

---

## File Reference Summary

### Python SDK Files Analyzed

| File | Key Content |
|------|-------------|
| `src/claude_agent_sdk/types.py:42-50` | `AgentDefinition` dataclass |
| `src/claude_agent_sdk/types.py:24` | `SettingSource` type |
| `src/claude_agent_sdk/types.py:425-433` | `SdkPluginConfig` TypedDict |
| `src/claude_agent_sdk/_internal/transport/subprocess_cli.py:279-300` | Agent + plugin CLI args |
| `src/claude_agent_sdk/_internal/transport/subprocess_cli.py:337-366` | Temp file handling |
| `examples/agents.py` | Agent usage examples |
| `examples/plugin_example.py` | Plugin usage example |
| `examples/filesystem_agents.py` | Setting sources example |

### Elixir Port Files Analyzed

| File | Key Content |
|------|-------------|
| `lib/claude_agent_sdk/agent.ex` | `Agent` struct and validation |
| `lib/claude_agent_sdk/options.ex:773-839` | Agent + plugin CLI args |
| `lib/claude_agent_sdk/options.ex:659-666` | Setting sources handling |
| `lib/claude_agent_sdk/transport/agents_file.ex` | Temp file externalization |
| `test/claude_agent_sdk/agent_test.exs` | Agent unit tests |
| `test/claude_agent_sdk/options_agents_test.exs` | Agent + Options tests |
| `test/claude_agent_sdk/options_extended_test.exs` | Plugin + setting sources tests |
| `test/claude_agent_sdk/transport/agents_file_test.exs` | Temp file tests |
| `examples/filesystem_agents_live.exs` | Filesystem agents example |

---

## Conclusion

The Elixir port provides **complete feature parity** for agent definitions and plugins. The implementation follows idiomatic Elixir patterns while maintaining exact CLI compatibility with the Python SDK. No remediation work is required for this feature area.
