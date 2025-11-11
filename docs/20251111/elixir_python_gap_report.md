# Elixir vs. Python SDK Gap Report — 2025-11-11

## Context
Anthropic’s public `claude-agent-sdk-python` repository (latest tag v0.1.6 on main) continues to evolve faster than our Elixir port. Recent marketing blurbs also hint at prompt caching and VM access, but no such code exists in the cloned Python repo (no references to "cache"/"prompt caching"/"virtual machine" across any fetched branches). The gaps below are all confirmed directly from the code we have locally.

## Gap 1 — Options Surface Area
- **Python**: `ClaudeAgentOptions` exposes budget caps, session controls, settings + plugin loading, CLI overrides, and thinking-token limits (`anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py:514-560`, wired via `_build_command` at `_internal/transport/subprocess_cli.py:96-229`).
- **Elixir**: `ClaudeAgentSDK.Options` + `to_args/1` top out at the older field set (`lib/claude_agent_sdk/options.ex:69-183` & `232-410`). Missing knobs: `max_budget_usd`, `continue_conversation`, `resume`, `setting_sources`, `settings`, `plugins`, `env`, `extra_args`, `user`, `cwd` enforcement beyond basic, and `max_thinking_tokens`. Users therefore cannot:
  - Cap spend or enforce thinking-token ceilings.
  - Resume/fork sessions the way the CLI expects.
  - Load `CLAUDE.md`/project-local settings or register plugin directories programmatically.
  - Pass arbitrary CLI flags (`extra_args`) or process-level env overrides.

**Impact**: parity claims in `PYTHON_SDK_COMPARISON.md` are inaccurate; production users lack key configuration levers that Anthropic itself advertises.

## Gap 2 — Transport Customisation & Environment Control
- **Python**: `SubprocessCLITransport` merges `options.env`, allows running as another OS user, streams stderr through callbacks, enforces `max_buffer_size`, maintains temp files for long `--agents` payloads, and respects `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK` (`anthropics/.../_internal/transport/subprocess_cli.py:200-314`).
- **Elixir**: `Transport.Port` and the fallback `Process` module hard-code a tiny env allowlist and offer zero hooks for stderr handling or custom user/env overrides (`lib/claude_agent_sdk/transport/port.ex:70-210`, `lib/claude_agent_sdk/process.ex:295-330`). No way to:
  - Inject plugin paths or secrets via `options.env`.
  - Subscribe to CLI stderr without reading from the Port manually.
  - Skip the CLI version check or set process ownership.

**Impact**: features that depend on environment shaping (plugins, custom MCP servers, alternate CLI installs) work in Python but cannot be reproduced from Elixir.

## Gap 3 — Runtime Control APIs *(Resolved Nov 2025)*
- **Python**: `ClaudeSDKClient` already exposes `interrupt()`, `set_permission_mode()`, `set_model()`, `get_server_info()`, and a bounded `receive_response()` helper (`anthropics/claude-agent-sdk-python/src/claude_agent_sdk/client.py:200-317`).
- **Elixir**: Parity reached in `lib/claude_agent_sdk/client.ex` with:
  - `Client.interrupt/1` wiring through the control protocol (`Protocol.encode_interrupt_request/1`, `Client.handle_call(:interrupt, ...)`).
  - `Client.get_server_info/1` returning the initialization payload cached during handshake.
  - `Client.receive_response/1` collecting a single response’s messages until the `:result` frame.

**Impact**: ✅ Addressed; runtime control parity now documented in `PYTHON_SDK_COMPARISON.md` and covered by `client_test.exs`.

## Gap 4 — Prompt Caching / VM Claims Not Reflected in Code
- No branch or file in `anthropics/claude-agent-sdk-python` mentions prompt caching, cache invalidation, or VM orchestration. Marketing copy referencing "80% lower costs" is not represented in the SDK sources we have. This likely lives in a private repo or is pending release; we should not advertise support until real APIs exist.

## Recommended Next Steps
1. **Options Parity**: extend `ClaudeAgentSDK.Options`, `OptionBuilder`, and `Options.to_args/1` to cover the Python fields. Thread the new data through `Transport.Port` and `Process` so CLI invocations receive budget caps, settings/plugins, env/user overrides, `extra_args`, and thinking-token limits.
2. **Transport Enhancements**: redesign `Transport.Port` to accept env/user/stderr hooks and configurable buffer sizes. Mirror Python’s ability to skip version checks and to inject temp files for large JSON payloads.
3. ~~**Runtime Control Methods**: add `Client.interrupt/1`, `Client.get_server_info/1`, and a bounded response helper. Ensure the control protocol layer actually sends the corresponding requests, and update `Transport.Port/Process` to propagate control messages reliably.~~ **Done (Nov 2025).**
4. **Documentation Hygiene**: refresh `PYTHON_SDK_COMPARISON.md` and README claims once the above land, explicitly noting which Python features remain unimplemented. Track any future prompt-caching/VM items separately until code exists.

## Appendix — References
- Python options struct & transport wiring: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/types.py:514-560`, `_internal/transport/subprocess_cli.py:96-314`.
- Elixir options + CLI args: `lib/claude_agent_sdk/options.ex:69-410`.
- Elixir transport/process env limitations: `lib/claude_agent_sdk/transport/port.ex:70-210`, `lib/claude_agent_sdk/process.ex:295-330`.
- Python client runtime APIs: `anthropics/claude-agent-sdk-python/src/claude_agent_sdk/client.py:200-317`.
- Elixir client API surface: `lib/claude_agent_sdk/client.ex:108-315`.
