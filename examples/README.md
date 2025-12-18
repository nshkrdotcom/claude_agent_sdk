# Examples

These examples are **live** (they talk to the real Claude Code CLI).

## Prereqs

- Install CLI: `npm install -g @anthropic-ai/claude-code`
- Authenticate: `claude login` (or set `ANTHROPIC_API_KEY` / `CLAUDE_AGENT_OAUTH_TOKEN`)

## Run Everything

- `bash examples/run_all.sh`
  - Sets `CLAUDE_EXAMPLES_FORCE_HALT=true` to ensure each `mix run` exits cleanly

## Run One

- `mix run examples/basic_example.exs`

## Curated Live Examples

- `examples/basic_example.exs` — minimal `ClaudeAgentSDK.query/2` + message extraction
- `examples/session_features_example.exs` — SessionStore save/search + resume + session-related CLI flags
- `examples/structured_output_live.exs` — structured JSON via `--json-schema`
- `examples/sandbox_settings_live.exs` — sandbox merged into `--settings` + live query
- `examples/tools_and_betas_live.exs` — `--tools` variations (optional: `CLAUDE_CODE_BETAS`)
- `examples/advanced_features/agents_live.exs` — multi-agent workflow via `resume/3`
- `examples/advanced_features/permissions_live.exs` — tool permission callback (`can_use_tool`)
- `examples/advanced_features/sdk_mcp_live_demo.exs` — SDK MCP tools invoked in-process
- `examples/streaming_tools/quick_demo.exs` — minimal streaming session (no tools/hooks)
- `examples/streaming_tools/sdk_mcp_streaming.exs` — Streaming + SDK MCP tools (stream events + tool lifecycle)
- `examples/hooks/context_injection.exs` — `user_prompt_submit` context injection hook
- `examples/hooks/basic_bash_blocking.exs` — `pre_tool_use` allow/deny hook for Bash
- `examples/hooks/file_policy_enforcement.exs` — `pre_tool_use` file policy hook for Write/Edit (sandbox + sensitive files)
- `examples/hooks/logging_and_audit.exs` — pre/post tool hooks for audit logging
- `examples/hooks/complete_workflow.exs` — combined hooks workflow (context + audit + security + monitoring)
- `examples/streaming_tools/basic_streaming_with_hooks.exs` — Streaming API + hooks
- `examples/runtime_control/control_parity_live.exs` — Query/control parity + runtime permission mode switching
- `examples/assistant_error_live.exs` — assistant error metadata (streaming vs aggregated)
- `examples/file_checkpointing_live.exs` — `rewind_files/2` (best-effort; depends on CLI support)
- `examples/filesystem_agents_live.exs` — filesystem agents loaded via `setting_sources: ["project"]`

## Archived / Mock

- `examples/archive/mock_demos/` contains deterministic mock/transport examples.
- `examples/archive/` contains older or experimental scripts.
