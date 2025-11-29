# Elixir Port Sync Plan (align with Python SDK 0.1.10)

## Python delta to absorb
- Bundled Claude Code CLI baked into the package with a tracked `_cli_version.py`, defaulting to the bundled binary but allowing overrides.
- Structured outputs: `output_format` accepts JSON Schema, CLI invoked with `--json-schema`, and `ResultMessage.structured_output` is parsed.
- Assistant error surfacing: assistant frames can carry an `error` discriminator.
- Hook quality-of-life: per-matcher `timeout` plumbed through initialize config; initialize request timeout made configurable via `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT`.
- Release flow changes: build scripts to download/bundle CLI, wheel retagging, and tests covering structured outputs.

## Current Elixir state (key gaps)
- CLI discovery in `lib/claude_agent_sdk/process.ex` only checks `claude` on PATH; no bundled binary support or version pin.
- Options only allow `:text | :json | :stream_json`; no JSON Schema passthrough or structured output field in `ClaudeAgentSDK.Message` / streaming events (`lib/claude_agent_sdk/message.ex`, `lib/claude_agent_sdk/streaming/event_parser.ex`).
- Hooks lack per-matcher timeout metadata (`lib/claude_agent_sdk/hooks/matcher.ex`, `build_hooks_config/2` in `lib/claude_agent_sdk/client.ex`); callback timeout is hardcoded to 60s.
- Initialize/control timeouts are implicit; no way to honor `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` for slower startups.
- Tests/docs/examples cover streaming + tools but not structured outputs or bundled CLI workflows.

## Action plan

### 1) Structured outputs (highest impact)
- Extend `ClaudeAgentSDK.Options` to accept a structured variant (e.g., `{:json_schema, map}` or `%{type: :json_schema, schema: map}`) and emit `--json-schema` in `Options.to_args/1` while keeping `--output-format stream-json` + `--verbose`.
- Update parsers to capture structured payloads:
  - Add `structured_output` to result data in `ClaudeAgentSDK.Message.build_result_data/2`.
  - Ensure streaming path emits a structured payload on `message_stop` when present (`lib/claude_agent_sdk/streaming/event_parser.ex`).
- Add tests:
  - Unit: options → args emits `--json-schema`; parsing a sample `result` JSON yields `structured_output`.
  - Integration/mock: mock CLI output with `structured_output` and assert `ContentExtractor` handles it; optionally a live e2e behind an env flag mirroring the Python suite.
- Document usage (README + OptionBuilder preset snippet) with a minimal schema example and cautions about CLI version requirements.

### 2) Hook and init resiliency
- Add `timeout_ms` (or seconds) to `Hooks.Matcher` and propagate into `build_hooks_config/2` so the control initialize payload matches Python’s `timeout` field.
- Use matcher or global timeout to drive the `Task.yield` window for hook/permission callbacks in `lib/claude_agent_sdk/client.ex` (fallback to 60s).
- Honor `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (ms) when waiting for initialize/control responses and/or streaming startup; expose a sane floor (60s) and make it overridable for slow MCP startups.
- Add regression tests around hook timeout serialization and callback timeout overrides.

### 3) Bundled CLI + version tracking
- Introduce a tracked CLI version constant (e.g., `lib/claude_agent_sdk/cli_version.ex`) and prefer a vendored binary (e.g., `priv/_bundled/claude*`) before PATH resolution in `process.ex` and streaming transports.
- Provide a mix task to download the CLI for the current platform and drop it into `priv/_bundled`; add `.gitignore` + checksum logging.
- Optionally extend `mix hex.build` packaging guidance to document when to bundle vs. rely on system installs; add a guard that warns if the detected CLI is older than the minimum supported version.
- Add unit tests for executable resolution (bundled first, PATH fallback) using temp dirs.

### 4) Test & docs lift
- Mirror the Python structured-output e2e coverage with a low-cost mock fixture and an opt-in live test target.
- Update changelog and `docs` to reflect the new capabilities and defaults (structured outputs, hook timeouts, bundled CLI).
- If feasible, add a CI job to exercise the download/bundle mix task on Linux/macOS/Windows without publishing artifacts.

## Open questions / dependencies
- Do we want to ship the bundled CLI in Hex releases or keep bundling as an opt-in developer task (size vs. convenience)?
- Should hook timeouts be per-matcher only, or also allow a global override in `Options`?
- For structured outputs, align on the schema shape we accept (`{:json_schema, map}` vs. map with atom/string keys) to minimize breaking changes for existing `output_format` users.
