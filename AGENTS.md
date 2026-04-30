# Repository Guidelines

## Project Structure
- `lib/` contains public `ClaudeAgentSDK` modules and internal runtime adapters.
- `test/` contains ExUnit coverage; `test/support/` is test-only and may contain lower-runtime fixtures.
- `guides/`, `docs/`, `examples/`, `README.md`, and `CHANGELOG.md` must stay aligned with runtime and dependency behavior.
- `doc/` is generated output and should not be edited.

## Execution Plane Stack
- This SDK sits above `cli_subprocess_core`; do not expose raw `ExecutionPlane.*` internals in public APIs or docs.
- Use `CliSubprocessCore` facades for execution surfaces, transport errors, transport info, process exits, sessions, commands, and provider model policy.
- Keep `cli_subprocess_core` dependency resolution publish-aware: local path deps for sibling development, Hex constraints for release builds.

## ASM Boundary
- Claude-native controls such as hooks, MCP, permissions, permission callbacks, allowed/disallowed tools, settings, agents, control-client flows, and native system prompt channels belong in this SDK.
- ASM may derive only common placement/session data unless a caller passes explicit Claude-native overrides through a provider extension or calls this SDK directly.
- Do not generalize Claude control behavior into ASM without all-four proof across Claude, Codex, Gemini, and Amp.
- Before asserting a Claude-native feature exists, add or update `guides/provider_behavior_manifest.md` with source, fixture, or live-smoke evidence.
- SDK-direct promotion examples in `examples/promotion_path/` must not import or alias ASM.

## Gates
- Run `mix format`.
- Run `mix compile --warnings-as-errors`.
- Run `mix test`.
- Run `mix credo --strict`.
- Run `mix dialyzer`.
- Run `mix docs --warnings-as-errors`.
