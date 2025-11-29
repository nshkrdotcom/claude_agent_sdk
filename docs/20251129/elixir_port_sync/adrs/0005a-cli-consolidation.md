# ADR 0005a: CLI Discovery Consolidation and Version Tracking

- **Status:** Proposed
- **Date:** 2025-11-29
- **Owner:** SDK team
- **Related:** ADR 0005 (Optional Bundled CLI) - this ADR is a prerequisite

## Context
- CLI executable discovery (`System.find_executable("claude")`) is scattered across 5+ modules with inconsistent error handling.
- No version tracking exists; users may run outdated CLI versions without warning.
- ADR 0005 proposes optional CLI bundling, but requires a centralized discovery module as a foundation.
- This ADR extracts the non-bundling portions of ADR 0005 to clean up the codebase immediately.

### Current State (Scattered Discovery)

| Location | Pattern | Error Handling |
|----------|---------|----------------|
| `process.ex:373` | `find_executable/0` | Raises on not found |
| `streaming/session.ex:470` | Tries `claude-code` then `claude` | Falls back to `"claude"` string |
| `client.ex:1074` | Direct `System.find_executable` | Returns `{:error, :claude_not_found}` |
| `transport/port.ex:231` | Direct call | Returns `{:error, {:command_not_found, "claude"}}` |
| `auth_checker.ex:344` | Direct call + version check | Returns `{false, nil}` |

## Decision
1. Create `ClaudeAgentSDK.CLI` module as single source of truth for executable discovery.
2. Add version detection and minimum version tracking.
3. Emit warnings when installed CLI is older than minimum supported version.
4. Migrate all call sites to use the new module.
5. Prepare `.gitignore` for future bundled binaries (ADR 0005).

## Rationale
- **DRY principle**: Eliminate 5 duplicate discovery implementations.
- **Consistent errors**: Unified error handling across all entry points.
- **Version awareness**: Proactive warnings help users avoid compatibility issues.
- **Foundation for bundling**: When ADR 0005 bundling is implemented, only `CLI.find_executable/0` needs modification.
- **Testability**: Single module is easier to mock in tests.

## Consequences
- All modules gain a dependency on `ClaudeAgentSDK.CLI`.
- Slightly more indirection for executable lookup (negligible performance impact).
- Version checks add a subprocess call on first use (cached thereafter).

## Module API

```elixir
defmodule ClaudeAgentSDK.CLI do
  @minimum_version "1.0.0"

  # Discovery
  def find_executable()        # {:ok, path} | {:error, :not_found}
  def find_executable!()       # path | raises RuntimeError
  def installed?()             # boolean

  # Version management
  def version()                # {:ok, "1.2.3"} | {:error, reason}
  def minimum_version()        # returns @minimum_version string
  def version_supported?()     # true if installed >= minimum

  # Warnings
  def warn_if_outdated()       # emits Logger.warning if version < minimum, returns :ok

  # Future (ADR 0005 bundling):
  # def bundled_path()         # path to priv/_bundled/claude* or nil
end
```

## Implementation Plan

### Phase 1: Create CLI Module
1. Create `lib/claude_agent_sdk/cli.ex` with discovery and version functions.
2. Implement version parsing for `claude --version` output.
3. Add `@minimum_version` module attribute.
4. Add `warn_if_outdated/0` that logs when version < minimum.

### Phase 2: Migrate Call Sites
1. `process.ex` — replace private `find_executable/0` with `CLI.find_executable!/0`.
2. `streaming/session.ex` — replace inline logic with `CLI.find_executable!/0`.
3. `client.ex` — replace with `CLI.find_executable/0`, pattern match result.
4. `transport/port.ex` — replace with `CLI.find_executable/0`.
5. `auth_checker.ex` — replace with `CLI.find_executable/0` + `CLI.version/0`.

### Phase 3: Cleanup and Tests
1. Remove dead `find_executable/0` from `process.ex`.
2. Add `test/claude_agent_sdk/cli_test.exs` with unit tests.
3. Update `.gitignore` with `priv/_bundled/` entry for ADR 0005.

### Phase 4: Documentation
1. Add `@moduledoc` and `@doc` to CLI module.
2. Note in README that CLI version >= minimum is recommended.

## Alternatives Considered
- **Keep scattered discovery** — rejected; makes ADR 0005 bundling harder and violates DRY.
- **Implement full ADR 0005 bundling now** — rejected; bundling adds complexity and isn't needed yet.
- **No version tracking** — rejected; version mismatches cause confusing errors.

## Rollout
- Ship as internal refactor; no breaking changes to public API.
- Changelog notes the new `ClaudeAgentSDK.CLI` module for advanced users.
- ADR 0005 bundling can follow once this foundation is in place.
