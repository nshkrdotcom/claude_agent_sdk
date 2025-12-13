# Tools Option Feature

**PR**: #389
**Commit**: ea0ef25
**Author**: Ashwin Bhat
**Priority**: High

## Overview

The `tools` option controls the **base set** of available tools, separately from the `allowed_tools`/`disallowed_tools` filtering. This matches the TypeScript SDK's approach.

## Python Implementation

### Types (`types.py`)

```python
class ToolsPreset(TypedDict):
    """Tools preset configuration."""
    type: Literal["preset"]
    preset: Literal["claude_code"]

@dataclass
class ClaudeAgentOptions:
    tools: list[str] | ToolsPreset | None = None
    allowed_tools: list[str] = field(default_factory=list)
    # ... existing fields
```

### Transport (`subprocess_cli.py`)

```python
# Handle tools option (base set of tools)
if self._options.tools is not None:
    tools = self._options.tools
    if isinstance(tools, list):
        if len(tools) == 0:
            cmd.extend(["--tools", ""])
        else:
            cmd.extend(["--tools", ",".join(tools)])
    else:
        # Preset object - 'claude_code' preset maps to 'default'
        cmd.extend(["--tools", "default"])
```

## Supported Modes

1. **Array of tool names**: `["Read", "Edit", "Bash"]`
   - CLI: `--tools Read,Edit,Bash`

2. **Empty array**: `[]` (disables all built-in tools)
   - CLI: `--tools ""`

3. **Preset object**: `{"type": "preset", "preset": "claude_code"}`
   - CLI: `--tools default`

## Elixir Implementation

### 1. Add Type Definition

In `lib/claude_agent_sdk/options.ex`:

```elixir
@typedoc """
Tools preset configuration.
"""
@type tools_preset :: %{
        type: :preset,
        preset: :claude_code
      }

@typedoc """
Tools option - controls base set of available tools.
- List of tool names: ["Read", "Edit", "Bash"]
- Empty list: [] (disables all built-in tools)
- Preset: %{type: :preset, preset: :claude_code}
"""
@type tools_option :: [String.t()] | tools_preset() | nil
```

### 2. Add Field to Options Struct

In `lib/claude_agent_sdk/options.ex`, add a new `:tools` field near the existing
`allowed_tools`/`disallowed_tools` fields:

```elixir
defstruct [
  # ...
  # NEW: Base set of tools (Python v0.1.12+)
  :tools,
  # Existing filtering options
  :allowed_tools,
  :disallowed_tools,
  # ... existing fields
]
```

And update the `@type t`:

```elixir
@type t :: %__MODULE__{
        tools: tools_option(),
        allowed_tools: [String.t()] | nil,
        # ... existing fields
      }
```

### 3. Add CLI Argument Builder

In `lib/claude_agent_sdk/options.ex`, add the argument builder:

```elixir
@spec to_args(t()) :: [String.t()]
def to_args(%__MODULE__{} = options) do
  []
  |> add_output_format_args(options)
  |> add_max_turns_args(options)
  # ... existing builders
  |> add_append_system_prompt_args(options)
  |> add_tools_args(options)          # NEW - add before allowed_tools/disallowed_tools
  |> add_allowed_tools_args(options)
  |> add_disallowed_tools_args(options)
  # ...
end

# NEW: Handle tools option
defp add_tools_args(args, %{tools: nil}), do: args

defp add_tools_args(args, %{tools: tools}) when is_list(tools) do
  if tools == [] do
    args ++ ["--tools", ""]
  else
    args ++ ["--tools", Enum.join(tools, ",")]
  end
end

defp add_tools_args(args, %{tools: %{type: :preset, preset: :claude_code}}) do
  args ++ ["--tools", "default"]
end

defp add_tools_args(args, %{tools: %{"type" => "preset", "preset" => "claude_code"}}) do
  args ++ ["--tools", "default"]
end
```

### 4. Add OptionBuilder Helpers (Optional)

In `lib/claude_agent_sdk/option_builder.ex`:

```elixir
@doc """
Sets the base tools to a specific list.

## Examples

    options = OptionBuilder.with_tools(["Read", "Glob", "Grep"])
"""
@spec with_tools([String.t()]) :: Options.t()
def with_tools(tools) when is_list(tools) do
  %Options{tools: tools}
end

@spec with_tools(Options.t(), [String.t()]) :: Options.t()
def with_tools(%Options{} = options, tools) when is_list(tools) do
  %{options | tools: tools}
end

@doc """
Disables all built-in tools.
"""
@spec with_no_tools() :: Options.t()
def with_no_tools do
  %Options{tools: []}
end

@spec with_no_tools(Options.t()) :: Options.t()
def with_no_tools(%Options{} = options) do
  %{options | tools: []}
end

@doc """
Uses the default Claude Code tools preset.
"""
@spec with_tools_preset() :: Options.t()
def with_tools_preset do
  %Options{tools: %{type: :preset, preset: :claude_code}}
end
```

## Tests to Add

```elixir
# test/claude_agent_sdk/options_test.exs

describe "tools option" do
  test "tools as array generates --tools flag" do
    options = %Options{tools: ["Read", "Edit", "Bash"]}
    args = Options.to_args(options)

    assert "--tools" in args
    tools_idx = Enum.find_index(args, &(&1 == "--tools"))
    assert Enum.at(args, tools_idx + 1) == "Read,Edit,Bash"
  end

  test "tools as empty array generates empty --tools flag" do
    options = %Options{tools: []}
    args = Options.to_args(options)

    assert "--tools" in args
    tools_idx = Enum.find_index(args, &(&1 == "--tools"))
    assert Enum.at(args, tools_idx + 1) == ""
  end

  test "tools preset generates --tools default" do
    options = %Options{tools: %{type: :preset, preset: :claude_code}}
    args = Options.to_args(options)

    assert "--tools" in args
    tools_idx = Enum.find_index(args, &(&1 == "--tools"))
    assert Enum.at(args, tools_idx + 1) == "default"
  end

  test "nil tools does not generate --tools flag" do
    options = %Options{tools: nil}
    args = Options.to_args(options)

    refute "--tools" in args
  end
end
```

## Usage Example

```elixir
# Only allow Read, Glob, and Grep tools
options = %ClaudeAgentSDK.Options{
  tools: ["Read", "Glob", "Grep"],
  max_turns: 1
}

for message <- ClaudeAgentSDK.query("What tools do you have?", options) do
  IO.inspect(message)
end

# Disable all built-in tools (SDK MCP tools only)
options = %ClaudeAgentSDK.Options{
  tools: [],
  mcp_servers: %{"custom" => my_mcp_server}
}

# Use Claude Code default preset
options = %ClaudeAgentSDK.Options{
  tools: %{type: :preset, preset: :claude_code}
}
```

## Difference from allowed_tools/disallowed_tools

| Option | Purpose | CLI Flag |
|--------|---------|----------|
| `tools` | Sets the **base set** of tools available | `--tools` |
| `allowed_tools` | **Filters** from base set (whitelist) | `--allowedTools` |
| `disallowed_tools` | **Filters** from base set (blacklist) | `--disallowedTools` |

Example: If `tools: ["Read", "Edit", "Bash"]` and `disallowed_tools: ["Bash"]`, only Read and Edit are available.
