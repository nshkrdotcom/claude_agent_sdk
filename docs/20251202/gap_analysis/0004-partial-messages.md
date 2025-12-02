# ADR 0004 — `include_partial_messages` not honoured in `query/2`

- Status: Proposed
- Date: 2025-12-02

## Context
- Python’s `query()` supports incremental output via `include_partial_messages`; the transport sets the flag and `parse_message` emits `StreamEvent` objects (`anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py:201-259` and `_internal/message_parser.py:159-166`).
- Elixir still routes `ClaudeAgentSDK.query/2` to the synchronous `Process` runner unless control features are present (`lib/claude_agent_sdk/query.ex:51-60`), and the transport selector ignores `include_partial_messages` (`lib/claude_agent_sdk/transport/streaming_router.ex:96-112`). The `Message`/`Process` parsers don’t recognize `stream_event` frames and fall back to plain assistant text (`lib/claude_agent_sdk/message.ex:70-85`, `lib/claude_agent_sdk/process.ex:439-505`).

## Gap
- Setting `include_partial_messages: true` on `query/2`, `continue/2`, or `resume/3` drops incremental updates instead of yielding streaming events, unlike Python.

## Consequences
- Callers cannot implement typewriter/progress UIs or early-cancel behaviours with the simple `query` API; only the bespoke `Streaming` module works.

## Recommendation
- Treat `include_partial_messages` as a control-feature trigger (route through the control client or streaming session parser), and extend message parsing to emit structured stream-event frames so `query/2` matches Python’s incremental behaviour.
