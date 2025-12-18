# Python SDK Port Plan (f834ba9..0434749)

## Summary

This doc set captures what changed in `anthropics/claude-agent-sdk-python` between:

- **Base:** `f834ba9e1586ea2e31353fafcb41f78b7b9eab51`
- **Head:** `0434749` (current `origin/main` as of pull on 2025-12-17)

and how to port the relevant user-facing/runtime behavior to this Elixir SDK.

The Python range spans **v0.1.17** and **v0.1.18**, and is primarily:

1. **`UserMessage.uuid` surfaced** (devX for file checkpointing + `rewind_files`)
2. **Bundled Claude Code CLI version bumps** (→ **2.0.72**)
3. **Docker-based e2e harness + regression coverage** for filesystem agents / setting sources

## Docs In This Set

- [`01_user_message_uuid.md`](./01_user_message_uuid.md)
- [`02_bundled_cli_version_and_installation.md`](./02_bundled_cli_version_and_installation.md)
- [`03_docker_e2e_test_infra.md`](./03_docker_e2e_test_infra.md)
- [`04_filesystem_agents_regression.md`](./04_filesystem_agents_regression.md)

## Python Commit Timeline (in this range)

| Commit | Python release | Theme |
|--------|---------------|-------|
| `0ae5c32` | v0.1.17 | Add `uuid` to `UserMessage` response type |
| `5752f38` | v0.1.17 | Bundled CLI → 2.0.70 |
| `eba5675` | v0.1.17 | Release |
| `a0ce44a` | v0.1.18 | Docker test harness (catch container-specific issue #406) |
| `27575ae` | v0.1.18 | Bundled CLI → 2.0.71 |
| `91e65b1` | v0.1.18 | Bundled CLI → 2.0.72 |
| `a3df944` | v0.1.18 | Release |
| `0434749` | v0.1.18 | CI YAML fix (release-tag workflow) |

## What To Port (Elixir)

### A) `UserMessage.uuid` devX parity

Python:
- Adds `uuid` to `UserMessage` in `src/claude_agent_sdk/types.py`
- Parses/threads it through in `src/claude_agent_sdk/_internal/message_parser.py`
- Documents it in `ClaudeSDKClient.rewind_files()` docstring and adds a unit test

Elixir status:
- **Already parses** `"uuid"` into `%Message{type: :user}.data.uuid` in `lib/claude_agent_sdk/message.ex`
- **Missing:** explicit docs/API surfacing + regression test coverage

Design docs: `01_user_message_uuid.md`

### B) Bundled CLI version tracking (and optional bundling workflow)

Python:
- Tracks bundled CLI in `src/claude_agent_sdk/_cli_version.py` (`2.0.72`)
- Uses a bundled binary when present (package internal `_bundled/`)

Elixir status:
- `ClaudeAgentSDK.CLI` already supports a bundled binary location (`priv/_bundled/claude*`) and known-location discovery.
- **Missing:** a tracked “bundled/recommended CLI version” constant and a repeatable “install/bundle” workflow (mix task / CI step).

Design docs: `02_bundled_cli_version_and_installation.md`

### C) Docker-based e2e harness + filesystem-agents regression tests

Python:
- Adds `Dockerfile.test` + `scripts/test-docker.sh`
- Adds CI job `test-e2e-docker`
- Adds e2e tests and an example for filesystem agents loaded via `--setting-sources project` (issue #406)

Elixir status:
- No Docker harness.
- Integration tests exist (`@tag :integration`), but **no targeted regression** for filesystem agents / setting sources.
- System init metadata (e.g., `agents`, `output_style`, `slash_commands`) is **only reliably available in `Message.raw`**, not `Message.data`.

Design docs:
- `03_docker_e2e_test_infra.md`
- `04_filesystem_agents_regression.md`

## File/Module Mapping (Python → Elixir)

| Python change | Python file(s) | Elixir touchpoint(s) |
|--------------|----------------|----------------------|
| `UserMessage.uuid` surfaced | `src/claude_agent_sdk/types.py`, `src/claude_agent_sdk/_internal/message_parser.py`, `tests/test_message_parser.py` | `lib/claude_agent_sdk/message.ex` (already parses), add unit tests + helper |
| Bundled CLI pin | `src/claude_agent_sdk/_cli_version.py` | add `lib/claude_agent_sdk/cli_version.ex`, add a mix task, align docs/diagnostics |
| Docker e2e harness | `Dockerfile.test`, `scripts/test-docker.sh`, `.github/workflows/test.yml` | add root `Dockerfile.test`, `scripts/test-docker.sh`, optional `.github/workflows` job |
| Filesystem agent regression | `e2e-tests/test_agents_and_settings.py`, `examples/filesystem_agents.py`, `.claude/agents/test-agent.md` | add targeted Elixir integration test + optional example; consider exposing init metadata in `Message.data` |

## Proposed Implementation Order (Elixir)

1. **Add/lock devX for `uuid`** (tests + docs + helper function)
2. **Add CLI version tracking** (recommended/bundled version constant) and document how it maps to features like file checkpointing
3. **Add filesystem agents regression test** (live/integration tagged), minimally reading init metadata from `Message.raw`
4. **Add Docker harness** for running (3) in a container, then wire into CI as an optional job gated by a secret token
5. (Optional) **Improve system init metadata ergonomics** by exposing selected init fields in `Message.data` with stable keys

## Acceptance Criteria

- Developers can obtain a stable user-message checkpoint id via `message.data.uuid` and use it with `Client.rewind_files/2` (documented).
- We can reproduce the “filesystem agent via project settings” scenario in Elixir and assert we get **init → assistant → result** (no silent early termination).
- We can run the targeted regression in Docker locally (script) and optionally in CI (job guarded by secret).
- We can point to a single “recommended CLI version” (matching Python’s bundled version: **2.0.72**) in Elixir docs/code.
