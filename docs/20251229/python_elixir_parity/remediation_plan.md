# Remediation Plan to Reach 100% Parity

Goal: Align Elixir behavior with the canonical Python SDK (v0.1.18) while keeping Elixir-only conveniences opt-in and non-breaking.

Principles
- Protocol correctness first (control protocol and stream-json parsing).
- Preserve backward compatibility where possible; add warnings when behavior changes.
- Add tests for every corrected gap using mock transport and recorded fixtures.

Phase 0: Protocol correctness (P0)
Target gaps: G-001, G-002, G-006, G-012, G-013

1) Fix permission response shape
- Change `encode_permission_response/4` to place data under `response` not `result`.
- Files: `lib/claude_agent_sdk/client.ex`
- Tests: add control protocol round-trip test in `test/` using mock control request.

2) Enforce stream-json output format for SDK flows
- For query/client/streaming, ignore `output_format` when it is not stream-json and either:
  - override to stream-json with warning, or
  - raise on unsupported output formats in SDK flows.
- Keep `--json-schema` when `output_format` is structured.
- Files: `lib/claude_agent_sdk/process.ex`, `lib/claude_agent_sdk/client.ex`, `lib/claude_agent_sdk/streaming/session.ex`, `lib/claude_agent_sdk/options.ex`
- Tests: ensure options with `output_format: :json` do not break streaming parsing.

3) MCP tool error semantics and naming
- Normalize tool results so errors return a successful JSONRPC result with `is_error` and content, matching Python.
- Accept `isError` input from tool modules but emit `is_error` in JSONRPC response.
- Avoid returning JSONRPC error for tool execution failures unless the MCP protocol itself fails.
- Files: `lib/claude_agent_sdk/tool/registry.ex`, `lib/claude_agent_sdk/client.ex`, `lib/claude_agent_sdk/tool.ex` (docs)
- Tests: MCP tools/call with success, tool error, and runtime exception.

4) Hook matcher timeout units
- Treat timeout inputs as seconds (float or integer) to match Python.
- Provide backward-compat path: accept `timeout_ms` but convert to seconds if explicitly tagged or add a new field `timeout_seconds`.
- Files: `lib/claude_agent_sdk/hooks/matcher.ex`, `lib/claude_agent_sdk/client.ex`
- Tests: verify CLI payload uses seconds and that timeouts behave correctly.

5) MCP initialize metadata
- Use configured server name/version in `initialize` responses and do not hardcode `1.0.0`.
- Files: `lib/claude_agent_sdk/client.ex`
- Tests: MCP initialize returns matching `serverInfo` from options.

Phase 1: API parity and CLI integration (P1)
Target gaps: G-003, G-004, G-007, G-008, G-009, G-010, G-017, G-018, G-022, G-021

6) can_use_tool validation and auto permission prompt
- Enforce the Python rules: can_use_tool requires streaming prompt and cannot be combined with permission_prompt_tool.
- Auto-set `permission_prompt_tool` to "stdio" when can_use_tool is used.
- Files: `lib/claude_agent_sdk/query.ex`, `lib/claude_agent_sdk/client.ex`, `lib/claude_agent_sdk/options.ex`
- Tests: invalid config raises; correct config auto-sets prompt tool.

7) CLI path override and executable support
- Thread `cli_path` (or equivalent) through all launch points: Process, Port, Streaming Session, Client.
- Either rename to match Python (`cli_path`) or make existing fields functional and document mapping.
- Files: `lib/claude_agent_sdk/cli.ex`, `lib/claude_agent_sdk/process.ex`, `lib/claude_agent_sdk/transport/port.ex`, `lib/claude_agent_sdk/streaming/session.ex`, `lib/claude_agent_sdk/client.ex`
- Tests: custom path is used; error messaging reflects it.

8) Unidirectional streaming query support
- Add `ClaudeAgentSDK.query/2` overload to accept `Enumerable` prompts and stream results as they arrive.
- Provide a transport argument (module or instance) similar to Python `query(..., transport=...)`.
- Files: `lib/claude_agent_sdk.ex`, `lib/claude_agent_sdk/query.ex`, new helper module if needed.
- Tests: mock transport streaming input/output.

