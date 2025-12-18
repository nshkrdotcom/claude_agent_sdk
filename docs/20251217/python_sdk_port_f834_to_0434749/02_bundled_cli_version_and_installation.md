# Port: Bundled Claude Code CLI Version (→ 2.0.72) + Optional Installation Workflow

## Background

The Python SDK bundles Claude Code and tracks the bundled version in code:

- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_cli_version.py`
  - `__cli_version__ = "2.0.72"` (as of `91e65b1`)

Within this port range, Python bumped the bundled CLI from **2.0.69 → 2.0.72**.

Even when Elixir does not ship the binary, keeping a *pinned reference version* is valuable:

- Reproducible integration test environment (“use the same CLI Python bundles”)
- A single place to document “known-good” CLI versions for features like:
  - streaming control protocol (hooks/permissions)
  - file checkpointing + rewind
  - partial message streaming

## Current Elixir State

### Already present

- `ClaudeAgentSDK.CLI` supports bundled binary discovery:
  - default path: `priv/_bundled/claude` (or `claude.exe` on Windows)
  - override: `Application.get_env(:claude_agent_sdk, :cli_bundled_path)`
  - also searches PATH and common locations including `~/.claude/local/claude`
- Minimum version warning:
  - `@minimum_version "2.0.0"`
  - `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK` supported

Related prior design work:
- `docs/20251129/elixir_port_sync/adrs/0005-bundled-cli.md` proposes an opt-in bundling workflow and a tracked CLI version constant; this port supplies the concrete “what version?” input (2.0.72) and extends it with Docker-driven regression testing needs.

### Missing / not yet standardized

1. **Tracked “recommended/bundled CLI version” constant** in the Elixir codebase
2. **A repeatable “install/bundle CLI” workflow** (mix task / script)
3. **Docs that tie feature requirements to versions** (we have scattered notes; no single source of truth)

## Port Design

### 1) Add a pinned CLI version module

Add `lib/claude_agent_sdk/cli_version.ex` (or similar) that exposes:

- `ClaudeAgentSDK.CLIVersion.bundled/0 :: String.t()` → `"2.0.72"`
- (optional) `ClaudeAgentSDK.CLIVersion.minimum_supported/0 :: String.t()` → `"2.0.0"`

Rationale:
- Mirrors Python’s `_cli_version.py` and makes “what version should I use?” discoverable.
- Lets docs/tests reference a single constant.

### 2) Add an opt-in bundling task (developer/CI convenience)

Add a mix task:

- `mix claude.bundle_cli`

Behavior:
- Determines desired CLI version:
  - default: `ClaudeAgentSDK.CLIVersion.bundled()`
  - override: `--version 2.0.72`
- Installs Claude Code using an official channel
  - Unix: `curl -fsSL https://claude.ai/install.sh | bash`
  - Windows: `irm https://claude.ai/install.ps1 | iex`
- Locates the installed `claude` executable (typically `$HOME/.local/bin/claude`)
- Copies it into `priv/_bundled/claude` (or `priv/_bundled/claude.exe`)
- Ensures execute permissions on Unix
- Verifies `priv/_bundled/claude --version` matches the requested version (or prints a warning if the installer cannot pin)

Notes / constraints:
- The official installer may install “latest” rather than a specific version; if so, we have two options:
  1. Treat `bundled` as “known-good minimum” and accept newer versions
  2. Prefer version pinning via `npm install -g @anthropic-ai/claude-code@<version>` when Node is available

The design should support both:
- `--strategy installer` (default, simple)
- `--strategy npm` (pinned, requires Node)

### 3) `.gitignore` policy for bundled binaries

Add a `priv/_bundled/.gitignore` (or update root `.gitignore`) so the binary is not committed.

### 4) Use the pinned version in docs and diagnostics

Update documentation to explicitly state:
- “Recommended CLI version: `ClaudeAgentSDK.CLIVersion.bundled()` (2.0.72)”
- “Minimum supported: 2.0.0 (warnings only, unless a feature requires more)”

Optionally update `ClaudeAgentSDK.AuthChecker.diagnose/0` output to show:
- installed CLI version
- pinned recommended version

### 5) Feature-specific version expectations (optional follow-on)

Python’s pinned CLI bumps often accompany new control protocol capabilities.

For Elixir, consider adding *feature-level* version notes/warnings (non-blocking):
- if `enable_file_checkpointing: true`, warn when CLI < 2.0.69 (or whichever version introduced checkpointing)
- if `include_partial_messages: true`, warn when CLI < the first supporting version

This is strictly a devX enhancement; it’s not required for parity with Python’s “minimum version” check but aligns with the motivation of tracking a bundled version.

## Test Plan

- Unit:
  - `ClaudeAgentSDK.CLIVersion.bundled/0` returns a semver string
  - `ClaudeAgentSDK.CLI.find_executable/0` prefers `priv/_bundled` when present (already partially covered indirectly; add explicit unit coverage if needed)
- Integration (tagged):
  - `mix claude.bundle_cli` actually installs/copies/verifies (network + platform dependent)

## Rollout / Migration

- Ship `CLIVersion` module + docs first (safe).
- Add `mix claude.bundle_cli` next (opt-in).
- Consider CI integration only after the task is stable across platforms.

## Proposed Elixir Touchpoints

- New: `lib/claude_agent_sdk/cli_version.ex`
- New: `lib/mix/tasks/claude.bundle_cli.ex` (or `claude.install_cli.ex`)
- Update (optional): `lib/claude_agent_sdk/cli.ex` to expose `recommended_version/0` and/or include it in warnings/diagnostics
- Update: `.gitignore` and/or add `priv/_bundled/.gitignore`
- Update (optional): `lib/claude_agent_sdk/auth_checker.ex` to display recommended/bundled CLI version in `diagnose/0`
