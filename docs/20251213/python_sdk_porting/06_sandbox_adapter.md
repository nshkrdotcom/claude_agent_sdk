# Sandbox Adapter Interface

**PR**: #363
**Commit**: f21f63e
**Author**: ollie-anthropic
**Priority**: Lower (Elixir has `settings` pass-through; sandbox merge not yet implemented)

## Overview

Adds programmatic sandbox configuration to the SDK, allowing control over bash command sandboxing behavior. This matches the TypeScript SDK's approach.

**Important**: Filesystem and network *restrictions* are configured via permission rules (`Read`/`Edit`/`WebFetch` allow/deny), NOT via these sandbox settings. Sandbox settings control *behavior* (enabled, auto-allow, excluded commands, etc.).

## Python Implementation

### Types (`types.py`)

```python
class SandboxNetworkConfig(TypedDict, total=False):
    """Network configuration for sandbox."""
    allowUnixSockets: list[str]
    allowAllUnixSockets: bool
    allowLocalBinding: bool
    httpProxyPort: int
    socksProxyPort: int


class SandboxIgnoreViolations(TypedDict, total=False):
    """Violations to ignore in sandbox."""
    file: list[str]
    network: list[str]


class SandboxSettings(TypedDict, total=False):
    """Sandbox settings configuration."""
    enabled: bool
    autoAllowBashIfSandboxed: bool
    excludedCommands: list[str]
    allowUnsandboxedCommands: bool
    network: SandboxNetworkConfig
    ignoreViolations: SandboxIgnoreViolations
    enableWeakerNestedSandbox: bool


@dataclass
class ClaudeAgentOptions:
    # Sandbox configuration for bash command isolation.
    sandbox: SandboxSettings | None = None
```

### Transport (`subprocess_cli.py`)

```python
def _build_settings_value(self) -> str | None:
    """Build settings value, merging sandbox settings if provided."""
    has_settings = self._options.settings is not None
    has_sandbox = self._options.sandbox is not None

    if not has_settings and not has_sandbox:
        return None

    # If only settings path and no sandbox, pass through as-is
    if has_settings and not has_sandbox:
        return self._options.settings

    # If we have sandbox settings, we need to merge into a JSON object
    settings_obj: dict[str, Any] = {}

    if has_settings:
        # Parse existing settings (JSON string or file path)
        # ... parsing logic ...

    # Merge sandbox settings
    if has_sandbox:
        settings_obj["sandbox"] = self._options.sandbox

    return json.dumps(settings_obj)

def _build_command(self) -> list[str]:
    # ...
    settings_value = self._build_settings_value()
    if settings_value:
        cmd.extend(["--settings", settings_value])
```

## Elixir Implementation

### 1. Add Type Definitions

In `lib/claude_agent_sdk/options.ex` or a new `lib/claude_agent_sdk/sandbox.ex`:

```elixir
@typedoc """
Network configuration for sandbox.
"""
@type sandbox_network_config :: %{
        optional(:allowUnixSockets) => [String.t()],
        optional(:allowAllUnixSockets) => boolean(),
        optional(:allowLocalBinding) => boolean(),
        optional(:httpProxyPort) => pos_integer(),
        optional(:socksProxyPort) => pos_integer()
      }

@typedoc """
Violations to ignore in sandbox.
"""
@type sandbox_ignore_violations :: %{
        optional(:file) => [String.t()],
        optional(:network) => [String.t()]
      }

@typedoc """
Sandbox settings configuration.

Controls how Claude Code sandboxes bash commands for filesystem
and network isolation.

Note: Filesystem and network restrictions are configured via permission
rules, not via these sandbox settings.
"""
@type sandbox_settings :: %{
        optional(:enabled) => boolean(),
        optional(:autoAllowBashIfSandboxed) => boolean(),
        optional(:excludedCommands) => [String.t()],
        optional(:allowUnsandboxedCommands) => boolean(),
        optional(:network) => sandbox_network_config(),
        optional(:ignoreViolations) => sandbox_ignore_violations(),
        optional(:enableWeakerNestedSandbox) => boolean()
      }
```

### 2. Add Field to Options Struct

```elixir
defstruct [
  # ... existing fields
  :setting_sources,
  # NEW: Sandbox configuration (v0.7.0)
  :sandbox,
  plugins: [],
  # ... rest of fields
]

@type t :: %__MODULE__{
        # ... existing fields
        setting_sources: [String.t() | atom()] | nil,
        sandbox: sandbox_settings() | nil,
        plugins: [plugin_config()],
        # ... rest of fields
      }
```

