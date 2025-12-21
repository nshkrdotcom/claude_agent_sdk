# CLI Bundling Analysis: Elixir SDK Options

**Date**: 2025-12-20
**Status**: Analysis / Future Consideration
**Author**: Claude Agent SDK Team

## Executive Summary

The Python Claude Agent SDK bundles the Claude Code CLI binary directly into the package, providing a zero-dependency installation experience. This document analyzes how the Python SDK achieves this and explores potential approaches for the Elixir SDK.

## Current State

### Elixir SDK (Current)

- **CLI Installation**: Users must install separately via npm
- **Discovery**: SDK searches PATH and common locations
- **Recommended Version**: Tracked in `@recommended_version` constant
- **User Experience**: Requires Node.js/npm as a prerequisite

```bash
# Current user workflow
npm install -g @anthropic-ai/claude-code
mix deps.get
```

### Python SDK (Reference Implementation)

- **CLI Installation**: Bundled in the wheel package
- **Discovery**: Checks bundled binary first, falls back to PATH
- **Version Tracking**: `__cli_version__` matches bundled binary
- **User Experience**: Zero external dependencies

```bash
# Python user workflow
pip install claude-agent-sdk
# That's it - CLI is included
```

## Python SDK Bundling Mechanism

### 1. Download Script (`scripts/download_cli.py`)

Uses Anthropic's official install scripts (NOT npm):

```python
# Unix
install_cmd = ["bash", "-c", "curl -fsSL https://claude.ai/install.sh | bash"]

# Windows
install_cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-Command",
               "irm https://claude.ai/install.ps1 | iex"]
```

The CLI binary is a self-contained executable (~50-100MB), compiled from the Node.js codebase using tools like `pkg` or `nexe`.

### 2. Build Process (`scripts/build_wheel.py`)

```
1. Download CLI binary via official installer
2. Copy to src/claude_agent_sdk/_bundled/claude
3. Build wheel with `python -m build --wheel`
4. Retag wheel as platform-specific:
   - manylinux_2_17_x86_64
   - macosx_11_0_arm64
   - win_amd64
   - etc.
```

### 3. Runtime Discovery (`subprocess_cli.py`)

```python
def _find_cli(self):
    # Priority 1: Bundled CLI
    bundled_cli = self._find_bundled_cli()
    if bundled_cli:
        return bundled_cli

    # Priority 2: System PATH
    if cli := shutil.which("claude"):
        return cli

    # Priority 3: Common locations
    # ~/.local/bin/claude, /usr/local/bin/claude, etc.
```

### 4. Platform-Specific Wheels

PyPI supports platform-tagged wheels:

| Platform | Wheel Tag |
|----------|-----------|
| Linux x86_64 | `manylinux_2_17_x86_64` |
| Linux ARM64 | `manylinux_2_17_aarch64` |
| macOS x86_64 | `macosx_11_0_x86_64` |
| macOS ARM64 | `macosx_11_0_arm64` |
| Windows x64 | `win_amd64` |

`pip install` automatically selects the correct wheel for the user's platform.

## Challenges for Elixir/Hex

### 1. No Platform-Specific Package Support

Hex.pm does not support platform-tagged packages like PyPI wheels. A single package must work across all platforms.

**Impact**: Cannot ship different binaries for different OS/arch combinations in a single package version.

### 2. Binary Size Concerns

| Scenario | Package Size |
|----------|--------------|
| Current (no CLI) | ~200 KB |
| Single platform CLI | ~50-100 MB |
| All platforms bundled | ~300-500 MB |

Bundling all platform binaries would create an unreasonably large package.

### 3. Hex Package Conventions

Hex packages typically contain:
- Elixir/Erlang source code
- Native NIFs (compiled per-platform via `:make` or similar)
- Static assets in `priv/`

Large pre-built binaries are unconventional and may violate community expectations.

### 4. Build-Time vs Runtime

Elixir NIFs are compiled at `mix deps.compile` time using the system's toolchain. The Claude CLI is a pre-built binary, not source that can be compiled.

## Potential Approaches

### Approach 1: Download on First Use

**Description**: Automatically download the CLI binary when first needed at runtime.

**Implementation**:
```elixir
defmodule ClaudeAgentSDK.CLI.Installer do
  @install_dir Application.app_dir(:claude_agent_sdk, "priv/bin")

  def ensure_installed! do
    case find_executable() do
      {:ok, path} -> {:ok, path}
      {:error, :not_found} -> download_and_install()
    end
  end

  defp download_and_install do
    script = download_install_script()
    {_, 0} = System.cmd("bash", ["-c", script], env: [{"HOME", @install_dir}])
    {:ok, Path.join(@install_dir, "claude")}
  end
end
```

**Pros**:
- Zero-config experience for users
- Only downloads for user's actual platform
- No package size increase

**Cons**:
- Network dependency at runtime
- First-run delay (~30-60 seconds)
- Requires write access to priv/ or user directory
- Version pinning complexity
- Security considerations (downloading executables)

**User Experience**:
```elixir
# First query triggers download
ClaudeAgentSDK.query("Hello")
# => Downloading Claude CLI 2.0.75... done (45s)
# => "Hello! How can I help you today?"
```

### Approach 2: Mix Task Installer

**Description**: Provide a Mix task that users run once to install the CLI.

