# Prompt 02 - Query/CLI/API Parity (P1)

You are the next agent working in this repo. This is the second prompt in a sequential series. Focus on API and CLI parity gaps. Use TDD. Do NOT bump the version yet; that happens in Prompt 03.

Global requirements (apply across all prompts)
- Use TDD: write failing tests first, then implement, then refactor.
- Update docs for changes you make (README + all relevant `guides/*.md`).
- Update examples affected by behavior changes.
- All tests must pass; no warnings; no errors; no Credo or Dialyzer issues.

Required reading (docs)
- `docs/20251229/python_elixir_parity/gap_analysis.md`
- `docs/20251229/python_elixir_parity/parity_matrix.md`
- `docs/20251229/python_elixir_parity/remediation_plan.md`

Required reading (Python canonical reference)
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/query.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/client.py`
- `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py`

Required reading (Elixir implementation)
- `lib/claude_agent_sdk.ex`
- `lib/claude_agent_sdk/query.ex`
- `lib/claude_agent_sdk/process.ex`
- `lib/claude_agent_sdk/transport/port.ex`
- `lib/claude_agent_sdk/streaming/session.ex`
- `lib/claude_agent_sdk/options.ex`
- `lib/claude_agent_sdk/client.ex`
- `lib/claude_agent_sdk/cli.ex`

Scope for this prompt (gaps to close)
- G-003: can_use_tool validation + auto `permission_prompt_tool`.
- G-004: honor CLI path override from options (`cli_path` equivalent).
- G-007: non-control query should stream; eliminate full-buffer execution.
- G-008: query should accept stream/Enumerable prompts and optional transport injection.
- G-009: `--replay-user-messages` should be opt-in, not always on.
- G-010: wire `stderr` callback in Process and Streaming Session.
- G-017: allow `mcp_servers` to be JSON/path (alias to `mcp_config`).
- G-018: extra_args boolean behavior should match Python (true => flag only, false => omit).
- G-022: provide a streaming `receive_response` equivalent (non-blocking stream until result).
- G-021: differentiate `CLAUDE_CODE_ENTRYPOINT` for client vs query (set `sdk-elixir-client` in Client context).

TDD plan (high level)
1) Add tests for each gap with current behavior failing.
2) Implement minimal changes to pass tests.
3) Refactor carefully and update docs/examples.

Implementation tasks
1) can_use_tool validation + auto permission prompt
- Enforce Python rules: can_use_tool requires streaming prompt and cannot be combined with permission_prompt_tool.
- Auto-set permission_prompt_tool to "stdio" for control protocol.
- Implement in `ClaudeAgentSDK.query/2` / `Query.run` and `Client` start.

2) CLI path override
- Thread `path_to_claude_code_executable` / `executable` through CLI resolution in Process/Port/Streaming/Client.
- Align naming with Python `cli_path` or document mapping in README/guides.

3) Query streaming and AsyncIterable
- Add `ClaudeAgentSDK.query/2` overload for `Enumerable` prompts that streams to CLI stdin and yields responses as they arrive (unidirectional streaming).
- Add optional transport injection similar to Python `query(..., transport=...)` or document explicit alternative.
- Remove full-buffer sync use for streaming mode; use Port transport or a streaming erlexec.

4) replay-user-messages flag
- Only add `--replay-user-messages` when explicitly requested via `extra_args` or when needed for file checkpointing flows.

5) stderr callback in Process and Streaming Session
- Route non-JSON stderr lines to `options.stderr` in those modules, consistent with Port.

6) MCP config API
- Allow `mcp_servers` option to accept JSON string or file path (alias to `mcp_config`).
- Document in README + guides.

7) extra_args boolean semantics
- Match Python: `nil` or `true` should emit `--flag` only; `false` should omit flag.

8) receive_response streaming
- Add `receive_response_stream/1` that yields messages until result, keeping existing `receive_response/1` for compatibility.

9) client entrypoint env
- Set `CLAUDE_CODE_ENTRYPOINT` to `sdk-elixir-client` (or similar) when using Client transport, leaving `sdk-elixir` for query/streaming.

Docs and examples
- Update README and relevant guides for new API forms, CLI path configuration, streaming behavior, and stderr callback.
- Update any examples that depended on replay-user-messages or output format behavior.

Quality gates
- Run `mix test`.
- Run `mix credo --strict`.
- Run `mix dialyzer`.
- No warnings or failures.

Hand-off notes
- Summarize changes and any follow-ups for Prompt 03.
- Do not bump version; that is done in Prompt 03.