### 3. Update Settings Argument Builder

Replace the simple `add_settings_args/2` with a merged version:

```elixir
defp add_settings_args(args, options) do
  case build_settings_value(options) do
    nil -> args
    settings_value -> args ++ ["--settings", settings_value]
  end
end

@doc """
Builds the settings value, merging sandbox settings if provided.

Returns:
- nil if neither settings nor sandbox is provided
- The settings path if only settings is provided (no sandbox)
- JSON string if sandbox is provided (merged with settings if present)
"""
@spec build_settings_value(t()) :: String.t() | nil
defp build_settings_value(%{settings: nil, sandbox: nil}), do: nil

defp build_settings_value(%{settings: settings, sandbox: nil}) when is_binary(settings) do
  # No sandbox, pass settings through as-is
  settings
end

defp build_settings_value(%{settings: settings, sandbox: sandbox}) when sandbox != nil do
  # Have sandbox, need to merge into JSON
  settings_obj = parse_existing_settings(settings)

  # Merge sandbox settings
  settings_obj = Map.put(settings_obj, "sandbox", normalize_sandbox(sandbox))

  Jason.encode!(settings_obj)
end

defp parse_existing_settings(nil), do: %{}

defp parse_existing_settings(settings) when is_binary(settings) do
  trimmed = String.trim(settings)

  cond do
    # JSON string
    String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") ->
      case Jason.decode(trimmed) do
        {:ok, obj} when is_map(obj) -> obj
        _ -> read_settings_file(settings)
      end

    # File path
    true ->
      read_settings_file(settings)
  end
end

defp read_settings_file(path) do
  case File.read(path) do
    {:ok, content} ->
      case Jason.decode(content) do
        {:ok, obj} when is_map(obj) -> obj
        _ -> %{}
      end

    {:error, _} ->
      %{}
  end
end

defp normalize_sandbox(sandbox) when is_map(sandbox) do
  # Convert atom keys to string keys for JSON
  for {k, v} <- sandbox, into: %{} do
    key = if is_atom(k), do: Atom.to_string(k), else: k
    value = normalize_sandbox_value(v)
    {key, value}
  end
end

defp normalize_sandbox_value(v) when is_map(v), do: normalize_sandbox(v)
defp normalize_sandbox_value(v) when is_list(v), do: v
defp normalize_sandbox_value(v), do: v
```

### 4. Add OptionBuilder Helpers

```elixir
@doc """
Enables sandboxing with default settings.

## Examples

    options = OptionBuilder.with_sandbox()
"""
@spec with_sandbox() :: Options.t()
def with_sandbox do
  %Options{sandbox: %{enabled: true}}
end

@spec with_sandbox(Options.t()) :: Options.t()
def with_sandbox(%Options{} = options) do
  %{options | sandbox: %{enabled: true}}
end

@doc """
Configures sandbox with custom settings.

## Examples

    options = OptionBuilder.with_sandbox_settings(%{
      enabled: true,
      autoAllowBashIfSandboxed: true,
      excludedCommands: ["docker", "git"],
      network: %{
        allowLocalBinding: true,
        allowUnixSockets: ["/var/run/docker.sock"]
      }
    })
"""
@spec with_sandbox_settings(sandbox_settings()) :: Options.t()
def with_sandbox_settings(sandbox) when is_map(sandbox) do
  %Options{sandbox: sandbox}
end

@spec with_sandbox_settings(Options.t(), sandbox_settings()) :: Options.t()
def with_sandbox_settings(%Options{} = options, sandbox) when is_map(sandbox) do
  %{options | sandbox: sandbox}
end
```

## Tests to Add

