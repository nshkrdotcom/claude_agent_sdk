# ADR 0003: Initialize Timeout via Environment Override

- **Status:** Proposed
- **Date:** 2025-11-29
- **Owner:** SDK team

## Context
- Python 0.1.10 reads `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (ms) to set a longer timeout for the initialize control request, floored at 60s, to handle slow MCP/server startups.
- Elixir initialize/control waits are implicit; no env-based override exists, so slow startups can time out.
- We need parity and an operator-friendly knob without API changes.

## Decision
- Honor `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (milliseconds) in the Elixir client when waiting for initialize/control responses.
- Convert to seconds, apply a minimum of 60s, and use this timeout in the control-request wait path (initialize at minimum; optionally reuse for other control calls).
- Expose a private helper for testability; document the env var in README/docs.

## Rationale
- Matches Python behavior and provides a non-breaking operational override.
- Avoids changing public function signatures; relies on environment for rare long-start cases.

## Consequences
- Longer waits possible if operators set high values; risk of hanging is explicit and opt-in.
- Tests must cover env parsing and floor logic.

## Implementation Plan
1) **Config parsing**
   - Add a helper to read `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (ms), default 60000, floor to 60s; convert to seconds float.
2) **Client wiring**
   - Use the derived timeout in initialize control request wait (and optionally other control requests for consistency).
   - Ensure default behavior stays 60s when env not set.
3) **Tests**
   - Unit: env parsing with various values (missing, small, large, non-numeric).
   - Integration: simulate slow initialize in mock transport and assert timeout uses env override.
4) **Docs**
   - Note the env var in README/operational docs; explain it’s for slow MCP/server startups.

## Alternatives Considered
- Adding an `Options` field for initialize timeout — rejected for now to minimize API churn; env keeps parity with Python’s approach.
- Applying override to all control requests — we’ll start with initialize, then decide if a global application is desired.

## Rollout
- Ship with the structured outputs/hook timeout release; announce the env knob and default floor.
