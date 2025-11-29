# Task
Implement ADR 0005a (CLI Discovery Consolidation and Version Tracking) using TDD.

# Required Reading (read first)
- `docs/20251129/elixir_port_sync/adrs/0005a-cli-consolidation.md`
- Current discovery implementations (all need migration):
  - `lib/claude_agent_sdk/process.ex` (lines 373-380, `find_executable/0`)
  - `lib/claude_agent_sdk/streaming/session.ex` (line 470, inline discovery)
  - `lib/claude_agent_sdk/client.ex` (line 1074, `build_cli_command/1`)
  - `lib/claude_agent_sdk/transport/port.ex` (lines 214, 231, `resolve_command/1` and `build_command_from_options/1`)
  - `lib/claude_agent_sdk/auth_checker.ex` (line 344, `check_cli_installation_private/0`)
- Existing tests for reference:
  - `test/claude_agent_sdk/process_env_test.exs`

# Constraints / Alignment
- Root of repo is the current working directory.
- Follow ADR 0005a exactly: create `ClaudeAgentSDK.CLI` module, migrate all call sites.
- Do NOT implement bundling (that's ADR 0005). Only consolidate discovery + add version tracking.
- Executable names to try in order: `claude-code`, then `claude` (matching `streaming/session.ex` pattern).
- Version parsing: run `claude --version`, parse output. Handle failure gracefully.
- Use `Logger.warning/1` for outdated version warnings (not `Logger.warn` which is deprecated).

# TDD Expectations
1. **Add tests first** (`test/claude_agent_sdk/cli_test.exs`):
   - `find_executable/0` returns `{:ok, path}` when CLI exists on PATH.
   - `find_executable/0` returns `{:error, :not_found}` when CLI missing.
   - `find_executable!/0` returns path when CLI exists.
   - `find_executable!/0` raises `RuntimeError` when CLI missing.
   - `installed?/0` returns boolean.
   - `version/0` returns `{:ok, version_string}` or `{:error, reason}`.
   - `minimum_version/0` returns the configured minimum version string.
   - `version_supported?/0` returns true/false based on comparison.
   - `warn_if_outdated/0` logs warning when version < minimum (use `ExUnit.CaptureLog`).

2. **Implement `lib/claude_agent_sdk/cli.ex`** to satisfy tests:
   - `@minimum_version "1.0.0"` (adjust based on actual Claude CLI versions).
   - Discovery tries `claude-code` first, then `claude`.
   - Version parsing handles `claude --version` output format.
   - Version comparison uses `Version.compare/2` if versions are semver-compatible.

3. **Migrate call sites** (one at a time, verify tests still pass):
   - `process.ex`: Replace `find_executable/0` body → `CLI.find_executable!()`.
   - `streaming/session.ex`: Replace inline logic → `CLI.find_executable!()`.
   - `client.ex`: Replace `System.find_executable("claude")` → `CLI.find_executable/0` with pattern match.
   - `transport/port.ex`: Replace in `build_command_from_options/1` → `CLI.find_executable/0`.
   - `auth_checker.ex`: Replace discovery → `CLI.find_executable/0`, version check → `CLI.version/0`.

4. **Cleanup**:
   - Remove now-unused private `find_executable/0` from `process.ex` if it becomes dead code.
   - Add `.gitignore` entry: `priv/_bundled/` (prep for ADR 0005).

5. **Run tests**: `mix test test/claude_agent_sdk/cli_test.exs` and full suite.

# Acceptance Criteria
- [ ] `lib/claude_agent_sdk/cli.ex` exists with all specified functions.
- [ ] All 5 call sites migrated to use `ClaudeAgentSDK.CLI`.
- [ ] `test/claude_agent_sdk/cli_test.exs` covers discovery, version, and warning logic.
- [ ] All tests pass (new and existing).
- [ ] `.gitignore` includes `priv/_bundled/` entry.
- [ ] No duplicate `System.find_executable("claude")` calls remain in migrated modules.
- [ ] `mix compile --warnings-as-errors` passes (no unused code warnings).

# Implementation Notes

## Version Parsing
The `claude --version` output format may vary. Example approaches:
```elixir
# If output is "claude 1.2.3\n"
case Regex.run(~r/(\d+\.\d+\.\d+)/, output) do
  [_, version] -> {:ok, version}
  _ -> {:error, :parse_failed}
end
```

## Version Comparison
```elixir
def version_supported? do
  case version() do
    {:ok, v} -> Version.compare(v, @minimum_version) != :lt
    {:error, _} -> false  # Can't determine, assume not supported
  end
end
```

## Warning Logic
```elixir
def warn_if_outdated do
  case version() do
    {:ok, v} ->
      if Version.compare(v, @minimum_version) == :lt do
        Logger.warning("Claude CLI version #{v} is below minimum #{@minimum_version}. Consider upgrading.")
      end
    {:error, _} ->
      Logger.warning("Could not determine Claude CLI version. Minimum supported: #{@minimum_version}")
  end
  :ok
end
```

# File Checklist
- [ ] `lib/claude_agent_sdk/cli.ex` (NEW)
- [ ] `test/claude_agent_sdk/cli_test.exs` (NEW)
- [ ] `lib/claude_agent_sdk/process.ex` (MODIFY)
- [ ] `lib/claude_agent_sdk/streaming/session.ex` (MODIFY)
- [ ] `lib/claude_agent_sdk/client.ex` (MODIFY)
- [ ] `lib/claude_agent_sdk/transport/port.ex` (MODIFY)
- [ ] `lib/claude_agent_sdk/auth_checker.ex` (MODIFY)
- [ ] `.gitignore` (MODIFY - add `priv/_bundled/`)