```elixir
describe "sandbox option" do
  test "sandbox only generates JSON settings" do
    options = %Options{
      sandbox: %{
        enabled: true,
        autoAllowBashIfSandboxed: true
      }
    }
    args = Options.to_args(options)

    assert "--settings" in args
    settings_idx = Enum.find_index(args, &(&1 == "--settings"))
    settings_value = Enum.at(args, settings_idx + 1)

    parsed = Jason.decode!(settings_value)
    assert parsed["sandbox"]["enabled"] == true
    assert parsed["sandbox"]["autoAllowBashIfSandboxed"] == true
  end

  test "sandbox merges with existing JSON settings" do
    existing = ~s({"permissions": {"allow": ["Bash(ls:*)"]}, "verbose": true})

    options = %Options{
      settings: existing,
      sandbox: %{
        enabled: true,
        excludedCommands: ["git", "docker"]
      }
    }
    args = Options.to_args(options)

    settings_idx = Enum.find_index(args, &(&1 == "--settings"))
    settings_value = Enum.at(args, settings_idx + 1)

    parsed = Jason.decode!(settings_value)

    # Original settings preserved
    assert parsed["permissions"] == %{"allow" => ["Bash(ls:*)"]}
    assert parsed["verbose"] == true

    # Sandbox merged in
    assert parsed["sandbox"]["enabled"] == true
    assert parsed["sandbox"]["excludedCommands"] == ["git", "docker"]
  end

  test "settings file path passed through when no sandbox" do
    options = %Options{settings: "/path/to/settings.json"}
    args = Options.to_args(options)

    assert "--settings" in args
    settings_idx = Enum.find_index(args, &(&1 == "--settings"))
    assert Enum.at(args, settings_idx + 1) == "/path/to/settings.json"
  end

  test "sandbox with full network config" do
    options = %Options{
      sandbox: %{
        enabled: true,
        network: %{
          allowUnixSockets: ["/tmp/ssh-agent.sock"],
          allowAllUnixSockets: false,
          allowLocalBinding: true,
          httpProxyPort: 8080,
          socksProxyPort: 8081
        }
      }
    }
    args = Options.to_args(options)

    settings_idx = Enum.find_index(args, &(&1 == "--settings"))
    settings_value = Enum.at(args, settings_idx + 1)

    parsed = Jason.decode!(settings_value)
    network = parsed["sandbox"]["network"]

    assert network["allowUnixSockets"] == ["/tmp/ssh-agent.sock"]
    assert network["allowAllUnixSockets"] == false
    assert network["allowLocalBinding"] == true
    assert network["httpProxyPort"] == 8080
    assert network["socksProxyPort"] == 8081
  end
end
```

## Usage Example

```elixir
# Basic sandboxing
options = %ClaudeAgentSDK.Options{
  sandbox: %{
    enabled: true,
    autoAllowBashIfSandboxed: true
  }
}

# Full configuration
options = %ClaudeAgentSDK.Options{
  sandbox: %{
    enabled: true,
    autoAllowBashIfSandboxed: true,
    excludedCommands: ["docker", "git"],  # Run outside sandbox
    allowUnsandboxedCommands: false,       # All else must be sandboxed
    network: %{
      allowLocalBinding: true,
      allowUnixSockets: ["/var/run/docker.sock"]
    },
    ignoreViolations: %{
      file: ["/tmp/*"],
      network: ["localhost"]
    }
  }
}

for message <- ClaudeAgentSDK.query("Build and test the project", options) do
  IO.inspect(message)
end
```

## Configuration Reference

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `enabled` | boolean | false | Enable bash sandboxing (macOS/Linux only) |
| `autoAllowBashIfSandboxed` | boolean | true | Auto-approve bash when sandboxed |
| `excludedCommands` | [string] | [] | Commands to run outside sandbox |
| `allowUnsandboxedCommands` | boolean | true | Allow `dangerouslyDisableSandbox` |
| `network.allowUnixSockets` | [string] | [] | Accessible Unix socket paths |
| `network.allowAllUnixSockets` | boolean | false | Allow all Unix sockets |
| `network.allowLocalBinding` | boolean | false | Allow localhost binding (macOS) |
| `network.httpProxyPort` | int | - | Custom HTTP proxy port |
| `network.socksProxyPort` | int | - | Custom SOCKS5 proxy port |
| `ignoreViolations.file` | [string] | [] | File paths to ignore violations |
| `ignoreViolations.network` | [string] | [] | Network hosts to ignore violations |
| `enableWeakerNestedSandbox` | boolean | false | Weaker sandbox for Docker (Linux) |

## Notes

1. Sandbox settings control *behavior*, not *restrictions*
2. Filesystem restrictions use `Read`/`Edit` permission rules
3. Network restrictions use `WebFetch` permission rules
4. The `--settings` flag receives JSON when sandbox is configured
5. Existing settings (file path or JSON) are merged with sandbox config

## Audit Notes

- The Elixir SDK already has a “sandboxed” preset (`ClaudeAgentSDK.OptionBuilder.sandboxed/2`), but that is implemented via working directory + permission rules (e.g. disallowing `Bash`). It is separate from (and does not replace) the Python `sandbox` settings object merged into `--settings`.
