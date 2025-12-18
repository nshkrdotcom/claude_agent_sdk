# Port: Bundled Claude Code CLI Version (→ 2.0.72) + Optional Installation Workflow

## Background

The Python SDK tracks a bundled CLI version in code:

- `src/claude_agent_sdk/_cli_version.py`: `__cli_version__ = "2.0.72"` (as of `91e65b1`)

Within this port range, Python bumped from **2.0.69 → 2.0.72** across three commits.

Even when Elixir does not ship the binary on Hex, keeping a *pinned reference version* is valuable:

- Reproducible integration test environment ("use the same CLI Python bundles")
- A single place to document "known-good" CLI versions for features like:
  - streaming control protocol (hooks/permissions)
  - file checkpointing + rewind
  - partial message streaming

## Current Elixir State

### Already present

- **Bundled binary discovery** in `ClaudeAgentSDK.CLI` (`lib/claude_agent_sdk/cli.ex`):
  - `find_bundled_executable/0` at line 128-136 checks `priv/_bundled/claude` (or `claude.exe` on Windows)
  - Override via `Application.get_env(:claude_agent_sdk, :cli_bundled_path)`
  - `find_in_known_locations/0` at line 165-175 searches PATH and common locations including `~/.claude/local/claude`

- **Minimum version warning** at `cli.ex:12-14`:
  - `@minimum_version "2.0.0"`
  - `@skip_version_check_env "CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK"`

### Missing / not yet standardized

1. **Tracked "recommended/bundled CLI version" constant** - No `@recommended_version` or `recommended_version/0` function
2. **A repeatable "install/bundle CLI" workflow** - No mix task for installing/bundling
3. **Docs that tie feature requirements to versions** - Scattered notes, no single source of truth

## Port Design

### 1) Add a recommended CLI version constant (required)

**Option A: Add to existing `cli.ex` (simpler)**

```elixir
# In lib/claude_agent_sdk/cli.ex
@recommended_version "2.0.72"

@doc """
Returns the recommended Claude CLI version for this SDK release.
"""
@spec recommended_version() :: String.t()
def recommended_version, do: @recommended_version
```

**Option B: New module (mirrors Python structure)**

Add `lib/claude_agent_sdk/cli_version.ex`:

```elixir
defmodule ClaudeAgentSDK.CLIVersion do
  @moduledoc "Tracks recommended CLI versions for SDK features."

  @recommended "2.0.72"

  def recommended, do: @recommended
  def minimum, do: "2.0.0"
end
```

**Recommendation:** Option A is sufficient and avoids adding a new module for a single constant.

### 2) Optional: Add a bundling helper task

**Important constraint:** The official installer (`curl https://claude.ai/install.sh | bash`) does **not** support version pinning. It always installs the latest version.

To pin a specific version, you must use npm:
```bash
npm install -g @anthropic-ai/claude-code@2.0.72
```

Given this, a mix task would have limited utility:
- `--strategy installer` - Installs latest (not the pinned version)
- `--strategy npm` - Requires Node.js, defeats some of the simplicity

**Recommendation:** Document the npm approach for users who need version pinning. A mix task is lower priority.

If implemented, keep it simple:

```elixir
# lib/mix/tasks/claude.install_cli.ex
defmodule Mix.Tasks.Claude.InstallCli do
  use Mix.Task

  @shortdoc "Installs Claude CLI to priv/_bundled/"

  def run(_args) do
    # 1. Run: curl -fsSL https://claude.ai/install.sh | bash
    # 2. Copy ~/.local/bin/claude to priv/_bundled/claude
    # 3. Verify with --version
    # NOTE: This installs latest, not necessarily @recommended_version
  end
end
```

### 3) `.gitignore` policy

The bundled binary path is already covered if `.gitignore` includes `priv/_bundled/`. Verify this exists; if not, add:

```gitignore
# Bundled CLI binaries (not committed)
priv/_bundled/
```

### 4) Update diagnostics (optional)

`ClaudeAgentSDK.AuthChecker.diagnose/0` could show:
- Installed CLI version: `2.0.XX`
- Recommended version: `2.0.72`
- Status: ✓ (or warning if below recommended)

## Test Plan

| Test type | What to test | Tag |
|-----------|--------------|-----|
| Unit | `ClaudeAgentSDK.CLI.recommended_version/0` returns a semver string | (none) |
| Unit | `ClaudeAgentSDK.CLI.find_executable/0` prefers `priv/_bundled` when present | (none) |

## Proposed Elixir Touchpoints

| File | Change | Priority |
|------|--------|----------|
| `lib/claude_agent_sdk/cli.ex` | Add `@recommended_version` and `recommended_version/0` | Required |
| `.gitignore` | Ensure `priv/_bundled/` is ignored | Required |
| `lib/mix/tasks/claude.install_cli.ex` | Bundling task | Optional |
| `lib/claude_agent_sdk/auth_checker.ex` | Show recommended vs installed version | Optional |

## Risks / Open Questions

1. **Installer doesn't support version pinning** - The official installer always installs latest. This limits the utility of a bundling task. Document npm approach for users who need reproducibility.

2. **Version drift** - If recommended version isn't updated when Python bumps theirs, we drift. Consider a process note to bump when Python does.

3. **Hex doesn't ship binaries** - Unlike Python (PyPI can include binaries), Hex packages are source-only. Users must install CLI separately. This is a known limitation, not a bug.
