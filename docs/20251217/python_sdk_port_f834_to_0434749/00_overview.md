# Python SDK Port Plan (f834ba9..0434749)

## Summary

This doc set captures what changed in `anthropics/claude-agent-sdk-python` between:

- **Base:** `f834ba9e1586ea2e31353fafcb41f78b7b9eab51`
- **Head:** `0434749` (current `origin/main` as of 2025-12-17)

and how to port the relevant user-facing/runtime behavior to this Elixir SDK.

The Python range spans **v0.1.17** and **v0.1.18**, and is primarily:

1. **`UserMessage.uuid` surfaced** (devX for file checkpointing + `rewind_files`)
2. **Bundled Claude Code CLI version bumps** (2.0.69 → **2.0.72**)
3. **Docker-based e2e harness + regression coverage** for filesystem agents / setting sources

## Docs In This Set

- [`01_user_message_uuid.md`](./01_user_message_uuid.md)
- [`02_bundled_cli_version_and_installation.md`](./02_bundled_cli_version_and_installation.md)
- [`03_docker_e2e_test_infra.md`](./03_docker_e2e_test_infra.md)
- [`04_filesystem_agents_regression.md`](./04_filesystem_agents_regression.md)
- [`IMPLEMENTATION_PROMPT.md`](./IMPLEMENTATION_PROMPT.md) - **Complete implementation instructions for agent execution**

## Python Commit Timeline (in this range)

