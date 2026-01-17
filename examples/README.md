# Examples

> **Note:** Examples are available in the [source repository](https://github.com/nshkrdotcom/claude_agent_sdk/tree/main/examples) and are not included in the Hex package to minimize download size. Clone the repo to run them locally.

These examples demonstrate real integration with the Claude Code CLI.

## Prerequisites

- **Claude Code CLI:** `npm install -g @anthropic-ai/claude-code`
- **Authentication:** `claude login` (or set `ANTHROPIC_API_KEY` / `CLAUDE_AGENT_OAUTH_TOKEN`)

## Mix Task Example (Recommended Starting Point)

A complete working example app showing how to integrate Claude into your own Mix project:

**[`mix_task_chat/`](mix_task_chat/README.md)**

- Mix tasks using the SDK
- Real-time streaming responses (typewriter effect)
- Interactive multi-turn conversations
- Simple query-response patterns for scripting

```bash
git clone https://github.com/nshkrdotcom/claude_agent_sdk.git
cd claude_agent_sdk/examples/mix_task_chat
mix deps.get
mix chat "Hello, Claude!"           # Streaming response
mix chat --interactive              # Multi-turn conversation
mix ask -q "What is 2+2?"           # Script-friendly output
```

## Running Examples

### Run All Examples

```bash
bash examples/run_all.sh
```

Sets `CLAUDE_EXAMPLES_FORCE_HALT=true` to ensure each script exits cleanly.
The runner continues after failures and prints a summary at the end (non-zero exit
if any example failed).

### Run Individual Examples

```bash
mix run examples/basic_example.exs
```

## Example Index

### Core Examples

| Example | Description |
|---------|-------------|
| `basic_example.exs` | Minimal `ClaudeAgentSDK.query/2` with message extraction |
| `session_features_example.exs` | SessionStore save/search, resume, session CLI flags |
| `structured_output_live.exs` | Structured JSON via `--json-schema` |
| `sandbox_settings_live.exs` | Sandbox merged into `--settings` |
| `tools_and_betas_live.exs` | `--tools` variations |

### Advanced Features

| Example | Description |
|---------|-------------|
| `advanced_features/agents_live.exs` | Multi-agent workflow via `resume/3` |
| `advanced_features/permissions_live.exs` | Tool permission callback (`can_use_tool`), fails if CLI doesn't emit control callbacks |
| `advanced_features/sdk_mcp_live_demo.exs` | SDK MCP tools invoked in-process |
| `advanced_features/subagent_spawning_live.exs` | Parallel subagent spawning (research-agent pattern) |
| `advanced_features/web_tools_live.exs` | WebSearch and WebFetch for web access |

### Streaming

| Example | Description |
|---------|-------------|
| `streaming_tools/quick_demo.exs` | Minimal streaming session |
| `streaming_tools/sdk_mcp_streaming.exs` | Streaming with SDK MCP tools |
| `streaming_tools/basic_streaming_with_hooks.exs` | Streaming API with hooks |
| `streaming_tools/stop_reason_probe.exs` | Control client probe for stop_reason emission across tool_use and end_turn |
| `streaming_tools/multi_turn_tool_streaming_session.exs` | Session path multi-turn tool streaming example (raises if stream ends after tool_use) |
| `streaming_tools/subagent_streaming.exs` | Subagent streaming with `parent_tool_use_id` for routing output by source |

### Hooks

| Example | Description |
|---------|-------------|
| `hooks/context_injection.exs` | `user_prompt_submit` context injection |
| `hooks/basic_bash_blocking.exs` | `pre_tool_use` allow/deny for Bash |
| `hooks/file_policy_enforcement.exs` | `pre_tool_use` file policy for Write/Edit |
| `hooks/logging_and_audit.exs` | Pre/post tool hooks for audit logging |
| `hooks/complete_workflow.exs` | Combined hooks workflow |

### Runtime Control

| Example | Description |
|---------|-------------|
| `runtime_control/control_parity_live.exs` | Query/control parity, permission mode switching |
| `assistant_error_live.exs` | Assistant error metadata handling |
| `file_checkpointing_live.exs` | `rewind_files/2` (depends on CLI support) |
| `filesystem_agents_live.exs` | Filesystem agents via `setting_sources: ["project"]` |

## Archived Examples

The `archive/` directory contains older or experimental scripts, including mock/transport examples for deterministic testing.

## Related Documentation

- [Getting Started](../guides/getting-started.md)
- [Streaming Guide](../guides/streaming.md)
- [Hooks Guide](../guides/hooks.md)
- [Permissions Guide](../guides/permissions.md)
