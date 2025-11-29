# Task
Implement ADR 0005 (Optional Bundled Claude Code CLI for Elixir SDK) using TDD.

# Required Reading (read first)
- `docs/20251129/elixir_port_sync/adrs/0005-bundled-cli.md`
- CLI discovery and process spawn:
  - `lib/claude_agent_sdk/process.ex` (executable resolution, PATH check)
  - Any other transport/executable finders (search for `find_executable`/`System.find_executable("claude")`).
- Package metadata:
  - `mix.exs` (package files list, app config)
  - `.gitignore` (to extend with `priv/_bundled/claude*` if not present)
- Tasks/tests:
  - Existing mix tasks for reference (search `lib/mix/tasks` or `mix/tasks` paths).
  - Tests touching CLI resolution (search in `test/claude_agent_sdk/*` and `test/support`).

# Constraints / Alignment
- Root of repo is `../`. Paths above are relative to that root.
- Follow ADR 0005: implement optional bundling, prefer bundled executable, keep PATH fallback, add CLI version tracking, provide a mix task to download/copy the CLI, and do not ship binaries in Hex by default.
- Platform handling: `priv/_bundled/claude` (Unix) and `priv/_bundled/claude.exe` (Windows). Set execute bit on Unix.
- Add `.gitignore` entry for bundled binaries if missing.
- Provide warning when PATH binary is older than a minimum/desired version if no bundle is found.

# TDD Expectations
1. Add tests first:
   - Executable resolution prefers bundled over PATH; falls back to PATH when no bundle.
   - Warning emitted when only PATH binary is older than desired version (mock version check).
   - Mix task skeleton test: ensures it resolves target path and attempts copy; mock download to avoid network.
2. Implement code to satisfy tests:
   - `cli_version` module with desired/version helper.
   - Discovery logic update in process/transport.
   - `.gitignore` update for bundled binaries.
   - Mix task to download (via official installer) and copy into `priv/_bundled`, with flags for version/skip-download.
3. Run relevant tests and note results; if networked tests are risky, mark them skipped or mock download.

# Acceptance Criteria
- `lib/claude_agent_sdk/cli_version.ex` (or similar) exposes desired CLI version string.
- Executable discovery checks `priv/_bundled/claude*` first, then PATH; logs chosen path.
- Mix task `mix claude.bundle_cli` (name can vary but documented) downloads or reuses a CLI binary and places it in `priv/_bundled`, setting execute bits on Unix; supports specifying version or defaulting to `@cli_version`.
- `.gitignore` ignores bundled binaries.
- Tests cover discovery preference and warning behavior; task logic has at least a mocked test path. All added tests pass.
- Docs updated (README/ops) with instructions to bundle, note default PATH usage, and describe version pinning/size considerations.
