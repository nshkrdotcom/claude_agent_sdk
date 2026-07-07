# Repository Guidelines

## Project Structure
- `lib/` contains public `ClaudeAgentSDK` modules and internal runtime adapters.
- `test/` contains ExUnit coverage; `test/support/` is test-only and may contain lower-runtime fixtures.
- `guides/`, `docs/`, `examples/`, `README.md`, and `CHANGELOG.md` must stay aligned with runtime and dependency behavior.
- `doc/` is generated output and should not be edited.

## Execution Plane Stack
- This SDK sits above `cli_subprocess_core`; do not expose raw `ExecutionPlane.*` internals in public APIs or docs.
- This SDK must never spawn OS processes or open transports directly; all execution flows through `cli_subprocess_core` → `execution_plane`. That indirection is deliberate: Execution Plane is intended to run (optionally) as a separate, hard-isolated BEAM node so side-effecting execution is fault/security/blast-radius isolated from the SDK. Keeping execution behind the `CliSubprocessCore` facades is what lets that isolation land with no SDK change — do not re-couple execution (e.g. a direct Port/erlexec spawn) into this repo.
- Use `CliSubprocessCore` facades for execution surfaces, transport errors, transport info, process exits, sessions, commands, and provider model policy.
- Dependency source selection is handled by `build_support/dependency_sources.exs`
  and `build_support/dependency_sources.config.exs`; local overrides use
  `.dependency_sources.local.exs`.
- Keep `cli_subprocess_core` dependency resolution publish-aware: local path
  deps for sibling development, GitHub fallback for clean clones, and Hex
  constraints for release builds.
- Dependency source selection must not use environment variables.
- This repo is not a Weld consumer in this pass and must not receive a blind
  Weld dependency. Weld verification is limited to discovered Weld consumers.
- Runtime application code under `lib/**` must not call direct OS env APIs such
  as `System.get_env`, `System.fetch_env`, `System.put_env`, or
  `System.delete_env`.
- Runtime and deployment env reads belong in `config/runtime.exs` or an
  explicit `Config.Provider`; runtime modules read materialized values through
  `ClaudeAgentSDK.Env` or explicit caller options.

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
