# Task
Implement ADR 0001 (Structured Outputs Parity with Python SDK 0.1.10) using TDD.

# Required Reading (read first)
- `docs/20251129/elixir_port_sync/adrs/0001-structured-outputs.md`
- `lib/claude_agent_sdk/options.ex`
- `lib/claude_agent_sdk/message.ex`
- `lib/claude_agent_sdk/streaming/event_parser.ex`
- `lib/claude_agent_sdk/content_extractor.ex` (to ensure compatibility/behavior)
- `lib/claude_agent_sdk/option_builder.ex` (docs alignment for output_format presets)
- Any existing tests touching options or parsing:
  - `test/claude_agent_sdk/options_test.exs` (if present)
  - `test/claude_agent_sdk/message_test.exs`
  - `test/claude_agent_sdk/streaming/event_parser_test.exs`
  - `test/support` helpers for parsing/mocks

# Constraints / Alignment
- Root of repo is `../`. Paths above are relative to that root.
- Follow ADR 0001 exactly: add structured output_format (`{:json_schema, map}` or `%{type: :json_schema | "json_schema", schema: map}`), emit `--json-schema`, parse `structured_output` on results/streaming, keep stream-json + verbose behavior.
- Breaking change acceptable; prioritize parity with Python.
- No bundled CLI work (ADR 0003 covers env timeout; ADR 0002 covers hook timeouts; ADR 0004 covers assistant errors separately).

# TDD Expectations
1. Add/adjust tests first to describe desired behavior (options arg generation, message parsing, streaming event capture, content extractor passthrough). Prefer unit tests; add a mock/integration test for structured_output presence.
2. Implement code to satisfy tests.
3. Run relevant test suites and note results/remaining gaps.

# Acceptance Criteria
- Options: `output_format` accepts structured config; `Options.to_args/1` emits `--json-schema <schema-json>` and preserves `--output-format stream-json --verbose` behavior.
- Parsing: `Message` captures `structured_output` in result data; streaming parser surfaces structured output on final event (message_stop or synthetic result) without breaking existing text/tool events.
- ContentExtractor (or equivalent helper) handles structured outputs gracefully (documented behavior: passthrough or accessor).
- Tests cover: option arg emission, parsing with structured_output present/missing, streaming event parsing, and extractor behavior. Tests pass.
- Docs update: brief README/OptionBuilder note for structured output usage with schema example and CLI version note (consistent with ADR).
