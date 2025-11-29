# Task
Implement ADR 0004 (Assistant Error Field and Enum Parity) using TDD.

# Required Reading (read first)
- `docs/20251129/elixir_port_sync/adrs/0004-assistant-errors.md`
- Message parsing/structs: `lib/claude_agent_sdk/message.ex`
- Streaming parser (if assistant errors surface via streaming): `lib/claude_agent_sdk/streaming/event_parser.ex`
- Any helper modules that expose assistant/message types to consumers (`lib/claude_agent_sdk/content_extractor.ex`, etc.)
- Existing tests around message parsing/streaming (`test/claude_agent_sdk/message_test.exs`, `test/claude_agent_sdk/streaming/event_parser_test.exs`, and related support files).

# Constraints / Alignment
- Root of repo is `../`. Paths above are relative to that root.
- Follow ADR 0004: add optional `error` field to assistant messages, with enum matching Python (`authentication_failed`, `billing_error`, `rate_limit`, `invalid_request`, `server_error`, `unknown`).
- Backward compatible when field absent.

# TDD Expectations
1. Add tests first:
   - Parsing assistant JSON with/without `error` yields correct struct and enum value.
   - Streaming path (if applicable) preserves the `error` field on assistant/message_stop frames.
2. Implement code to satisfy tests.
3. Run relevant tests and capture results.

# Acceptance Criteria
- Assistant message struct/type includes optional `error` with the specified enum values.
- Parsers copy `error` through; streaming path does not drop it.
- Tests cover presence/absence and enum enforcement; all pass.
- Docs mention the new field and sample handling (e.g., rate-limit UI).
