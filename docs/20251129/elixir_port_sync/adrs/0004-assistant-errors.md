# ADR 0004: Assistant Error Field and Enum Parity

- **Status:** Proposed
- **Date:** 2025-11-29
- **Owner:** SDK team

## Context
- Python 0.1.10 added `AssistantMessage.error` with an enum of CLI-surfaced error types (`authentication_failed`, `billing_error`, `rate_limit`, `invalid_request`, `server_error`, `unknown`).
- Elixir currently does not expose an error discriminator on assistant messages; errors are only reflected in result frames or logs.
- For parity and better UI signaling, assistant frames should carry this optional error code.

## Decision
- Introduce an optional `error` field on Elixir assistant messages, with a fixed enum matching Python’s set.
- Parse and propagate this field in message decoding and streaming event handling.
- Keep backward compatibility: absence of the field yields `nil`.

## Rationale
- Aligns with Python semantics and improves client UX (e.g., can render auth vs. rate-limit errors distinctly).
- Minimal surface-area change; non-breaking to existing consumers who ignore the field.

## Consequences
- Slightly wider message struct and type spec; downstream code may optionally pattern-match on `error`.
- Requires parsing updates; test coverage must include assistant frames with `error`.

## Implementation Plan
1) **Types/structs**
   - Add `error` field to the assistant message struct/type (where assistant messages are represented).
   - Define an atom/string enum for the known error codes.
2) **Parsing**
   - Update message parsing to copy `error` when present.
   - If streaming events carry the error on message stop (as in Python control flow), ensure it’s preserved.
3) **Tests**
   - Unit: parse assistant JSON with/without `error` and assert the enum value.
   - Integration mock: feed a stream including an assistant error and ensure downstream sees it.
4) **Docs**
   - Note the field in message type docs and give example handling (e.g., show a retry prompt on `rate_limit`).

## Alternatives Considered
- Expose only in result frames — rejected; assistant-level errors are useful for mid-stream handling.
- Free-form string errors — rejected to maintain a stable enum aligned with Python.

## Rollout
- Ship with the structured outputs release; no migration required for existing users, but highlight the new field in the changelog.
