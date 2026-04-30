# Claude Provider Behavior Manifest

Provider-native Claude Code behavior must be proven here before this SDK
translates it. This manifest is SDK-owned evidence; it is not proof that ASM can
expose the feature as common behavior across providers.

| Feature | Evidence type | CLI version/source revision | Fixture | Live smoke | Known unsupported semantics | Date verified |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Code streaming JSON argument rendering | CLI help/source inspection and SDK render tests | current Claude Code CLI contract as represented by SDK options | `test/claude_agent_sdk/options_streaming_test.exs`; `test/claude_agent_sdk/runtime/cli_render_test.exs` | `examples/promotion_path/sdk_direct_claude.exs` | SDK-native option shaping; not an ASM common schema | 2026-04-29 |
| Claude-native tools, allowed/disallowed tools, and tool suppression | provider docs/source inspection and SDK tests | current Claude Code CLI contract | `test/claude_agent_sdk/options_streaming_test.exs`; `test/claude_agent_sdk/runtime/cli_render_test.exs` | `examples/promotion_path/sdk_direct_claude.exs` | `tools: []` and Claude tool flags are Claude-native; ASM must not expose common no-tool or host-tool options without all-four proof | 2026-04-29 |
| Claude-native MCP, hooks, permission callbacks, permission modes, and control-client routing | source inspection note and SDK transport tests | current Claude SDK/CLI control contract | `test/claude_agent_sdk/transport/streaming_router_test.exs`; `test/claude_agent_sdk/runtime/cli_render_test.exs` | Existing live hook/MCP/permission examples; promotion example stays text-only with tool suppression | Provider-native control behavior only; does not establish common ASM tools, approvals, or MCP semantics | 2026-04-29 |
| Shared `execution_surface` normalization for local and SSH placement | source inspection note and SDK runtime tests | current `cli_subprocess_core` dependency | `test/claude_agent_sdk/query_cli_stream_test.exs`; `test/claude_agent_sdk/runtime/cli_render_test.exs` | `examples/promotion_path/sdk_direct_claude.exs` for local keyword input; live SSH tests remain opt-in | Placement only; execution surface metadata must not become provider-native Claude configuration | 2026-04-29 |

