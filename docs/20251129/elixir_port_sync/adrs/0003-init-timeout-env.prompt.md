# Task
Implement ADR 0003 (Initialize Timeout via Environment Override) using TDD.

# Required Reading (read first)
- `docs/20251129/elixir_port_sync/adrs/0003-init-timeout-env.md`
- Client/control flow: `lib/claude_agent_sdk/client.ex` (initialize, control request waits)
- Transport/process timeout behavior (for context): `lib/claude_agent_sdk/process.ex` (timeout_ms handling), any control-protocol waiting helpers.
- Relevant tests around initialization/control timeouts (search `test/claude_agent_sdk/*` and `test/support`).

# Constraints / Alignment
- Root of repo is `../`. Paths above are relative to that root.
- Follow ADR 0003: read `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (ms), default 60000, convert to seconds, floor at 60s. Apply to initialize control request wait (and optionally shared control waits if consistent).
- No API signature changes; use env-based override. Keep defaults unchanged when env absent.

# TDD Expectations
1. Add tests first:
   - Env parsing helper: missing/invalid/low/high values -> expected seconds with floor.
   - Initialize/control wait uses env-derived timeout (mock slow response to assert override is applied).
2. Implement code to satisfy tests.
3. Run relevant tests and note outcomes.

# Acceptance Criteria
- Env parsing implemented with correct default (60s), floor, and conversion from ms.
- Initialize control request uses derived timeout; behavior unchanged when env not set.
- Tests cover parsing and application; all pass.
- Documentation: brief note in README/ops about `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` and its purpose (slow MCP/server startups).
