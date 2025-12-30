# Prompt 01 - Protocol Parity (P0)

You are the next agent working in this repo. Goal: close the highest-risk parity gaps with the Python canonical SDK. Use TDD. Keep changes minimal and compatibility-safe. This is the first of multiple sequential prompts. Do NOT bump the version yet; that happens in Prompt 03.

Global requirements (apply across all prompts)
- Use TDD: write failing tests first, then implement, then refactor.
- Update docs for changes you make (README + relevant `guides/*.md`).
- Update examples affected by behavior changes.
- All tests must pass; no warnings; no errors; no Credo or Dialyzer issues.

Required reading (docs)
- `docs/20251229/python_elixir_parity/gap_analysis.md`
- `docs/20251229/python_elixir_parity/parity_matrix.md`
- `docs/20251229/python_elixir_parity/remediation_plan.md`
- Any relevant design docs you touch under `docs/` and `guides/`.

Required reading (Python canonical reference)
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/message_parser.py`

Required reading (Elixir implementation)
- `lib/claude_agent_sdk/client.ex`
- `lib/claude_agent_sdk/control_protocol/protocol.ex`
- `lib/claude_agent_sdk/hooks/matcher.ex`
- `lib/claude_agent_sdk/options.ex`
- `lib/claude_agent_sdk/tool.ex`
- `lib/claude_agent_sdk/tool/registry.ex`
- `lib/claude_agent_sdk/message.ex`

Scope for this prompt (gaps to close)
- G-001: control protocol permission response shape should use `response` (not `result`).
- G-002: hook matcher timeout units (Python uses seconds; Elixir currently uses ms).
- G-006: enforce `--output-format stream-json` for SDK flows even when `output_format` is set (structured output should still pass `--json-schema`).
- G-012: MCP tool error semantics and `is_error` naming; do not return JSONRPC error for tool execution failure; emit `is_error` in result payload.
- G-013: MCP `initialize` response should reflect configured server name/version (not hardcoded alias + `1.0.0`).

Do NOT address other gaps yet; they are handled in later prompts.

TDD plan (high level)
1) Add tests that fail on current behavior.
2) Implement minimal fixes to make tests pass.
3) Refactor carefully with no behavior changes beyond the gaps.

Test targets (suggested)
- Add unit tests around control protocol encoding and decode logic used in `Client`.
- Add MCP tool tests around tools/list and tools/call.
- Add tests around CLI arg formation when output_format is set.
- Add tests for hook timeout units in initialization payload.

Implementation tasks
1) Permission response shape
- Update `encode_permission_response/4` in `lib/claude_agent_sdk/client.ex` to emit:
  - `{"type": "control_response", "response": {"subtype": "success", "request_id": ..., "response": <payload>}}`
  - This must match Python `_internal/query.py`.

2) Hook matcher timeout units
- Change matcher timeout to seconds. Options:
  - Add a new field `timeout_seconds` and deprecate `timeout_ms`, or
  - Convert `timeout_ms` to seconds when constructing the control payload.
- Ensure CLI payload uses `timeout` in seconds (float allowed) like Python.

3) Output format enforcement
- Ensure SDK flows always emit `--output-format stream-json` for CLI output to keep parsing stable.
- Preserve `--json-schema` usage for structured outputs (same as Python).
- Do not allow user `output_format` to break stream-json parsing.

4) MCP tool error semantics
- Normalize tool output from `Tool.Registry` to match Python response:
  - Always return JSONRPC success with `result` containing `content` and optional `is_error`.
  - If a tool errors, set `is_error: true` in the result, not JSONRPC error.
- Normalize naming from `isError` to `is_error` in JSONRPC response.

5) MCP initialize metadata
- Use configured server `name` and `version` from options when responding to `initialize`.

Docs and examples
- Update README and relevant `guides/*.md` to document any observable behavior changes (permission response shape is internal; output format enforcement is external).
- Update examples if they rely on previous `output_format` or tool error behavior.

Quality gates
- Run `mix test`.
- Run `mix credo --strict`.
- Run `mix dialyzer`.
- No warnings or failures.

Deliverables
- Code changes implementing the above.
- Updated docs and examples.
- Updated tests.

Hand-off notes
- Summarize changes and any follow-ups for Prompt 02 and Prompt 03.
- Do not bump version; that is done in Prompt 03.