**Implementation**:
```elixir
defmodule Mix.Tasks.Claude.Install do
  use Mix.Task

  @shortdoc "Install Claude Code CLI"

  def run(args) do
    version = parse_version(args) || ClaudeAgentSDK.CLI.recommended_version()

    Mix.shell().info("Installing Claude Code CLI #{version}...")

    install_script = fetch_install_script()
    install_dir = determine_install_dir()

    case System.cmd("bash", ["-c", install_script],
                    env: [{"CLAUDE_INSTALL_DIR", install_dir}]) do
      {_, 0} ->
        Mix.shell().info("Claude CLI installed to #{install_dir}")
      {error, _} ->
        Mix.raise("Installation failed: #{error}")
    end
  end
end
```

**Pros**:
- Explicit user control
- No runtime surprises
- Can specify version
- Familiar pattern (like `mix ecto.setup`)

**Cons**:
- Extra step for users
- Users may forget to run it
- Documentation burden

**User Experience**:
```bash
mix deps.get
mix claude.install           # or: mix claude.install --version 2.0.75
mix run -e 'ClaudeAgentSDK.query("Hello")'
```

### Approach 3: Compile-Time Download (deps.compile hook)

**Description**: Download CLI during `mix deps.compile` via a custom compiler.

**Implementation** (in `mix.exs`):
```elixir
def project do
  [
    # ...
    compilers: [:claude_cli] ++ Mix.compilers(),
  ]
end
```

```elixir
defmodule Mix.Tasks.Compile.ClaudeCli do
  use Mix.Task.Compiler

  def run(_args) do
    unless cli_installed?() do
      download_cli()
    end
    {:ok, []}
  end
end
```

**Pros**:
- Automatic during normal workflow
- Happens once at compile time
- No runtime network calls

**Cons**:
- Unconventional use of compiler
- May confuse users
- CI/CD considerations
- Doesn't work for pre-compiled releases

**User Experience**:
```bash
mix deps.get
mix deps.compile  # CLI downloaded here automatically
```

### Approach 4: Separate Binary Package

**Description**: Create a companion package `claude_cli` that only provides the CLI binary.

**Implementation**:
```elixir
# In claude_agent_sdk mix.exs
defp deps do
  [
    {:claude_cli, "~> 2.0", optional: true}
  ]
end
```

```elixir
# claude_cli package - uses post-install hook
defmodule ClaudeCli.MixProject do
  # Downloads CLI in Mix.Tasks.Compile.ClaudeCli
end
```

**Pros**:
- Separation of concerns
- Users can opt-in to bundled CLI
- Version can track CLI releases

**Cons**:
- Maintaining two packages
- Optional dependency complexity
- Still has platform/size issues

**User Experience**:
```elixir
# mix.exs - explicit opt-in
{:claude_agent_sdk, "~> 0.6.8"},
{:claude_cli, "~> 2.0"}  # Optional: bundle the CLI
```

### Approach 5: Status Quo (Recommended)

**Description**: Keep the current approach - users install CLI separately via npm.

**Rationale**:
- Claude CLI is a Node.js tool, npm is the natural distribution
- Users likely already have Node.js for other tools
- No package size bloat
- No platform compatibility issues
- Clear separation of concerns

**Improvements to current approach**:
1. Better error messages when CLI not found
2. `mix claude.doctor` task for diagnostics
3. Documentation with copy-paste install commands
4. Version compatibility warnings

**User Experience** (enhanced):
```bash
# If CLI not found, helpful error:
$ mix run -e 'ClaudeAgentSDK.query("Hello")'

** (ClaudeAgentSDK.Errors.CLINotFoundError)
   Claude Code CLI not found.

   Install with:
     npm install -g @anthropic-ai/claude-code@2.0.75

   Or via official installer:
     curl -fsSL https://claude.ai/install.sh | bash

   Then authenticate:
     claude login
```

## Recommendation Matrix

| Approach | Complexity | User Experience | Maintenance | Recommended? |
|----------|------------|-----------------|-------------|--------------|
| Download on First Use | High | Good | Medium | No |
| Mix Task Installer | Medium | Good | Low | Maybe |
| Compile-Time Hook | Medium | Great | Medium | Maybe |
| Separate Package | High | Good | High | No |
| Status Quo (Enhanced) | Low | Acceptable | Low | **Yes** |

## Recommended Path Forward

### Short Term (v0.6.x)
1. Keep current npm-based installation
2. Improve error messages when CLI not found
3. Add `mix claude.doctor` diagnostic task
4. Document alternative install methods (official installer script)

### Medium Term (v0.7.x)
1. Consider `mix claude.install` task as convenience
2. Evaluate user feedback on installation friction

### Long Term (v1.0+)
1. Re-evaluate if Anthropic provides better distribution options
2. Consider if Hex adds platform-specific package support
3. Monitor how other Elixir packages solve similar problems

## Appendix: Official Install Script Details

The Claude CLI install script (`https://claude.ai/install.sh`) handles:

1. Platform detection (Linux/macOS/Windows)
2. Architecture detection (x86_64/arm64)
3. Download of correct binary
4. Installation to `~/.local/bin/` or specified location
5. PATH configuration hints

This is the same mechanism the Python SDK uses, making it a reliable option for any approach we choose.

## References

- Python SDK `scripts/download_cli.py`
- Python SDK `scripts/build_wheel.py`
- Python SDK `_internal/transport/subprocess_cli.py`
- Anthropic install script: `https://claude.ai/install.sh`
