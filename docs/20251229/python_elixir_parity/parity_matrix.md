# Parity Matrix

This matrix maps Python SDK features to the Elixir port and flags mismatches. Gap IDs refer to `gap_analysis.md`.

Options (ClaudeAgentOptions vs Options)
Python option | Elixir field | Status | Notes
---|---|---|---
tools | tools | Match | Same CLI mapping.
allowed_tools | allowed_tools | Match | Same CLI mapping.
system_prompt | system_prompt | Match | Same behavior; empty prompt forced.
permission_mode | permission_mode | Match | String vs atom; mapped.
permission_prompt_tool_name | permission_prompt_tool | Mismatch | Field rename + no `can_use_tool` auto-set (G-003).
max_turns | max_turns | Match | Same flag.
max_budget_usd | max_budget_usd | Match | Same flag.
model | model | Match | Same flag.
fallback_model | fallback_model | Match | Same flag.
betas | betas | Match | Same flag.
output_format | output_format | Mismatch | Elixir can override stream-json (G-006).
settings | settings | Match | Sandbox merge parity.
sandbox | sandbox | Match | Merged into `--settings`.
setting_sources | setting_sources | Match | Always emitted as in Python.
add_dirs | add_dirs / add_dir | Match | Elixir also supports singular.
mcp_servers | mcp_servers | Mismatch | Python accepts dict or JSON/path; Elixir splits into `mcp_servers` + `mcp_config` (G-017).
cli_path | path_to_claude_code_executable / executable | Missing | Options exist but unused (G-004).
extra_args | extra_args | Mismatch | Boolean serialization differs (G-018).
max_buffer_size | max_buffer_size | Partial | Only line length, no hard limit (G-011).
stderr | stderr | Partial | Not wired in Process/Streaming (G-010).
can_use_tool | can_use_tool | Partial | Missing validation + auto permission prompt (G-003).
hooks | hooks | Partial | Timeout units mismatch; extra events (G-002, G-020).
include_partial_messages | include_partial_messages | Match | Flag supported; streaming API always enables partials.
fork_session | fork_session | Match | Same flag.
agents | agents | Match | JSON encoding parity.
plugins | plugins | Match | Local plugins only.
max_thinking_tokens | max_thinking_tokens | Match | Same flag.
enable_file_checkpointing | enable_file_checkpointing | Match | Env var set.
user | user | Match | Supported via erlexec/port selection.

Client API (ClaudeSDKClient vs Client)
Python method | Elixir equivalent | Status | Notes
---|---|---|---
connect / disconnect | start_link / stop | Different | OTP lifecycle but feature equivalent.
query(prompt, session_id) | query(pid, prompt, session_id) | Match | Same behavior for prompt injection.
receive_messages | stream_messages | Match | Stream of messages.
receive_response | receive_response | Mismatch | Python yields stream; Elixir returns list (G-022).
interrupt | interrupt | Match | Control request supported.
set_permission_mode | set_permission_mode | Match | Control request supported.
set_model | set_model | Match | Control request supported.
rewind_files | rewind_files | Match | Control request supported.
get_server_info | get_server_info | Match | Implemented in Elixir.

Query API
Python query() | Elixir ClaudeAgentSDK.query/2 | Status | Notes
---|---|---|---
String prompt | Supported | Match | Works.
AsyncIterable prompt | Not supported | Missing | Unidirectional streaming not exposed (G-008).
Custom transport injection | Not supported | Missing | No public transport override (G-008).
Streaming output | Partial | Elixir non-control query buffers until exit (G-007).

Control protocol subtypes
Subtype | Python | Elixir | Status | Notes
---|---|---|---|---
initialize | Yes | Yes | Match | Elixir adds `sdkMcpServers` (extra).
hook_callback | Yes | Yes | Match | Timeout unit mismatch (G-002).
can_use_tool | Yes | Yes | Mismatch | Response shape differs (G-001).
set_permission_mode | Yes | Yes | Match | Works.
set_model | Yes | Yes | Match | Works.
interrupt | Yes | Yes | Match | Works.
rewind_files | Yes | Yes | Match | Works.
mcp_message | Yes | Yes | Match | Also accepts `sdk_mcp_request`.

MCP SDK server methods
Method | Python | Elixir | Status | Notes
---|---|---|---|---
initialize | Returns server.name/version | Uses alias name + `1.0.0` | Mismatch (G-013).
tools/list | Supported | Supported | Match.
tools/call | Result with `is_error` | JSONRPC error + `isError` naming | Mismatch (G-012).
notifications/initialized | Supported | Supported | Match.
resources/list | Method not found | Empty success | Mismatch (G-014).
prompts/list | Method not found | Empty success | Mismatch (G-014).

Message parsing
Python behavior | Elixir behavior | Status | Notes
---|---|---|---
Unknown result subtype tolerated | Crashes / atom leak | Mismatch (G-016).
Tool result field name `is_error` | Mixed `isError` / `is_error` | Mismatch (G-012).
Stream events as raw data | Elixir also parses into higher-level events (Streaming API) | Extra.

See `remediation_plan.md` for concrete fixes.
