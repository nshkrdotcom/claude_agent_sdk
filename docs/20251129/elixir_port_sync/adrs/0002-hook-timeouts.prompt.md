# Task
Implement ADR 0002 (Hook Matcher Timeouts and Callback Boundaries) using TDD.

# Required Reading (read first)
- `docs/20251129/elixir_port_sync/adrs/0002-hook-timeouts.md`
- Hook definitions and matcher struct: `lib/claude_agent_sdk/hooks/matcher.ex`
- Hook registry/build pipeline: `lib/claude_agent_sdk/client.ex` (build_hooks_config/2, handle_hook_callback/3, registry usage)
- Control protocol initialization encoding: `lib/claude_agent_sdk/control_protocol/protocol.ex`
- Permission/hook timeout handling references in tests (search in `test/claude_agent_sdk/*` and `test/support`)

# Constraints / Alignment
- Root of repo is `../`. Paths above are relative to that root.
- Follow ADR 0002: add optional per-matcher timeout, serialize into initialize payload as `"timeout"`, and use it to bound hook callback `Task.yield` with default 60s and a floor (>0).
- Maintain backward compatibility for users not setting timeouts.
- Do not conflate with permission callback timeouts unless minimally required; focus on hook matchers.

# TDD Expectations
1. Add/extend tests first:
   - Matcher serialization includes timeout when set.
   - Client uses matcher timeout to bound hook callback execution (simulate slow hook; expect timeout error string).
   - Default still 60s when unset; floor respected for small/invalid values.
2. Implement code to satisfy tests.
3. Run relevant tests and record results.

# Acceptance Criteria
- `Hooks.Matcher` supports timeout field and constructor opts; initialize payload includes `"timeout"` when present.
- Hook callback execution respects matcher-specific timeout (or default) and returns timeout error string consistent with existing patterns.
- Defaults/floor are enforced; existing behavior untouched when timeout absent.
- Tests cover serialization and runtime timeout behavior; all pass.
- Documentation: brief addition to hooks documentation/README describing the timeout option and defaults.