| Commit | Python release | Theme | Port-relevant? |
|--------|---------------|-------|----------------|
| `0ae5c32` | v0.1.17 | Add `uuid` to `UserMessage` response type | **Yes** |
| `5752f38` | v0.1.17 | Bundled CLI → 2.0.70 | Tracking only |
| `eba5675` | v0.1.17 | Release | No (changelog) |
| `904c2ec` | v0.1.18 | Use CHANGELOG.md for release notes | No (CI only) |
| `a0ce44a` | v0.1.18 | Docker test harness (issue #406 regression) | **Yes** |
| `27575ae` | v0.1.18 | Bundled CLI → 2.0.71 | Tracking only |
| `91e65b1` | v0.1.18 | Bundled CLI → 2.0.72 | Tracking only |
| `a3df944` | v0.1.18 | Release | No (changelog) |
| `0434749` | v0.1.18 | CI YAML fix (release-tag workflow) | No (CI only) |

## What To Port (Elixir)

### A) `UserMessage.uuid` devX parity

Python:
- Adds `uuid: str | None = None` to `UserMessage` in `src/claude_agent_sdk/types.py:565`
- Parses via `uuid = data.get("uuid")` in `src/claude_agent_sdk/_internal/message_parser.py:51,78,83`
- Updates `rewind_files()` docstring in `client.py:264-297` to explain `extra_args={"replay-user-messages": None}` requirement
- Adds unit test `test_parse_user_message_with_uuid` in `tests/test_message_parser.py`

Elixir status:
- **Already parses** `"uuid"` into `%Message{type: :user}.data.uuid` via `maybe_put_uuid/2` at `lib/claude_agent_sdk/message.ex:347-351`
- **Already includes** `--replay-user-messages` in streaming mode at `lib/claude_agent_sdk/client.ex:1417`
- **Missing:**
  - No `Message.user_uuid/1` helper function (proposed for ergonomics)
  - No unit test covering uuid parsing
  - Docs/examples could more explicitly show the checkpoint workflow

Design docs: `01_user_message_uuid.md`

### B) Bundled CLI version tracking (and optional bundling workflow)

Python:
- Tracks bundled CLI in `src/claude_agent_sdk/_cli_version.py` (`__cli_version__ = "2.0.72"`)
- Installs via official installer or npm in Dockerfile

Elixir status:
- `ClaudeAgentSDK.CLI` supports bundled binary discovery at `priv/_bundled/claude*` (line 128-136)
- `@minimum_version "2.0.0"` at `lib/claude_agent_sdk/cli.ex:12`
- **Missing:**
  - No tracked "recommended/bundled CLI version" constant
  - No `mix` task for installing/bundling CLI

Design docs: `02_bundled_cli_version_and_installation.md`

### C) Docker-based e2e harness + filesystem-agents regression tests

Python:
- Adds `Dockerfile.test` + `scripts/test-docker.sh` + `.dockerignore`
- Adds CI job `test-e2e-docker` in `.github/workflows/test.yml`
- Adds e2e test `test_filesystem_agent_loading` in `e2e-tests/test_agents_and_settings.py`
- Adds example `examples/filesystem_agents.py` and fixture `.claude/agents/test-agent.md`

Elixir status:
- No Docker harness
- Integration tests exist (`@moduletag :integration`), excluded by default in `test/test_helper.exs:17`
- **No targeted regression test** for filesystem agents / `setting_sources`
- System init metadata (`agents`, `output_style`, `slash_commands`) only in `Message.raw`, not `Message.data`
  - `build_system_data(:init, raw)` at `message.ex:426-435` extracts limited fields

Design docs:
- `03_docker_e2e_test_infra.md`
- `04_filesystem_agents_regression.md`

## File/Module Mapping (Python → Elixir)

| Python change | Python file(s) | Elixir touchpoint(s) |
|--------------|----------------|----------------------|
| `UserMessage.uuid` surfaced | `types.py:565`, `message_parser.py:51,78,83`, `tests/test_message_parser.py` | `message.ex:347-351` (already parses); add unit test + optional `user_uuid/1` helper |
| Bundled CLI pin | `_cli_version.py` | Add constant to `cli.ex` or new `cli_version.ex`; optional mix task |
| Docker e2e harness | `Dockerfile.test`, `scripts/test-docker.sh`, `.github/workflows/test.yml` | Add root `Dockerfile.test`, `scripts/test-docker.sh`; optional CI job |
| Filesystem agent regression | `e2e-tests/test_agents_and_settings.py`, `examples/filesystem_agents.py`, `.claude/agents/test-agent.md` | Add integration test; consider exposing init metadata in `Message.data` |

## Proposed Implementation Order (Elixir)

1. **Add unit test for uuid parsing** - Test that `Message.from_json/1` extracts uuid into `data.uuid`
2. **(Optional) Add `Message.user_uuid/1` helper** - Convenience accessor for the checkpoint id
3. **Add CLI version constant** - `ClaudeAgentSDK.CLI.recommended_version/0` returning `"2.0.72"`
4. **Add filesystem agents regression test** - Tagged `@moduletag :integration`, reads init metadata from `Message.raw`
5. **Add Docker harness** - `Dockerfile.test` + `scripts/test-docker.sh` for running (4) in container
6. **(Optional) Improve init metadata ergonomics** - Expose `agents`, `output_style`, `slash_commands` in `Message.data`

## Acceptance Criteria

- Unit test confirms `Message.from_json/1` extracts `"uuid"` from user messages into `data.uuid`
- Developers can obtain checkpoint id via `message.data.uuid` (documented in existing examples)
- `ClaudeAgentSDK.CLI.recommended_version/0` returns `"2.0.72"` (or current bundled version)
- Integration test reproduces filesystem agent scenario: `setting_sources: ["project"]` + `.claude/agents/*.md` → asserts **init → assistant → result**
- Docker harness can run integration tests locally via `./scripts/test-docker.sh integration`

## Test Tagging Conventions (Elixir)

For clarity on how tests are organized and excluded:

| Tag | Meaning | Default behavior |
|-----|---------|------------------|
| `@moduletag :integration` | Requires real CLI but no live API | Excluded by `test/test_helper.exs:17` |
| `@moduletag :live` | Requires live API key | Excluded by `test/test_helper.exs:17` |
| `@moduletag :requires_cli` | Requires CLI discovery | Excluded in CI via `--exclude requires_cli` |

To run integration tests: `mix test --include integration`
To run live tests: `LIVE_TESTS=true mix test --include live`