9) Real-time streaming for non-control query
- Replace erlexec sync buffering with streaming line-by-line parsing, or route query through Port transport when no control features are needed.
- Files: `lib/claude_agent_sdk/process.ex`, `lib/claude_agent_sdk/query.ex`
- Tests: messages arrive before process exit.

10) Make `--replay-user-messages` opt-in
- Only add this flag when explicitly requested via `extra_args` or when file checkpointing requires it.
- Files: `lib/claude_agent_sdk/client.ex`, `lib/claude_agent_sdk/transport/port.ex`, `lib/claude_agent_sdk/streaming/session.ex`
- Tests: user messages only present when flag enabled.

11) Wire stderr callbacks in all modes
- Deliver stderr lines to `options.stderr` in Process and Streaming Session, matching Python.
- Files: `lib/claude_agent_sdk/process.ex`, `lib/claude_agent_sdk/streaming/session.ex`
- Tests: stderr callback fires on non-JSON lines.

12) Align MCP config API and extra_args semantics
- Allow `mcp_servers` to accept a JSON string or file path (alias to `mcp_config`).
- Treat `extra_args` booleans like Python: `true` emits flag only, `false` omits.
- Files: `lib/claude_agent_sdk/options.ex`
- Tests: CLI args match Python behavior for booleans and mcp config.

13) Client receive_response streaming variant
- Add `receive_response_stream/1` that yields messages until result, mirroring Python.
- Keep existing list-returning version for backward compat.
- Files: `lib/claude_agent_sdk/client.ex`
- Tests: streaming iterator stops on result.

14) Distinct entrypoint env for client
- Set `CLAUDE_CODE_ENTRYPOINT` to `sdk-elixir-client` (or similar) when using Client, leaving `sdk-elixir` for query.
- Files: `lib/claude_agent_sdk/transport/port.ex`, `lib/claude_agent_sdk/process.ex`, `lib/claude_agent_sdk/streaming/session.ex`
- Tests: env values differ between query and client.

Phase 2: Hardening and divergence cleanup (P2)
Target gaps: G-011, G-014, G-015, G-016, G-020

15) Enforce max_buffer_size
- Add buffer limit and raise a CLIJSONDecodeError when exceeded, matching Python.
- Files: `lib/claude_agent_sdk/transport/port.ex`, `lib/claude_agent_sdk/process.ex`
- Tests: oversized line triggers error.

16) MCP method parity
- Change `resources/list` and `prompts/list` to return method-not-found errors (or make this behavior configurable).
- Files: `lib/claude_agent_sdk/client.ex`
- Tests: MCP method errors match Python.

17) Remove atom conversion for tool names
- Store and dispatch MCP tool names as strings; avoid `String.to_atom`.
- Files: `lib/claude_agent_sdk/tool/registry.ex`, `lib/claude_agent_sdk/client.ex`
- Tests: tools with unknown names do not create atoms.

18) Message parsing robustness
- Avoid `String.to_atom` for `type`/`subtype`; preserve unknown subtypes as strings.
- Files: `lib/claude_agent_sdk/message.ex`
- Tests: unknown result subtype does not crash.

19) Hook event parity
- Gate `SessionStart`, `SessionEnd`, and `Notification` hooks behind a feature flag or emit warnings to align with Python support.
- Files: `lib/claude_agent_sdk/hooks/hooks.ex`
- Tests: configuring unsupported hooks returns warning.

Validation plan
- Unit tests for options serialization, control protocol encoding/decoding, and message parsing.
- MCP tool tests: success, tool error with `is_error`, runtime exception.
- Integration tests with mock transport for streaming and permission callbacks.
- Optional live CLI tests gated behind env flag (as already used in this repo).

Success criteria
- All gap IDs resolved or explicitly documented as intentional divergence.
- CLI-compatible outputs remain stream-json across SDK flows.
- Control protocol requests/responses match Python payload shapes.
