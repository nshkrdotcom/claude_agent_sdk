# Claude Code SDK Examples

Scripts can be run in **live mode** (real Claude Code CLI + real API calls) or using the SDK mocks.

- Live (recommended for examples): `mix run.live examples/<path>.exs`
- Mock/default: `mix run examples/<path>.exs` (behavior depends on `:claude_agent_sdk, :use_mock` and `LIVE_MODE`)

## Usage

```bash
mix run.live examples/<path>.exs [args...]
```

## Core & Quickstart

- `examples/basic_example.exs` — single-turn hello world
- `examples/simple_analyzer.exs` — analyze a file
- `examples/file_reviewer.exs` — review a file
- `examples/simple_batch.exs` — batch over a directory
- `examples/simple_test_gen.exs` — generate test scaffolds
- `examples/custom_agents_example.exs` — define custom agents
- `examples/model_selection_example.exs` — compare model presets
- `examples/factorial_example.exs` — factorial demo module
- `examples/session_features_example.exs` — session persistence/forking
- `examples/project_assistant_fixed.exs` — interactive helper
- `examples/week_1_2_showcase.exs` — early feature tour
- `examples/test_auth_detection.exs` — auth challenge detection
- `examples/assistant_error_live.exs` — assistant error surface
- `examples/structured_output_live.exs` — JSON schema output
- `examples/control_parity_live.exs` — control protocol parity
- `examples/tools_and_betas_live.exs` — `tools` / `betas` option parity
- `examples/sandbox_settings_live.exs` — sandbox settings merged into `--settings`
- `examples/file_checkpointing_live.exs` — enable file checkpointing + `rewind_files` (CLI payload dependent)

## Streaming + Tools

- `examples/streaming_tools/basic_streaming_with_hooks.exs`
- `examples/streaming_tools/sdk_mcp_streaming.exs`
- `examples/streaming_tools/quick_demo.exs`
- `examples/streaming_tools/liveview_pattern.exs` (pattern/pseudo-code)

## Runtime Control

- `examples/runtime_control/model_switcher.exs`
- `examples/runtime_control/transport_swap.exs`
- `examples/runtime_control/subscriber_broadcast.exs`
- `examples/runtime_control/cancellable_callbacks.exs` — cooperative cancellation using abort signals
  - Emits simple telemetry events for hook/permission start/completion/cancel

## Advanced (MCP, Agents, Permissions)

- `examples/advanced_features/mcp_calculator_tool.exs`
- `examples/advanced_features/sdk_mcp_simple_test.exs`
- `examples/advanced_features/sdk_mcp_live_demo.exs`
- `examples/advanced_features/agent_switching.exs`
- `examples/advanced_features/agents_live.exs`
- `examples/advanced_features/permission_control.exs`
- `examples/advanced_features/permissions_live.exs`
- `examples/advanced_features/full_feature_showcase.exs`

## Hooks

- `examples/hooks/basic_bash_blocking.exs`
- `examples/hooks/context_injection.exs`
- `examples/hooks/file_policy_enforcement.exs`
- `examples/hooks/logging_and_audit.exs`
- `examples/hooks/complete_workflow.exs`
