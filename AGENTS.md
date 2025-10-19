# Repository Guidelines

## Project Structure & Module Organization
- `lib/claude_agent_sdk/` contains the public API, orchestration layers, hooks, and Mix tasks—co-locate new modules with their nearest peer.
- `test/` mirrors the lib tree, with shared helpers in `test/support/`; keep unit specs fast and isolate long-running flows with tags.
- `examples/` and `demo_mock.exs` showcase scripted agents; update them whenever behaviour or CLI parameters change.
- Docs and assets live under `docs/`, `ARCHITECTURE.md`, and `assets/`; Dialyzer PLTs are cached in `priv/plts`.

## Build, Test, and Development Commands
- `mix deps.get` — sync dependencies after editing `mix.exs`.
- `mix compile --warnings-as-errors` — keep builds warning-free.
- `mix test` — default ExUnit suite (integration coverage stays skipped).
- `mix test --include integration` — run CLI-backed scenarios after `claude login`.
- `mix credo --strict`, `mix dialyzer`, and `mix showcase` or `mix run.live examples/basic_example.exs` — enforce quality gates and smoke-test agent workflows.

## Coding Style & Naming Conventions
Stick to idiomatic Elixir: two-space indentation, pipe-friendly function chains, and CamelCase modules aligned with directory layout. Run `mix format` before committing; `.formatter.exs` covers `lib/`, `test/`, and `config/`. Credo and Dialyzer must pass, and new structs need `@enforce_keys`, `@type t`, and consistent naming per `NAMING_CONVENTION.md`.

## Testing Guidelines
Tests use ExUnit with the `ClaudeAgentSDK.Mock` helper for deterministic responses; name files `*_test.exs` and keep them parallel to their lib module. Real CLI flows are guarded by `@tag :integration`; enable them with `mix test --include integration` only after `claude login` and `mix claude.setup_token`. Assert on message types, streamed events, and error branches, updating fixtures whenever the control protocol evolves.

## Commit & Pull Request Guidelines
Favor short, imperative commit subjects like `Fix doc warnings` or `Add MCP tool registry hook`, and keep each commit focused. Open PRs from feature branches, link issues, and include validation notes summarizing the Mix commands you ran (plus screenshots for CLI UX tweaks). Before requesting review, verify `mix format`, `mix credo --strict`, `mix dialyzer`, and the relevant `mix test` targets; mention any suites intentionally skipped.

## Security & Agent Configuration Tips
Authentication lives under `lib/claude_agent_sdk/auth/`; keep secrets out of the repo and rely on `mix claude.setup_token` (or `CLAUDE_AGENT_OAUTH_TOKEN`) for credential management. When extending agent profiles or permission modes, validate `Client.set_agent/2` and `Client.set_permission_mode/2` with the live runner and document any new configuration knobs in `docs/` and `config/runtime.exs`.
