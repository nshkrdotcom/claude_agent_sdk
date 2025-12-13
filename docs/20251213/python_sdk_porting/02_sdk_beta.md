# SDK Beta Support

**PR**: #390
**Commit**: 4e56cb1
**Author**: Ashwin Bhat
**Priority**: High

## Overview

The `betas` option allows SDK users to pass beta feature flags to the CLI. Currently supports the 1M context window beta.

## Python Implementation

### Types (`types.py`)

```python
# SDK Beta features - see https://docs.anthropic.com/en/api/beta-headers
SdkBeta = Literal["context-1m-2025-08-07"]

@dataclass
class ClaudeAgentOptions:
    # Beta features - see https://docs.anthropic.com/en/api/beta-headers
    betas: list[SdkBeta] = field(default_factory=list)
```

### Transport (`subprocess_cli.py`)

```python
if self._options.betas:
    cmd.extend(["--betas", ",".join(self._options.betas)])
```

### Exports (`__init__.py`)

```python
from .types import (
    SdkBeta,
    # ...
)

__all__ = [
    # ...
    "SdkBeta",
    # ...
]
```

## Elixir Implementation

### 1. Add Type Definition

In `lib/claude_agent_sdk/options.ex`:

```elixir
@typedoc """
SDK Beta features.
See: https://docs.anthropic.com/en/api/beta-headers

Current betas:
- "context-1m-2025-08-07" - 1M context window beta
"""
@type sdk_beta :: String.t()
# Or more strictly:
# @type sdk_beta :: :"context-1m-2025-08-07"
```

### 2. Add Field to Options Struct

In `lib/claude_agent_sdk/options.ex`, add to `defstruct`:

```elixir
defstruct [
  # ... existing fields
  :model,
  :fallback_model,
  # NEW: Beta features (Python v0.1.12+)
  betas: [],
  :permission_prompt_tool,
  # ... rest of fields
]
```

And update the `@type t`:

```elixir
@type t :: %__MODULE__{
        # ... existing fields
        model: model_name() | nil,
        fallback_model: model_name() | nil,
        betas: [sdk_beta()],
        permission_prompt_tool: String.t() | nil,
        # ... rest of fields
      }
```

### 3. Add CLI Argument Builder

In `lib/claude_agent_sdk/options.ex`:

```elixir
@spec to_args(t()) :: [String.t()]
def to_args(%__MODULE__{} = options) do
  []
  |> add_output_format_args(options)
  # ... existing builders
  |> add_fallback_model_args(options)
  |> add_betas_args(options)           # NEW
  |> add_agents_args(options)
  # ... rest of builders
end

# NEW: Handle betas option
defp add_betas_args(args, %{betas: []}), do: args
defp add_betas_args(args, %{betas: nil}), do: args

defp add_betas_args(args, %{betas: betas}) when is_list(betas) do
  args ++ ["--betas", Enum.join(betas, ",")]
end
```

### 4. Add OptionBuilder Helper (Optional)

In `lib/claude_agent_sdk/option_builder.ex`:

```elixir
@doc """
Enables 1M context window beta.

## Examples

    options = OptionBuilder.with_1m_context()
"""
@spec with_1m_context() :: Options.t()
def with_1m_context do
  %Options{betas: ["context-1m-2025-08-07"]}
end

@spec with_1m_context(Options.t()) :: Options.t()
def with_1m_context(%Options{} = options) do
  existing_betas = options.betas || []
  %{options | betas: ["context-1m-2025-08-07" | existing_betas] |> Enum.uniq()}
end

@doc """
Adds a beta feature flag.

## Examples

    options = OptionBuilder.with_beta("context-1m-2025-08-07")
"""
@spec with_beta(String.t()) :: Options.t()
def with_beta(beta_name) when is_binary(beta_name) do
  %Options{betas: [beta_name]}
end

@spec with_beta(Options.t(), String.t()) :: Options.t()
def with_beta(%Options{} = options, beta_name) when is_binary(beta_name) do
  existing_betas = options.betas || []
  %{options | betas: [beta_name | existing_betas] |> Enum.uniq()}
end
```

## Tests to Add

```elixir
# test/claude_agent_sdk/options_test.exs

describe "betas option" do
  test "betas list generates --betas flag" do
    options = %Options{betas: ["context-1m-2025-08-07"]}
    args = Options.to_args(options)

    assert "--betas" in args
    betas_idx = Enum.find_index(args, &(&1 == "--betas"))
    assert Enum.at(args, betas_idx + 1) == "context-1m-2025-08-07"
  end

  test "multiple betas are comma-separated" do
    options = %Options{betas: ["context-1m-2025-08-07", "future-beta-2025-01-01"]}
    args = Options.to_args(options)

    assert "--betas" in args
    betas_idx = Enum.find_index(args, &(&1 == "--betas"))
    assert Enum.at(args, betas_idx + 1) == "context-1m-2025-08-07,future-beta-2025-01-01"
  end

  test "empty betas does not generate --betas flag" do
    options = %Options{betas: []}
    args = Options.to_args(options)

    refute "--betas" in args
  end

  test "nil betas does not generate --betas flag" do
    options = %Options{betas: nil}
    args = Options.to_args(options)

    refute "--betas" in args
  end
end
```

## Usage Example

```elixir
# Enable 1M context window beta
options = %ClaudeAgentSDK.Options{
  betas: ["context-1m-2025-08-07"],
  max_turns: 5
}

for message <- ClaudeAgentSDK.query("Analyze this large codebase...", options) do
  IO.inspect(message)
end

# Using OptionBuilder helper
options =
  ClaudeAgentSDK.OptionBuilder.build_development_options()
  |> ClaudeAgentSDK.OptionBuilder.with_1m_context()
```

## Notes

1. For parity with Python, prefer defaulting `betas` to `[]`; treat `nil` as “unset” for backward compatibility
2. Beta names are passed as-is to the CLI - no validation is performed
3. Future betas can be added without code changes by users specifying the beta string directly
4. See Anthropic's API documentation for current beta features: https://docs.anthropic.com/en/api/beta-headers
