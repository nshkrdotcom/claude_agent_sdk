# ADR 0001 — CLI path override and version checks still missing

- Status: Proposed
- Date: 2025-12-02

## Context
- The Python SDK lets callers point at a bundled or custom Claude CLI binary via `cli_path`, falls back to a packaged `_bundled` copy, and guards against outdated installs with a minimum version check (`anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:52-116` and `302-305`).
- Elixir options expose `:path_to_claude_code_executable`, `:executable`, and `:executable_args`, but both the process runner and control client always call `CLI.find_executable/0` and spawn whatever is on `PATH`, with no version enforcement (`lib/claude_agent_sdk/process.ex:302-310`, `lib/claude_agent_sdk/client.ex:1177-1190`).

## Gap
- Users cannot pin a specific CLI binary or rely on the bundled Claude CLI from Python; they also get no warning when running an unsupported CLI version.

## Consequences
- Environments without `claude` on `PATH` cannot use the Elixir SDK even when a bundled binary or explicit path is available.
- Version skew risks (e.g., pre-2.x CLIs) go undetected, leading to subtle control-protocol failures that Python proactively warns about.

## Recommendation
- Thread an explicit CLI path through both the process and control transports, honoring `path_to_claude_code_executable` / `executable` / `executable_args`.
- Add a minimal version probe (with a `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK` escape hatch) so we match Python’s guardrails. 
