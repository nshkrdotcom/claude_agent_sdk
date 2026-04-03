# Examples

> **Note:** Examples are available in the [source repository](https://github.com/nshkrdotcom/claude_agent_sdk/tree/main/examples) and are not included in the Hex package to minimize download size. Clone the repo to run them locally.

These examples demonstrate real integration with the Claude Code CLI.

## Prerequisites

- **Claude Code CLI:** `npm install -g @anthropic-ai/claude-code`
- **Authentication:** `claude login` (or set `ANTHROPIC_API_KEY` / `CLAUDE_AGENT_OAUTH_TOKEN`)

## Runtime Config Notes

Some examples that exercise in-process tools and query streaming are affected by runtime config:

```elixir
# Timeouts and buffer sizes are centralized in Config.* modules:
config :claude_agent_sdk, ClaudeAgentSDK.Config.Timeouts,
  tool_execution_ms: 30_000

# Legacy flat keys still work for non-migrated settings:
config :claude_agent_sdk,
  cli_stream_module: ClaudeAgentSDK.Query.CLIStream,
  task_supervisor_strict: false,
  agents_temp_file_max_age_seconds: 86_400
```

See the [Configuration Internals](../guides/configuration-internals.md) guide for
all tunable constants and their defaults.

`process_module` is still accepted as a fallback key for query streaming, but it is deprecated.

All live examples call `Examples.Support.ensure_live!/0`, which starts
`ClaudeAgentSDK.TaskSupervisor` for clean supervised async task execution.

If you enable strict mode (`task_supervisor_strict: true`) and the configured task
supervisor is missing, background task scheduling returns
`{:error, {:task_supervisor_unavailable, supervisor}}` instead of unsupervised fallback.

Transport-level close/missing-command errors normalize to `:not_connected` and
`:cli_not_found` at query/control boundaries.

For lifecycle tests and demos, transport/session modules also support `startup_mode: :lazy`
to defer subprocess startup until `handle_continue/2`.

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
bash examples/run_all.sh --ssh-host example.internal
bash examples/run_all.sh --ssh-host example.internal --danger-full-access
```

Sets `CLAUDE_EXAMPLES_FORCE_HALT=true` to ensure each script exits cleanly.
The runner continues after failures and prints a summary at the end (non-zero exit
if any example failed).

`run_all.sh` now uses one transport-aware live preflight for both local and
`--ssh-host` runs. That means missing CLI, remote auth/access failures, and SSH
placement issues are caught before the runner fans out into the full example
list.

The preflight timeout is backend-aware:

- Anthropic-backed runs default to `30s`
- Ollama-backed runs default to `60s`

Set `CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS` to override the inner transport
budget. The shell wrapper keeps a small extra headroom above that value so
compile/startup overhead does not trip the outer `timeout` before the transport
budget does. You can also override that headroom with
`CLAUDE_EXAMPLES_PREFLIGHT_WRAPPER_HEADROOM_SECONDS`.

### Run with Ollama

Fastest path:

```bash
bash examples/run_all.sh --ollama
```

This runs the full example list against the Ollama-backed Claude path and
defaults to `llama3.2`.

Pick a different Ollama model:

```bash
bash examples/run_all.sh --ollama --ollama-model qwen3.5:14b
```

Environment-variable form still works:

```bash
CLAUDE_EXAMPLES_BACKEND=ollama \
CLAUDE_EXAMPLES_OLLAMA_MODEL=llama3.2 \
bash examples/run_all.sh
```

Ollama mode keeps the example source on canonical Claude names such as
`haiku` and maps them to the selected Ollama model through the
core-owned model registry path.

Examples that depend on unsupported Ollama features now self-skip by default.
Set `CLAUDE_EXAMPLES_FORCE_UNSUPPORTED=true` if you want to force those runs.

If Ollama preflight fails, the first things to check are:

- `ANTHROPIC_BASE_URL` points at a reachable Ollama server
- the selected model is installed and warmed
- `CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS` is high enough for cold-start latency

### Run Individual Examples

```bash
mix run examples/basic_example.exs
mix run examples/basic_example.exs -- --ssh-host example.internal
mix run examples/basic_example.exs -- --ssh-host example.internal --danger-full-access
```

## Shared SSH Flags

Every CLI-backed example in this directory accepts the same optional SSH
transport flags:

- `--cwd <path>` passes an explicit working directory to the example
- `--danger-full-access` maps the example to `permission_mode: :bypass_permissions`
- `--ssh-host <host>` switches the example to `execution_surface: :ssh_exec`
- `--ssh-user <user>` overrides the SSH user
- `--ssh-port <port>` overrides the SSH port
- `--ssh-identity-file <path>` sets the SSH identity file

If you omit the SSH flags, the examples keep the existing local subprocess
default unchanged.

`--danger-full-access` only changes the Claude runtime permission posture. It
does not change transport placement. Use it when you want the same example to
stay on `execution_surface: :ssh_exec` but run with the permissive Claude mode
on a remote host.

Run an individual example with Ollama:

```bash
CLAUDE_AGENT_PROVIDER_BACKEND=ollama \
ANTHROPIC_AUTH_TOKEN=ollama \
ANTHROPIC_API_KEY='' \
ANTHROPIC_BASE_URL=http://localhost:11434 \
CLAUDE_AGENT_EXTERNAL_MODEL_OVERRIDES='{"haiku":"llama3.2","sonnet":"llama3.2","opus":"llama3.2","sonnet[1m]":"llama3.2","opus[1m]":"llama3.2","legacy-sonnet":"llama3.2"}' \
mix run examples/basic_example.exs
```

## Example Index

### Core Examples

| Example | Description |
|---------|-------------|
| `basic_example.exs` | Minimal `ClaudeAgentSDK.query/2` with message extraction |
| `effort_gating_live.exs` | Live effort demo showing supported models, Haiku gating, and invalid-value validation |
| `max_effort_opus_live.exs` | Opus `:max` effort — request/response and streaming for both `opus` and `opus[1m]` (**not in `run_all.sh`** — expensive) |
| `session_features_example.exs` | SessionStore save/search, resume, session CLI flags |
| `resume_persistence_repro_live.exs` | Standalone repro for `--print --resume` dropping intermediate turns (**not in `run_all.sh`**) |
| `structured_output_live.exs` | Structured JSON via `--json-schema` |
| `sandbox_settings_live.exs` | Sandbox merged into `--settings` |
| `tools_and_betas_live.exs` | `--tools` variations |

### Advanced Features

| Example | Description |
|---------|-------------|
| `advanced_features/agents_live.exs` | Multi-agent workflow via `resume/3` |
| `advanced_features/permissions_live.exs` | Tool permission callback (`can_use_tool`), fails if CLI doesn't emit control callbacks |
| `advanced_features/sdk_mcp_live_demo.exs` | SDK MCP tools invoked in-process (`tools/call` handled asynchronously in Client) |
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
