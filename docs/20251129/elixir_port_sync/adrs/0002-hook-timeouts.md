# ADR 0002: Hook Matcher Timeouts and Callback Boundaries

- **Status:** Proposed
- **Date:** 2025-11-29
- **Owner:** SDK team

## Context
- Python 0.1.10 adds per-matcher `timeout` that flows through initialize and affects hook execution timing; it also keeps a 60s default Task timeout for callbacks.
- Elixir hooks currently lack per-matcher timeout metadata; callbacks are hardcoded to a 60s `Task.yield`.
- We need parity so long-running hooks can be tuned and the CLI receives timeout hints during initialize.

## Decision
- Add optional `timeout_ms` (or seconds) on `ClaudeAgentSDK.Hooks.Matcher` and include it in initialize payloads.
- Use the matcher timeout to bound hook callback `Task.yield`; fallback to a 60s default.
- Keep a floor (e.g., 1s) to avoid accidental zero/negative timeouts.

## Rationale
- Matches Python semantics and allows slow hooks (e.g., MCP servers) to run without premature failures.
- Centralizes timeout configuration per matcher instead of a global knob, aligning with upstream design.

## Consequences
- Slightly wider matcher struct; existing code without timeouts remains unchanged.
- If a user sets very high timeouts, stalled hooks may block longer; we rely on explicit configuration.
- Initialize payload changes: adds `"timeout"` per matcher; requires CLI versions that ignore/accept this field gracefully (Python CLI already does).

## Implementation Plan
1) **Data model**
   - Add `timeout_ms` (or seconds) field to `Hooks.Matcher` struct with type spec; constructor `Matcher.new/2` accepts an opts keyword for timeout.
2) **Initialize wiring**
   - In `Client.build_hooks_config/2`, include `"timeout"` when present.
   - Ensure control protocol encoder stays compatible with existing CLI (extra fields should be ignored upstream).
3) **Execution**
   - In `Client.handle_hook_callback/3`, derive the timeout for the matched callback(s); use matcher timeout else default 60s. (If multiple matchers apply, pick the first-matched or max—choose and document.)
   - Mirror behavior for permission callbacks only if we later add a global knob (out-of-scope for now).
4) **Tests**
   - Unit: matcher serializes timeout; callback Task honors configured timeout.
   - Integration mock: simulate a slow hook and assert timeout error message matches expectation.
5) **Docs**
   - Add to README/hooks guide: how to set per-matcher timeout and defaults.

## Alternatives Considered
- Global hook timeout only — rejected; less flexible and diverges from Python.
- Per-callback timeout — overkill for now; matcher-level is sufficient and aligned.

## Rollout
- Ship alongside structured outputs to keep protocol changes together.
- Document the default (60s) and the floor, and warn that very low values may cause spurious timeouts.
