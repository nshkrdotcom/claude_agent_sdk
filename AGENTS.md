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

## Gates
- Run `mix format`.
- Run `mix compile --warnings-as-errors`.
- Run `mix test`.
- Run `mix credo --strict`.
- Run `mix dialyzer`.
- Run `mix docs --warnings-as-errors`.
