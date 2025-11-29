# ADR 0001: Structured Outputs Parity with Python SDK 0.1.10

- **Status:** Proposed
- **Date:** 2025-11-29
- **Owner:** SDK team

## Context
- Python 0.1.10 supports structured outputs via `output_format={"type": "json_schema", "schema": ...}` and surfaces validated data on `ResultMessage.structured_output`.
- Elixir currently only supports `:text | :json | :stream_json` and discards structured payloads. Event parsers don’t surface structured content, and Options don’t emit `--json-schema`.
- We need parity so Elixir users can request and consume validated JSON.

## Decision
- Extend `ClaudeAgentSDK.Options.output_format` to accept structured output configuration and emit the `--json-schema` CLI flag.
- Parse `structured_output` from result frames (and streaming message_stop if present) into Elixir message structs.
- Introduce a breaking but aligned shape: `output_format: {:json_schema, map()} | %{type: :json_schema | "json_schema", schema: map()}`. Anything else remains backward compatible.
- Document usage and add tests (unit + mock/integration) before release.

## Rationale
- Aligns with Python feature set and CLI capabilities.
- Keeps API clear: explicit constructors for structured outputs; minimal ambiguity with old atoms.
- Allows users to rely on CLI validation instead of manual decoding.

## Consequences
- **Breaking API:** Existing `output_format` type spec widens; validation must reject unsupported tuples/maps to avoid silent failures.
- CLI dependency: requires a CLI version that supports `--json-schema`; we will warn if detected CLI is too old (but not block for now).
- Parsers must preserve existing behavior for non-structured flows.

## Implementation Plan
1) **Options / CLI args**
   - Update `ClaudeAgentSDK.Options` type + docs to allow structured config.
   - In `Options.to_args/1`, when `json_schema` variant present, append `--json-schema <schema-json>`; ensure `--output-format stream-json --verbose` stays intact.
2) **Parsing**
   - `ClaudeAgentSDK.Message`: include `structured_output` in `result` data maps.
   - `Streaming.EventParser`: when encountering a `message_stop` or result payload that includes `structured_output`, emit it on the final event or attach to a synthetic result frame.
3) **Content helpers**
   - Ensure `ContentExtractor` handles structured payloads gracefully (likely a passthrough).
4) **Tests**
   - Unit: Options emits `--json-schema`; Message.parse handles result JSON with `structured_output`.
   - Mock integration: feed a mock `result` JSON containing `structured_output` and assert the data is present.
   - Optional live e2e (behind env flag) mirroring Python’s structured-output tests.
5) **Docs**
   - README section with a minimal schema example and note on CLI version expectations.
   - Migration note describing the new `output_format` shape.

## Alternatives Considered
- Accept raw `output_format: map()` and detect `schema` implicitly — rejected to avoid ambiguity and to mirror Python’s explicit `type`.
- Auto-detect structured outputs from responses without explicit `--json-schema` — rejected; upstream expects the flag.

## Rollout
- Ship in the next Elixir release after tests land.
- Add a CLI-version warning (not a hard block) when `json_schema` is requested but CLI is older than the minimum version that supports it.
