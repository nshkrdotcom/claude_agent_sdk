# Python vs Elixir SDK Gap Analysis (Deep)

Date: 2025-12-29
Python reference: anthropics/claude-agent-sdk-python v0.1.18
Elixir target: repo root (claude_agent_sdk v0.7.2)

Scope
- Canonical behavior derived from the Python SDK code in `anthropics/claude-agent-sdk-python`.
- Elixir implementation reviewed in `lib/` plus transport and streaming modules.
- Focus areas: public API parity, CLI invocation/flags, control protocol, MCP SDK servers, hooks, permissions, message parsing, and streaming.

Summary
- Critical gaps: 3
- High gaps: 8
- Medium gaps: 8
- Low gaps: 4

Status Update (v0.7.2)
- Resolved: All gaps listed below are addressed in `claude_agent_sdk` v0.7.2, including G-011/G-014/G-015/G-016/G-020.
- Intentional divergence: G-005 (CLI bundling) remains a documented difference; the Elixir SDK does not ship a bundled CLI binary.
- Compatibility note: G-022 is satisfied via `Client.receive_response_stream/1` while retaining the list-returning `receive_response/1` for backward compatibility.

Most impactful mismatches
- Control protocol permission response shape (G-001)
- Output format handling can break stream-json parsing (G-006)
- MCP tool error semantics and is_error naming mismatch (G-012)
- Non-control query is not streaming and lacks AsyncIterable input (G-007, G-008)

Gap list
ID | Severity | Area | Python reference | Elixir reference | Summary
---|---|---|---|---|---
G-001 | Critical | Control protocol | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py` | `lib/claude_agent_sdk/client.ex` | Permission responses use `response` in Python but Elixir encodes `result`.
G-002 | High | Hooks | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py` | `lib/claude_agent_sdk/hooks/matcher.ex` | Hook matcher `timeout` is seconds in Python; Elixir uses `timeout_ms` and forwards ms.
G-003 | High | Permissions | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/client.py` | `lib/claude_agent_sdk/client.ex`, `lib/claude_agent_sdk/options.ex` | Python enforces `can_use_tool` streaming + mutual exclusion with permission prompt; Elixir does not and does not auto-set `permission_prompt_tool`.
G-004 | High | CLI discovery | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py` | `lib/claude_agent_sdk/cli.ex`, `lib/claude_agent_sdk/process.ex` | `cli_path` override honored in Python; Elixir options `path_to_claude_code_executable`/`executable` are unused.
G-005 | Medium | CLI bundling | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_bundled` | `lib/claude_agent_sdk/cli.ex` | Python bundles a CLI binary; Elixir does not ship `_bundled` and only checks for one.
G-006 | Critical | Output format | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py` | `lib/claude_agent_sdk/options.ex`, `lib/claude_agent_sdk/process.ex`, `lib/claude_agent_sdk/client.ex` | Python always enforces `--output-format stream-json`; Elixir allows `output_format` to override and can break parsing.
G-007 | High | Query streaming | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/query.py` | `lib/claude_agent_sdk/process.ex` | Python streams messages as they arrive; Elixir `Process.stream` buffers until process exit.
G-008 | High | Query API | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/query.py` | `lib/claude_agent_sdk.ex`, `lib/claude_agent_sdk/query.ex` | Python `query()` accepts AsyncIterable prompts and optional transport injection; Elixir `query/2` only accepts strings.
G-009 | High | CLI flags | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py` | `lib/claude_agent_sdk/client.ex`, `lib/claude_agent_sdk/transport/port.ex`, `lib/claude_agent_sdk/streaming/session.ex` | Elixir always adds `--replay-user-messages` in control/streaming; Python requires explicit `extra_args`.
G-010 | High | Stderr handling | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py` | `lib/claude_agent_sdk/process.ex`, `lib/claude_agent_sdk/streaming/session.ex` | Python supports `stderr` callback in all modes; Elixir ignores `stderr` in Process/Streaming and merges in Port only.
G-011 | Medium | Buffer limits | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py` | `lib/claude_agent_sdk/transport/port.ex` | Python enforces `max_buffer_size` and raises on overflow; Elixir only uses line length without hard limit.
G-012 | Critical | MCP SDK tools | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py` | `lib/claude_agent_sdk/tool/registry.ex`, `lib/claude_agent_sdk/client.ex` | Python returns successful MCP tool results with `is_error`; Elixir returns JSONRPC error on tool failure and uses `isError` naming.
G-013 | High | MCP init metadata | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py` | `lib/claude_agent_sdk/client.ex` | MCP `initialize` response in Elixir always uses `server_name` alias + version `1.0.0`, ignoring configured name/version.
G-014 | Medium | MCP methods | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py` | `lib/claude_agent_sdk/client.ex` | Elixir returns empty success for `resources/list` and `prompts/list`; Python returns method-not-found errors.
G-015 | Medium | Tool name handling | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/query.py` | `lib/claude_agent_sdk/client.ex`, `lib/claude_agent_sdk/tool/registry.ex` | Elixir converts MCP tool names to atoms (`String.to_atom`), unlike Python strings; potential atom leak and mismatch.
G-016 | High | Message parsing | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/message_parser.py` | `lib/claude_agent_sdk/message.ex` | Elixir `result` subtype parsing assumes known values and uses `String.to_atom`; unknown subtype can crash and leak atoms.
G-017 | Medium | MCP config API | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py` | `lib/claude_agent_sdk/options.ex` | Python accepts `mcp_servers` as dict or JSON/path; Elixir splits into `mcp_servers` and `mcp_config` (API mismatch).
G-018 | Medium | Extra args | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/_internal/transport/subprocess_cli.py` | `lib/claude_agent_sdk/options.ex` | Python uses `None` for boolean flags; Elixir serializes booleans as `--flag true/false`.
G-019 | Low | SDK MCP server defaults | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/__init__.py` | `lib/claude_agent_sdk.ex` | Python `create_sdk_mcp_server` defaults version to `1.0.0`; Elixir requires `version`.
G-020 | Low | Hook events | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py` | `lib/claude_agent_sdk/hooks/hooks.ex` | Elixir advertises SessionStart/SessionEnd/Notification hooks; Python does not support them.
G-021 | Low | Entrypoint env | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/query.py` | `lib/claude_agent_sdk/process.ex`, `lib/claude_agent_sdk/transport/port.ex` | Python distinguishes `sdk-py` vs `sdk-py-client`; Elixir always `sdk-elixir`.
G-022 | Low | Client receive_response API | `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/client.py` | `lib/claude_agent_sdk/client.ex` | Python yields messages until Result; Elixir returns a list and blocks.

Extra features in Elixir (not in Python)
- `ClaudeAgentSDK.Streaming` session API with parsed `text_delta` events.
- `OptionBuilder`, `StreamingRouter`, and richer auth helpers (`AuthManager`, `AuthChecker`).
- `strict_mcp_config`, `agent`, and `session_id` options.

These are not regressions but are divergences from the canonical Python surface area.

Assumptions and risk notes
- CLI behavior is inferred from the Python SDK usage; if CLI semantics differ, Python remains the canonical reference for parity.
- Several mismatches (G-001, G-006, G-012) can cause incorrect behavior even when the Elixir SDK appears to function.

See `remediation_plan.md` for a staged plan to resolve all gaps.
