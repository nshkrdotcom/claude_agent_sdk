# Prompt 03 - Hardening, Docs, Release (P2)

You are the next agent working in this repo. This is the final prompt in a sequential series. Focus on hardening, remaining gaps, and release updates. Use TDD. This is the prompt that bumps the version to 0.7.2.

Global requirements (apply across all prompts)
- Use TDD: write failing tests first, then implement, then refactor.
- Update docs for changes you make (README + all `guides/*.md`).
- Update examples affected by behavior changes.
- All tests must pass; no warnings; no errors; no Credo or Dialyzer issues.

Required reading (docs)
- `docs/20251229/python_elixir_parity/gap_analysis.md`
- `docs/20251229/python_elixir_parity/parity_matrix.md`
- `docs/20251229/python_elixir_parity/remediation_plan.md`
- All `guides/*.md` (you will update them).

Required reading (Python canonical reference)
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/message_parser.py`

Required reading (Elixir implementation)
- `lib/claude_agent_sdk/message.ex`
- `lib/claude_agent_sdk/client.ex`
- `lib/claude_agent_sdk/transport/port.ex`
- `lib/claude_agent_sdk/process.ex`
- `lib/claude_agent_sdk/hooks/hooks.ex`
- `lib/claude_agent_sdk/tool/registry.ex`

Scope for this prompt (gaps to close)
- G-011: enforce max_buffer_size (hard limit) and surface CLIJSONDecodeError on overflow.
- G-014: MCP methods `resources/list` and `prompts/list` should return method-not-found errors (match Python).
- G-015: avoid `String.to_atom` for MCP tool names; keep string keys.
- G-016: message parsing should not crash or create atoms for unknown `type`/`subtype`.
- G-020: handle unsupported hook events (SessionStart, SessionEnd, Notification) to match Python.
- Also resolve any remaining gaps from previous prompts and reconcile docs.

TDD plan (high level)
1) Add failing tests for each remaining gap.
2) Implement fixes with minimal behavior change.
3) Refactor and update docs/examples.

Implementation tasks
1) max_buffer_size enforcement
- Add buffer length tracking in Port/Process and raise a CLIJSONDecodeError (or equivalent error message) once the limit is exceeded.

2) MCP method parity
- Update MCP dispatcher to return JSONRPC method-not-found for `resources/list` and `prompts/list`.

3) Tool name handling
- Keep MCP tool names as strings; update registry to use string keys.
- Ensure tools/call works without atom conversion.

4) Message parsing robustness
- Avoid `String.to_atom` on unknown `type`/`subtype`.
- Store unknown subtypes as strings and avoid atom leakage.

5) Hook event parity
- Gate unsupported hook events (SessionStart/SessionEnd/Notification) with warnings or reject them during validation, matching Python behavior.

6) Docs and examples
- Update README and all `guides/*.md` to reflect the final, correct behavior.
- Update or add examples to match the new semantics (buffer limits, MCP behavior, hook events).

7) Version bump (release prep)
- Bump version to `0.7.2` in:
  - `mix.exs`
  - `README.md`
  - `CHANGELOG.md` (add entry dated 2025-12-29 with summary)

Quality gates
- Run `mix test`.
- Run `mix credo --strict`.
- Run `mix dialyzer`.
- No warnings or failures.

Final checklist
- All gaps in `docs/20251229/python_elixir_parity/gap_analysis.md` are resolved or explicitly documented as intentional divergences.
- README and guides updated.
- Examples updated and passing.
- Version bumped to 0.7.2 with changelog entry.
