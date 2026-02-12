# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.0] - 2026-02-11

### Added

- `c:ClaudeAgentSDK.Transport.interrupt/1` callback implementation in the Erlexec transport for cooperative interruption of active subprocess execution.

### Fixed

- Erlexec transport framing now handles UTF-8 text split across chunk boundaries without data loss or mojibake.
- Streaming parser now preserves incomplete multibyte UTF-8 suffix bytes between chunks until completion.
- Streaming session stderr processing now treats chunk boundaries in a binary-safe way.
- Added regression coverage for UTF-8 boundary handling and interrupt behavior in transport and streaming tests.

### Enhanced

- `Message.error_result/2` now supports structured error details via `:error_details` and `:error_struct` options. When a `ProcessError` struct is provided without explicit details, the system automatically populates `error_details` with exit code and stderr. Callers can also supply a custom details map via `:error_details`.

## [0.13.0] - 2026-02-11

### Added

#### Centralized Configuration System

- **`Config.Timeouts`**: All timeout values (client init, streaming, query, transport, auth, hooks, session cleanup) consolidated into a single module with runtime-overridable accessors. Replaces `@default_*` module attributes and inline literals across `Client`, `Streaming.Session`, `CLIStream`, `ClientStream`, `AuthManager`, `AuthChecker`, `Tool.Registry`, `Orchestrator`, `Hooks.Matcher`, `Transport.Erlexec`, and `Process`.
- **`Config.Buffers`**: Buffer sizes (`max_stdout_buffer_bytes`, `max_stderr_buffer_bytes`, `max_lines_per_batch`, `stream_buffer_limit`) and display truncation lengths (`error_preview_length`, `message_trim_length`, `error_truncation_length`, `summary_max_length`) centralized with runtime overrides.
- **`Config.Auth`**: Auth file paths (`token_store_path`, `session_storage_dir`), TTLs (`token_ttl_days`, `session_max_age_days`), token prefixes (`oauth_token_prefix`, `api_key_prefix`), and cloud credential paths (`aws_credentials_path`, `gcp_credentials_path`).
- **`Config.CLI`**: CLI version constraints (`minimum_version`, `recommended_version`), executable discovery (`executable_candidates`), install command, and shared streaming flag builders (`streaming_output_args`, `streaming_bidirectional_args`).
- **`Config.Env`**: Canonical registry of all environment variable names the SDK reads (`ANTHROPIC_API_KEY`, `CLAUDE_AGENT_OAUTH_TOKEN`, `CLAUDE_AGENT_USE_BEDROCK`, `CLAUDE_CODE_ENTRYPOINT`, etc.) and `passthrough_vars/0`. Eliminates bare string literals across modules.
- **`Config.Orchestration`**: Concurrency limits (`max_concurrent`), retry policies (`max_retries`, `backoff_ms`) with runtime overrides.

#### Config-Driven Model Registry

- **`Model` module rewritten**: Model validation, listing, and suggestion logic now reads from `Application.get_env(:claude_agent_sdk, :models)` at runtime instead of a compile-time `@known_models` module attribute. New models can be added via `Application.put_env` without recompilation.
- **`Model.known_models/0`**: Returns the merged map of all configured short forms and full IDs.
- **`Model.default_model/0`**: Returns the configured default model name.
- **`Model.short_forms/0`** and **`Model.full_ids/0`**: Return the configured short-form aliases and full model identifiers respectively.
- **Default model registry** in `config/config.exs`: Ships with `opus`, `sonnet`, `haiku`, `sonnet[1m]` short forms and their corresponding full IDs (`claude-opus-4-6`, `claude-sonnet-4-5-20250929`, `claude-haiku-4-5-20251001`, `claude-sonnet-4-5-20250929[1m]`). Default model: `"haiku"`.

#### Streaming Timeout Configurability

- **`Streaming.Session` respects `Options.timeout_ms`**: Session `send_message/2` stream timeout now uses the configured `timeout_ms` from options instead of a hardcoded 5-minute default. Added `:timeout_ms` GenServer call to expose the configured timeout.
- **Control client stream respects `Options.timeout_ms`**: `Streaming.stream_response/3` queries the client for its configured timeout via a new `GenServer.call(client_pid, :stream_timeout_ms)` and uses it for the stream receive loop.

#### Test Infrastructure

- **`ClaudeAgentSDK.Test.ModelFixtures`**: Shared model constants for tests (`test_model/0`, `test_model_alt/0`, `real_default_model/0`), eliminating hardcoded model strings scattered across test files.

### Changed

- **`Config` module doc updated**: Top-level `Config` module now documents its role as a facade and lists all sub-modules with their domains.
- **`Mock.default_response/0`**: Uses `Model.default_model()` instead of hardcoded `"claude-3-opus-20240229"`.
- **`ContentExtractor.summarize/2`**: Default `max_length` reads from `Buffers.summary_max_length()` instead of hardcoded `100`.
- **`Tool.Registry` timeout**: `execution_timeout_ms/0` reads from `Timeouts.tool_execution_ms()` instead of `Application.get_env(:claude_agent_sdk, :tool_execution_timeout_ms)`.
- **`TokenStore` storage path**: Falls back to `Config.Auth.token_store_path()` instead of a local `@default_path` attribute.
- **`SessionStore` defaults**: Storage dir and max age read from `Config.Auth` instead of local `@default_storage_dir` / `@max_age_days`.
- **Model references in examples and guides**: Updated from full model IDs (e.g., `"claude-opus-4"`, `"claude-sonnet-4"`) to short forms (`"opus"`, `"sonnet"`) throughout agent definitions, guides, and example code.
- **`ExDoc` groups updated**: Configuration group now lists all `Config.*` modules and `Model`.

### Documentation

- **New guide: Configuration Internals** (`guides/configuration-internals.md`): Complete reference for every tunable constant, its default, override examples, and design decisions (domain grouping, runtime functions vs module attributes).
- **New guide: Model Configuration** (`guides/model-configuration.md`): Config-driven model registry, adding custom models at runtime, overriding the default model, thinking tokens, test fixtures, and architecture diagram.
- Updated `configuration.md` with `Config.*` sub-module examples and link to Configuration Internals guide.
- Updated `agents.md`, `sessions.md`, `streaming.md`, `testing.md`, `getting-started.md`, and `mcp-tools.md` to use short-form model names.
- Updated `README.md` with `Config.*` override examples and version bump to `0.13.0`.

### Testing

- Added `Config.TimeoutsTest` — verifies all 30 timeout defaults and runtime override behavior.
- Added `Config.BuffersTest` — verifies all 8 buffer defaults and selective override.
- Added `Config.AuthTest` — verifies file paths, TTLs, prefixes, and runtime override.
- Added `Config.CLITest` — verifies version strings, executable candidates, and streaming arg builders.
- Added `Config.EnvTest` — verifies all environment variable name constants.
- Added `Config.OrchestrationTest` — verifies concurrency limits and retry defaults.
- Added `Streaming.SessionTimeoutTest` — verifies session timeout from `Options.timeout_ms` and fallback to default.
- Added control client stream timeout test in `StreamingFacadeTest`.
- Rewrote `ModelTest` to test config-driven behavior: runtime model additions, `short_forms/0`, `full_ids/0`, `known_models/0`, and `default_model/0`.
- Migrated all test files to use `ModelFixtures` (`test_model()` / `test_model_alt()`) instead of hardcoded model strings.
- Updated `Tool.RegistryTest` timeout test to override `Config.Timeouts` instead of flat `:tool_execution_timeout_ms` key.

## [0.12.0] - 2026-02-10

### Breaking Changes

> **Practical impact**: These changes affect internal transport plumbing. Users of the public API (`Client`, `CLIStream`, `Query`) are unaffected unless they directly referenced Transport modules or wrote custom transports.

- **`Transport.Port` removed**: The Erlang Port-based transport has been removed. `Transport.Erlexec` is now the sole built-in transport for all subprocess communication. All code paths already defaulted to Erlexec since 0.11.0. Users who explicitly passed `Transport.Port` must switch to `Transport.Erlexec` (or omit the transport option to use the default).
- **`Transport.normalize_reason(:port_closed)` removed**: The `:port_closed` -> `:not_connected` normalization has been removed. Custom transports should return `:not_connected` directly.
- **Transport error tuple shape updated**: low-level transport failures now use `{:error, {:transport, reason}}` instead of bare `{:error, reason}`.
- **Stdin-based prompt delivery**: String prompts are now sent via stdin as `stream-json` user messages with `--input-format stream-json`, instead of the previous `-- prompt` CLI arg. This unifies the prompt delivery path for all query types.
- **`--setting-sources ""` no longer emitted by default**: The empty value was disabling CLI-side persisted context including resume session lookup. Omitting it restores CLI defaults.
- **`session_id` removed from `resume_input/2` payload**: The CLI manages session binding via `--resume` flag, not per-message metadata.
- **`start/1` added as required Transport behaviour callback**: Custom transports using `@behaviour ClaudeAgentSDK.Transport` must now implement `start/1` (unlinked startup). Existing `start_link/1` remains required.

### Added

#### Transport Hardening (Erlexec)

- **`subscribe/3` tagged subscriptions**: Transport consumers can subscribe with `:legacy | reference()` and receive namespaced events (`{:claude_agent_sdk_transport, ref, event}`).
- **`force_close/1` transport callback**: Immediate shutdown API with `:exec.stop` + `:exec.kill(pid, 9)` escalation and 500ms timeout via `safe_call`.
- **`stderr/1` transport callback**: Retrieves bounded stderr capture from transport (returns `""` on error, matching amp_sdk).
- **`safe_call/3` task isolation**: All public API functions route through `TaskSupervisor.async_nolink` with yield/shutdown, protecting callers against transport death, timeout, and noproc conditions.
- **Queue-based stdout drain**: `pending_lines` `:queue` with `@max_lines_per_batch 200` and `:drain_stdout` self-message for backpressure control under burst output.
- **Bounded stderr buffer**: `max_stderr_buffer_size` with tail-truncation. Stderr events dispatched to subscribers in addition to callback.
- **Headless timeout auto-shutdown**: Configurable `headless_timeout_ms` auto-stops transport when no subscribers attach. Timer cancelled on first `subscribe` call.
- **Async send/end_input via IO tasks**: Tracked in `pending_calls` map, preventing blocking GenServer on risky stdin writes.
- **Deferred finalize exit**: 25ms delay timer allows late stdout to arrive before dispatching exit event. Drain loop flushes remaining queue before final exit dispatch.
- **`await_down/3`** (in `ProcessSupport`): Monitor-based process shutdown helper used by stream cleanup cascade.
- **`validate_command/1`**: Pre-launch command existence check returning `{:error, {:command_not_found, cmd}}`.

#### Transport Lifecycle

- **Split `start_link` into `start` + `Process.link`**: Cleaner error handling; catches `:badarg` from linking already-dead processes.
- **Deterministic `safe_call` cleanup**: Replaced `Task.yield/Task.shutdown` with direct `receive` on task ref. Added `maybe_kill_task/1` helper.
- **Bootstrap subscriber support**: `maybe_put_bootstrap_subscriber` in both Client and CLIStream pre-registers the caller before `start_link`, preventing message loss during subscribe race window.
- **CLIStream graceful close**: Rewritten `close_transport_with_timeout` waits for natural exit before escalating to `force_close` for Erlexec, reducing unnecessary SIGKILL sends.
- **ClientStream graceful close**: New `close_client_with_timeout` with monitor-based graceful shutdown replacing immediate `safe_stop`.

#### Client Resilience

- **Tolerant stream event parsing**: Replaced `Map.fetch!` with `Map.get` for `uuid` and `session_id` fields, preventing crashes on malformed events. Missing fields propagate as `nil`.

#### Bug Fixes

- **`mock_prompt_from/1` for string prompts**: Previously returned `nil` for binary prompts in mock mode, losing the prompt content. Now correctly returns the prompt string.

### Changed

- **Erlexec terminate rewrite**: Cancels finalize and headless timers with message flush, demonitors all subscribers, replies to pending callers with `{:error, {:transport, :transport_stopped}}`, force-stops subprocess, wrapped in try/catch.
- **Transport error normalization**: All bare `{:error, :send_failed}` and `{:error, :not_connected}` replaced with `{:error, {:transport, reason}}` via `transport_error/1` wrapper.
- **Subscriber storage**: Changed from `%{pid => ref}` to `%{pid => %{monitor_ref: ref, tag: tag}}` for tagged dispatch support.
- **CLIStream tagged dispatch**: Migrated to `make_ref()` subscription and `{:claude_agent_sdk_transport, ref, event}` pattern matching.
- **CLIStream cleanup cascade**: 4-stage monitor-based: `safe_force_close` -> `await_down(250ms)` -> `Process.exit(:shutdown)` -> `await_down(250ms)` -> `Process.exit(:kill)` -> `await_down(250ms)` -> `demonitor`. For Erlexec, waits for natural exit first before escalating.
- **Streaming readability**: Extracted inline `Stream.resource` next-fn into named `next_control_client_stream_state/1`.

### Removed

- **`Transport.Port` module** (661 lines), its test file, and Port-related test cases from `env_parity_test.exs`, `process_env_test.exs`, and `user_option_test.exs`.
- **`Transport.normalize_reason(:port_closed)` clause**.
- **Port references** from `default_transport_module/1`, `needs_cli_command?/2`, `normalize_transport/3`, `graceful_close?/1` in `cli_stream.ex`.

### Documentation

- Updated CUSTOM_TRANSPORTS.md error contract from `{:error, {:transport_failed, reason}}` to `{:error, {:transport, reason}}`.
- Updated CUSTOM_TRANSPORTS.md with new `subscribe/3`, `force_close/1`, `stderr/1` callbacks and Transport behaviour reference.
- Updated RUNTIME_CONTROL.md with `{:error, {:transport, reason}}` shapes and removed Port references.
- Updated README, getting-started, streaming, configuration, and error-handling guides to reference only Erlexec.
- Added R1 collector and R2 red team review reports for erlexec consolidation.

### Testing

- Added `force_close` stop and error-after-exit tests.
- Added `safe_call` transport-death isolation test.
- Added tagged and legacy subscriber dispatch tests.
- Added stderr event dispatch to tagged subscribers test.
- Added burst output queue drain tests (500 lines, 5 subscribers × 300 lines).
- Added `stderr/1` capture and buffer bounding tests.
- Added headless timeout auto-stop and cancel-on-subscribe tests.
- Added subscriber lifecycle auto-stop-on-last-down test.
- Added CLIStream cleanup test with signal-trapping stubborn subprocess.
- Added finalize drain responsiveness test via `:sys.replace_state`.
- Added `validate_command/1` error path test (nonexistent command).
- Added Erlexec buffer overflow test (`CLIJSONDecodeError` on `max_buffer_size` exceeded).
- Added multiple concurrent subscriber broadcast test.
- Added `start/1` callback to mock transports and test transport modules.
- Migrated `stderr_callback_test.exs` from Port to Erlexec transport.
- Converted crash-on-missing-uuid/session_id tests to resilience tests.
- Updated tagged/legacy subscriber tests to use stdin-driven scripts.
- Updated options test for `--setting-sources` default change.
- Updated resume persistence test for `session_id` removal.

## [0.11.0] - 2026-02-06

### Breaking Changes

- **`--print` flag removed**: The `--print` CLI flag has been removed from all modules (`CLIStream`, `Query`, `Streaming.Session`, `Transport.Port`, `Transport.Erlexec`, `Process`). All queries now use `--output-format stream-json` exclusively. This aligns with Python SDK v0.1.24.
- **`--agents` CLI flag removed**: Agents are no longer passed via `--agents` CLI argument. They are now sent through the `initialize` control request. `Options.to_args/1` no longer emits `--agents`. Use `Options.agents_for_initialize/1` to get the agents map for the initialize request.
- **`AgentsFile` module deleted**: `ClaudeAgentSDK.Transport.AgentsFile` has been removed along with all `temp_files` tracking across transports.
- **Client state is now a defstruct**: `Client` state is a `%Client{}` struct instead of a bare map. Four deprecated fields removed: `current_model`, `pending_model_change`, `current_permission_mode`, `pending_inbound_count`.

### Added

#### Hooks & Lifecycle

- **6 new hook events**: `PostToolUseFailure`, `Notification`, `SubagentStart`, `PermissionRequest`, `SessionStart`, `SessionEnd` — all 12 hook events from the Python SDK are now supported.
- **Enhanced hook input fields**: `hook_input` type now includes fields for all new events: `error`, `is_interrupt`, `message`, `title`, `notification_type`, `agent_id`, `agent_type`, `agent_transcript_path`, `permission_suggestions`, `permission_mode`, `source`, `reason`, `trigger`, `custom_instructions`, `stop_hook_active`.
- **New hook output helpers**: `Output.with_additional_context/2`, `Output.with_updated_mcp_output/2`, `Output.permission_decision/1`, `Output.permission_allow/0`, `Output.permission_deny/1`.
- **Subscriber lifecycle monitoring**: `Client` and `Streaming.Session` now monitor subscriber processes and automatically remove dead subscribers, preventing message sends to terminated processes.

#### MCP & Tools

- **MCP tool annotations**: `deftool` macro now accepts a 5th argument with options including `:annotations` for MCP tool annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`, `title`). Annotations are included in `tools/list` responses.
- **MCP status API**: `Client.get_mcp_status/1` sends a `mcp_status` control request and returns the MCP server status.
- **Async MCP dispatch**: SDK MCP `tools/call` requests are dispatched asynchronously via `TaskSupervisor`, so long-running tool execution no longer blocks the `Client` callback path.
- **DynamicSupervisor for Tool.Registry**: `create_sdk_mcp_server/1` accepts a `:supervisor` option to start the tool registry under your own `DynamicSupervisor`.
- **Async tool execution**: `Tool.Registry` executes tools in async tasks with configurable timeout via `tool_execution_timeout_ms`.
- **`tool_use_result` field**: User messages now parse the `tool_use_result` field from CLI JSON.

#### Transport & Startup

- **Lazy transport startup**: `Transport.Port`, `Transport.Erlexec`, and `Streaming.Session` support `startup_mode: :lazy` to defer subprocess startup to `handle_continue/2`. `start_link` returns before the subprocess is spawned; startup failures surface as process exit after init.
- **Transport reason normalization**: `Transport.normalize_reason/1` maps equivalent reasons to stable atoms (`:port_closed` → `:not_connected`, `{:command_not_found, "claude"}` → `:cli_not_found`).
- **Immediate error surfacing**: Control-client startup/send failures surface as immediate `%{type: :error}` stream events instead of waiting for the 5-minute stream timeout. Input-stream worker crashes also surface immediately.

#### Auth & Config

- **Async AuthManager**: `setup_token/0` and `refresh_token/0` run in background tasks. The `AuthManager` GenServer stays responsive while setup is in progress. Concurrent callers wait for the same in-flight setup.
- **`Config` module**: New `ClaudeAgentSDK.Config` module centralizes application env reads.
- **`Transport.Setup` module**: Shared transport setup logic extracted into a dedicated module.

#### Client & Session

- **`Client.await_initialized/2`**: Proper `GenServer.call`-based wait for client initialization, replacing the old polling loop.
- **Per-client `control_request_timeout_ms`**: Configurable timeout for individual control requests.
- **`agents_for_initialize/1`**: New public function on `Options` to convert agents map to CLI format for the initialize control request.
- **`Message.error_result/2`**: Standardized constructor for error result messages.

#### Shared Modules

- **`Runtime` module**: Shared runtime utilities extracted from multiple modules.
- **`Shell` module**: Shell command execution utilities.
- **`Transport.ExecOptions` module**: Shared exec option building for both transports.

### Changed

- **Agents via initialize**: Agent definitions are now sent through the control protocol `initialize` request instead of `--agents` CLI flag. This avoids ARG_MAX limits and aligns with Python SDK v0.1.19.
- **Continue/resume routing**: `Query.continue/2` and `Query.resume/3` now route through the control client when hooks, SDK MCP servers, or `can_use_tool` are configured, ensuring agents are properly sent via initialize.
- **`encode_initialize_request/4`**: Now accepts an optional 4th `agents` parameter.
- **SessionStore ETS access**: ETS table changed from `:public` to `:protected` for data isolation.
- **SessionStore deferred hydration**: On-disk session cache is hydrated in `handle_continue/2` for faster startup.
- **Transport `unsubscribe/2`**: New function on erlexec transport for explicit subscriber removal.

### Fixed

- **Atom exhaustion in TokenStore**: `String.to_atom/1` on JSON provider data replaced with a provider whitelist, preventing unbounded atom creation.
- **Permission struct enforcement**: `@enforce_keys` added to `Permission.RuleValue` and `Permission.Update` structs.
- **`clear_auth/0` error handling**: Return type changed to `:ok | {:error, term()}`, propagating storage errors to callers.
- **Process.alive? race**: Replaced `Process.alive?` checks with `try`/`:exit` guards in subscriber notification paths.
- **Stale temp file cleanup**: `AgentsFile` cleanup of stale temp files (before module deletion).

### Removed

- **`AgentsFile` module**: Entirely removed — agents are now sent via `initialize`.
- **4 deprecated Client state fields**: `current_model`, `pending_model_change`, `current_permission_mode`, `pending_inbound_count`.

## [0.10.0] - 2026-02-05

### Fixed

- **Resume turn persistence**: `resume/3` no longer uses `--print --resume` (one-shot mode) which dropped intermediate turns from the CLI session history. It now uses `--resume` with `--input-format stream-json` and sends the user prompt via stdin, preserving the full conversation across resume calls.
- **Transport exit race**: `CLIStream` now defers halt on `:transport_exit` when the transport process is still alive, preventing premature stream termination before all messages are drained.
- **Erlexec stdout flush on exit**: The erlexec transport now flushes any remaining `stdout_buffer` before broadcasting `:transport_exit`, ensuring no final message is lost.
- **Stale transport messages**: `CLIStream` drains leftover `:transport_message`, `:transport_error`, and `:transport_exit` messages from the caller's mailbox before starting a new transport, preventing cross-stream contamination.
- **Graceful transport close**: Transport shutdown now waits briefly for the process to exit on its own before force-closing, avoiding premature kills that could drop in-flight data.

### Changed

- **Default Opus model**: Updated `"opus"` alias from `claude-opus-4-1-20250805` to `claude-opus-4-6` across model map, guides, and tests.

### Added

- **Resume persistence repro**: New `examples/resume_persistence_repro_live.exs` live example that verifies intermediate turns survive across `resume/3` calls (known-failing until upstream CLI fix).
- **Resume persistence unit test**: New `QueryResumePersistenceTest` asserting that `resume/3` avoids one-shot `--print` mode and sends `stream-json` input.

## [0.9.2] - 2026-01-28

### Fixed

- **AuthChecker exec timeout**: Fixed `run_command_with_timeout/2` passing `{:timeout, ms}` inside the options list to `:exec.run/2`, which does not accept that tuple as an option. This caused `:exec.run` to return `{:error, {:invalid_option, {:timeout, 30000}}}`, making `authenticated?/0` return `false` even when the CLI is installed and authenticated. The fix uses `:exec.run/3` with the timeout as a separate third argument.

### Tests

- **Exec timeout regression test**: Added `AuthCheckerExecTimeoutTest` verifying that the erlexec call pattern does not produce `{:error, {:invalid_option, _}}`.

## [0.9.1] - 2026-01-23

### Added

- **Task Supervisor Strict Mode**: Optional `task_supervisor_strict` config to raise when a configured supervisor is missing.
- **OTP Supervision Compliance**: Added proper supervision for all async callback execution
  - Created `ClaudeAgentSDK.TaskSupervisor` module for supervised task execution
  - Consumers can optionally add this to their supervision tree for full OTP compliance
  - Automatic fallback to unlinked spawn when supervisor is not available
- **Callback Crash Handling**: Client now properly handles callback task crashes
  - Added `Process.monitor/1` for all callback tasks
  - New `handle_info({:DOWN, ...})` clause detects crashes
  - Error responses automatically sent when callbacks crash
  - Pending callbacks map properly cleaned up on crash
- **Callback Crash Tests**: New test file `client_callback_crash_test.exs` covering:
  - Hook callback crashes with raise
  - Hook callback crashes with exit
  - Client continues operating after callback crash
  - Permission callback crash handling
  - Monitor ref cleanup after normal completion

### Fixed

- **Task Supervisor Fallback**: Missing supervisors now fall back to `Task.start/1` instead of raw `spawn/1`.
- **Callback :DOWN Handling**: Treat `:shutdown` reasons and cancelled signals as non-crash cleanup paths.
- **Callback Error Messages**: CLI-facing error messages now use bounded exit formatting.
- **Callback :DOWN Handling**: Ignore normal task exits to avoid false error responses when callback results are still pending.
- **Task Supervisor Naming**: Custom `task_supervisor` configuration now starts tasks under the configured supervisor name reliably.
- **Critical OTP Violations**: Fixed 3 `Task.start/1` unsupervised process spawns:
  - `client.ex:2143` - Hook callback execution now uses `TaskSupervisor.start_child/2`
  - `client.ex:2213` - Permission callback execution now uses `TaskSupervisor.start_child/2`
  - `cli_stream.ex:178` - Input streaming now uses `TaskSupervisor.start_child/2`
- **Documentation Anti-Pattern**: Fixed Phoenix LiveView example in `streaming.ex` to use `Task.Supervisor.start_child/3` instead of `spawn_link/1`

### Changed

- **Pending Callbacks State**: Now stores `monitor_ref` in addition to `pid`, `signal`, and `type`
- **Callback Cleanup**: `pop_pending_callback/2` now demonitors the callback process
- **Cancel Cleanup**: `cancel_pending_callbacks/1` now demonitors all callback processes before killing them

### Documentation

- **Supervision Guidance**: Added strict-mode and fallback behavior notes in README and hooks guide.
- **Supervision Guidance**: Added TaskSupervisor usage notes in README and Hooks guide.

### Tests

- **Abnormal :DOWN**: Added coverage for non-normal callback task exits.
- **Fallback Task Identity**: Added coverage that fallback uses Task processes.
- **Callback :DOWN Race**: Added coverage to ensure normal exits do not emit error responses.
- **Custom Task Supervisor**: Added coverage for custom supervisor configuration paths.

## [0.9.0] - 2026-01-17

### Added

- **Subagent Streaming Support**: Streaming events now include `parent_tool_use_id` field to identify which Task tool call produced each event, enabling hierarchical UIs that route subagent output to separate panels.
- **Subagent Streaming Example**: Added `examples/streaming_tools/subagent_streaming.exs` demonstrating how to distinguish main agent vs subagent streaming output.

### Breaking Changes

- **StreamEvent Wrapper Validation**: Stream event wrappers now require `uuid` and `session_id` keys (missing fields raise) to match Python SDK behavior.

### Fixed

- **EventParser parent_tool_use_id Preservation (Session Path)**: Fixed `EventParser.unwrap_stream_event/1` discarding the `parent_tool_use_id` field from the CLI's `stream_event` wrapper.
- **Client parent_tool_use_id Preservation (Control Client Path)**: Fixed `Client.handle_decoded_message(:stream_event, ...)` discarding the `parent_tool_use_id` field when processing stream events via the control client transport.
- **Streaming message_to_event parent_tool_use_id**: Fixed `Streaming.message_to_event/2` to extract `parent_tool_use_id` from the Message struct's data field instead of hardcoding `nil`, enabling subagent output to preserve its parent tool context.
- **StreamEvent Metadata Preservation**: Streaming events now retain `uuid`, `session_id`, and `raw_event` metadata across both session and control-client paths, aligning with Python SDK StreamEvent parity.
- **Examples Reliability**: Updated the mock streaming demo to read raw stream event types and added a short retry when verifying Write tool output in the permissions live example.

## [0.8.1] - 2026-01-14

### Added

- **Init Readiness API**: Added `Client.await_init_sent/2` to block until the initialize request is sent, enabling deterministic test synchronization without flaky mailbox timing.
- **Pre-Subscriber Buffering**: Inbound stream events and SDK messages are now buffered until the first subscriber attaches, preventing dropped events during async startup.
- **Buffer Limit Option**: Added `stream_buffer_limit` option to `Options` (default: 1000) controlling max buffered entries before first subscriber; oldest entries are dropped when limit is exceeded.

### Changed

- **Test Timeouts**: Increased init message assertion timeouts from 200ms to 1000ms across client tests for reliability under load.
- **Test Patterns**: Replaced flaky `assert_receive {:mock_transport_send, init_json}` patterns with `Client.await_init_sent/2` followed by explicit message consumption.

### Fixed

- **Intermittent Test Failures**: Resolved race conditions caused by async `handle_continue` initialization where init messages arrived after short `assert_receive` timeouts.
- **Stream Event Drops**: Fixed stream events being silently dropped when `active_subscriber` was nil by auto-assigning first subscriber as active and flushing buffered events.
- **Legacy Subscribe**: Legacy `{:subscribe}` call now sets `active_subscriber` when nil and flushes pending inbound buffer to prevent indefinite buffering.

## [0.8.0] - 2026-01-12

### Added

- **Streaming Termination Logic**: Added `ClaudeAgentSDK.Streaming.Termination` for shared stop_reason tracking with message_start resets.
- **Session Test Injection**: Added `mock_stream` support and `Session.push_events/2` for deterministic session streaming tests.
- **Streaming Tests**: Added unit tests for termination logic and multi-turn tool streaming coverage across session and control client paths.
- **Streaming Examples**: Added live examples for stop_reason probing and session-path multi-turn tool streaming.
- **SDK Log Level**: Added `ClaudeAgentSDK.Log` with configurable `log_level` (default: `:warning`) for SDK-scoped log filtering.
- **Permission Modes**: Added `:delegate` and `:dont_ask` permission modes for parity with the current Claude CLI.

### Changed

- **Logging Defaults**: SDK logging now respects `:log_level` configuration for quieter default output.
- **Examples Index**: Updated `examples/run_all.sh` and `examples/README.md` to include the new streaming examples.
- **Live Examples**: Streaming/tool demos now fail fast when required tool calls or outputs are missing.
- **Streaming Partials**: `can_use_tool` now enables `include_partial_messages` to surface tool events during streaming.
- **Permission Prompt Tool**: `can_use_tool` now auto-configures `permission_prompt_tool` to `\"stdio\"` for control-protocol callbacks (parity with Python SDK).

### Fixed

- **Multi-Turn Tool Streaming**: Streams now continue after `message_stop` with `stop_reason: "tool_use"` in both control client and session paths.
- **Control Client Init**: Streaming now waits for control client initialization before sending messages to avoid dropped callbacks.
- **Stop Reason Staleness**: Stop reasons reset on `message_start` to avoid stale `tool_use` carryover across messages.
- **SDK MCP Streaming Output**: Tool input deltas are now rendered coherently instead of repeated partial lines.
- **Permission Callback Bridge**: Permission callbacks now run via PreToolUse hooks when the CLI does not emit `can_use_tool` requests (with `updated_permissions` ignored in that path and disabled in `:delegate`).

## [0.7.6] - 2026-01-07

### Added

- **Comprehensive Application Examples**: Added five production-ready example applications to `examples/` demonstrating advanced patterns:
  - **Phoenix Chat** (`examples/phoenix_chat`): Full Phoenix LiveView application with real-time WebSocket streaming, GenServer session management, and tool usage visualization.
  - **Document Generation** (`examples/document_generation`): AI-powered Excel creation utility using `elixlsx`, featuring natural language parsing, complex formula generation, and professional styling.
  - **Research Agent** (`examples/research_agent`): Sophisticated multi-agent coordination system with specialized subagents, hook-based lifecycle tracking, and parallel task execution.
  - **Email Agent** (`examples/email_agent`): Intelligent email assistant integrating IMAP access, SQLite persistence, automation rules, and natural language query processing.
  - **Skill Invocation** (`examples/skill_invocation`): Focused demonstration of the Skill tool, utilizing custom hook callbacks for invocation tracking and execution statistics.

### Changed

- **Documentation**: Updated `README.md` with a new "Full Application Examples" section detailing the new example projects.
- **ExDoc Configuration**: Updated `mix.exs` to include the README files from all new example applications in the generated documentation.

## [0.7.5] - 2026-01-07

### Added

- **Mix Task Example App**: New `examples/mix_task_chat/` - a complete working example demonstrating SDK integration in Mix tasks
  - `mix chat` - Streaming chat task with real-time typewriter output, interactive multi-turn conversations, and tool support
  - `mix ask` - Simple query task for scripting with quiet mode and JSON output options
  - Comprehensive README tutorial with architecture diagrams, code walkthroughs, and troubleshooting guide
  - Proper project structure with mix.exs, .formatter.exs, and comprehensive .gitignore

### Changed

- **Documentation**: Updated main README.md with prominent "Mix Task Example (Start Here)" section
- **Documentation**: Updated examples/README.md with "Mix Task Example (Recommended Starting Point)" section at top
- **ExDoc Configuration**: Added examples/README.md and examples/mix_task_chat/README.md to documentation extras
- **ExDoc Menu**: New "Examples" group in documentation sidebar with index and tutorial links
- **Hex Package**: Added `examples/mix_task_chat` to package files for inclusion in hex package
- **Dependencies**: Updated credo 1.7.12→1.7.15, dialyxir 1.4.5→1.4.7, erlexec 2.2.0→2.2.2, ex_doc 0.38.2→0.39.3, supertester 0.4.0→0.5.0
- **Mix Config**: Fixed deprecated `preferred_cli_env` warning by migrating to `def cli` block

### Fixed

- **Dialyzer**: Fixed invalid `timeout` option in `System.cmd/3` call in DebugMode
- **Dialyzer**: Fixed boolean guard expressions using `and` instead of `&&` for nil safety
- **Credo**: Replaced `length(list) > 0` with `list != []` for efficiency across codebase
- **Credo**: Fixed alias ordering to be alphabetical in Streaming and test modules
- **Credo**: Suppressed intentional struct field count warning in Options module

## [0.7.4] - 2025-12-31

### Added

- **Base Error Hierarchy Utilities**: Added `Errors.sdk_error?/1` and `Errors.category/1` functions for programmatic error handling (Python SDK parity)
  - `sdk_error?/1` returns true for any SDK error type
  - `category/1` returns error category (`:connection`, `:process`, `:parse`, `:generic`)
- **Guard Macro for SDK Errors**: New `ClaudeAgentSDK.Errors.Guards` module with `is_sdk_error/1` guard macro for pattern matching SDK errors in function heads and case clauses
- **Simple Schema Map Syntax**: Extended `Tool.simple_schema/1` to support map syntax for Python parity
  - Supports atom keys: `simple_schema(%{a: :float, b: :float})`
  - Supports string keys: `simple_schema(%{"name" => :string})`
  - Supports Elixir module types: `String`, `Integer`, `Float`
- **`Output.with_updated_input/2` Helper**: New helper for PreToolUse hooks to modify tool input before execution
- **SSE and HTTP MCP Server Types**: Added new MCP server transport types for remote servers
  - `:sse` - Server-Sent Events transport with `url` and optional `headers`
  - `:http` - HTTP transport with `url` and optional `headers`
- **`Transport.Port.end_input/1` Implementation**: Transport.Port now implements the `end_input/1` callback for stdin EOF signaling

### Changed

- Transport behaviour `end_input/1` is now implemented by Transport.Port (previously only Erlexec)

## [0.7.3] - 2025-12-31

### Added

- **ClaudeSDKError Base Exception**: Added `ClaudeAgentSDK.Errors.ClaudeSDKError` base exception for catch-all error handling (Python SDK parity)
- **Output.async/1 Helper**: Added `Output.async/1` and `Output.with_async_timeout/2` helpers for asynchronous hook processing
- **Tool.simple_schema/1 Helper**: Added `Tool.simple_schema/1` helper to reduce boilerplate when defining MCP tool schemas
  - Supports list of atoms (all string, all required)
  - Keyword list with types (`:string`, `:number`, `:integer`, `:boolean`, `:array`, `:object`)
  - Optional descriptions and optional field markers
- **Transport.end_input/1 Callback**: Added `end_input/1` as optional callback in Transport behaviour for signaling stdin EOF

### Changed

- **Stream Diagnostics**: CLIStream now tracks `received_first_message?` and `received_result?` for better error context
- **Documentation**: Updated guides for hooks, MCP tools, and error handling with new features

## [0.7.2] - 2025-12-29

### Fixed

- **Buffer Limits**: Enforced `max_buffer_size` hard limit across transports and sync parsing with `CLIJSONDecodeError` on overflow (G-011)
- **MCP Methods**: `resources/list` and `prompts/list` now return JSON-RPC method-not-found errors (G-014)
- **MCP Tool Names**: Registry and routing keep tool names as strings, avoiding atom leaks (G-015)
- **Message Parsing**: Unknown message types/subtypes no longer crash or create atoms (G-016)
- **Hooks Validation**: Unsupported hook events are rejected to match Python SDK parity (G-020)

### Changed

- **SDK MCP Server Defaults**: `create_sdk_mcp_server/1` defaults `version` to `"1.0.0"` when omitted (G-019)
- **Documentation**: Updated README, guides, parity matrix, and examples for 0.7.2 parity

## [0.7.1] - 2025-12-29

### Added

- **Python SDK Parity**: Full gap analysis and alignment with official Python SDK
  - `Permission.Update` struct for programmatic permission rule management
  - `Permission.RuleValue` struct for permission rule definitions
  - `Permission.Result` now accepts `Update.t()` structs in `updated_permissions`
  - Types: `:user_settings`, `:project_settings`, `:local_settings`, `:session` destinations
  - Types: `:add_rules`, `:replace_rules`, `:remove_rules`, `:set_mode`, `:add_directories`, `:remove_directories` update types
- **Documentation**: Added `@moduledoc` to all error struct modules (`CLIConnectionError`, `CLINotFoundError`, `ProcessError`, `CLIJSONDecodeError`, `MessageParseError`)
- **Typespecs**: Added `@spec` to `Message.error?/1` and `Message.session_id/1`
- **Gap Analysis Docs**: Comprehensive SDK comparison documentation in `docs/20251229/`

### Fixed

- **Release Compatibility**: Removed all runtime `Mix.env()` calls that caused `UndefinedFunctionError` in OTP releases (fixes #4)
  - Logging conditionals in `Client`, `AuthManager`, `Tool.Registry` now use Logger directly
  - Environment detection in `OptionBuilder` and `DebugMode` uses compile-time `@env` attribute
- **Error Handling**: Improved error handling across the codebase
  - `Transport.AgentsFile`: Now logs warnings instead of silently swallowing file errors
  - `Message.from_json/1`: Returns structured `{:error, {:parse_error, reason}}` instead of raw exception
  - `Query.ClientStream`: Logs specific error details before returning generic `:client_not_alive`
- **Documentation**: Fixed `Model.validate/1` examples that showed incorrect return values
- **Types**: Fixed `Client.state` type - removed legacy `[pid()]` variant from `subscribers` field

### Python SDK Parity Notes

Features already present in Elixir SDK matching Python SDK:
- `Client.get_server_info/1` - Returns initialization info from CLI
- CLI version check with minimum version warning (2.0.0+)
- `CLAUDE_CODE_ENTRYPOINT=sdk-elixir` environment variable
- `CLAUDE_AGENT_SDK_VERSION` environment variable for telemetry
- Windows command length limit handling (8000 char limit with temp file fallback)
- `control_cancel_request` handling for cooperative callback cancellation

## [0.7.0] - 2025-12-29

### Added
- Subagents: Added `subagent_spawning_live.exs` example demonstrating parallel orchestration via the Task tool.
- Web Tools: Added `web_tools_live.exs` example for `WebSearch` and `WebFetch` usage.
- API: Added `ClaudeAgentSDK.list_sessions/1` to list persisted sessions.

### Changed
- MCP Protocol: Updated `Client` to nest SDK MCP responses (`response.response.mcp_response`) to match Python SDK/CLI parity.
- CLI Args: Updated `Options` to pass in-process SDK MCP servers to the CLI via `--mcp-config` to ensure tool discovery.
- Testing: Introduced `:live_cli` tag to better isolate tests that spawn real processes.

### Documentation
- Overhaul: Refactored root-level documentation into comprehensive `guides/` (Streaming, Hooks, Permissions, Agents, etc.).
- Cleanup: Removed legacy root markdown files (`AGENTS.md`, `COMPREHENSIVE_MANUAL.md`, `HOOKS_GUIDE.md`, etc.).
- ExDoc: Updated configuration with organized groups for modules and guides.

## [0.6.10] - 2025-12-24

### Fixed

- Fixed `mix claude.setup_token` crashing with `invalid option :timeout` error - `System.cmd/3` does not support the `:timeout` option
- Fixed `mix claude.setup_token` not opening browser - was clearing environment variables needed for browser launch
- Changed token setup to prompt-based flow since Claude CLI requires interactive TTY (Ink/React UI)
- Token input now loops on invalid format or empty input instead of crashing
- Cleaned up setup messaging to be consistent and minimal

## [0.6.9] - 2025-12-23

### Added

- README: API comparison table showing when to use `query/2` vs `Streaming` vs `Client`
- README: Available models documentation (sonnet, opus, haiku)
- README: Message types reference (`:system`, `:assistant`, `:tool_use`, `:tool_result`, `:result`)
- README: Full example for multi-turn agent with real-time output using `Client` + `Task.async` pattern

### Fixed

- Improved debug logging for failed transport message decoding - now shows payload preview (first 500 chars) instead of just the error reason

## [0.6.8] - 2025-12-20

### Changed

- Bumped recommended Claude CLI version from 2.0.72 to 2.0.75

### Python SDK Parity

- Ports CLI version tracking from Python SDK commits `57e8b6e` and `3eb12c5`
- Recommended CLI version updated to 2.0.75 (tested and verified)

## [0.6.7] - 2025-12-17

### Added

- `ClaudeAgentSDK.CLI.recommended_version/0` - Returns recommended CLI version (2.0.72)
- `ClaudeAgentSDK.Message.user_uuid/1` - Helper to extract checkpoint UUID from user messages
- Unit tests for user message UUID parsing
- Integration test for filesystem agents loaded via `setting_sources`
- Docker test infrastructure (`Dockerfile.test`, `scripts/test-docker.sh`)

### Changed

- Improved documentation for file checkpointing workflow

### Python SDK Parity

- Ports changes from Python SDK f834ba9..0434749 (v0.1.17-v0.1.18)
- Adds UUID parsing test parity with `test_parse_user_message_with_uuid`
- Adds CLI version tracking parity with `_cli_version.py`
- Adds filesystem agents regression test parity with `test_filesystem_agent_loading`

## [0.6.6] - 2025-12-14

### Added

- Python parity audit implementations across options, control protocol, transports, message parsing, and error handling.
- New erlexec-backed transport to support OS-level user execution when `Options.user` is set.
- Structured error structs for CLI discovery, connection/start failures, subprocess exits, JSON decode failures, and message parse errors.

### Fixed

- Options CLI arg parity: always emit `--setting-sources ""` and `--system-prompt ""` when unset; add preset `system_prompt` shapes and `--append-system-prompt` support.
- Control protocol parity: camelCase permission response keys (`updatedInput`, `updatedPermissions`), MCP subtype/key compatibility, and bounded control request timeouts with cleanup.
- Transport parity: CLI discovery locations and bundled lookup, `PWD` env propagation, cwd missing-directory errors (no implicit mkdir), large `--agents` payload `@file` fallback, and stderr callback routing.
- Message parsing parity: usage extraction, `parent_tool_use_id` extraction, and stream event typing for streaming consumers.

## [0.6.5] - 2025-12-13

### Added

- Options parity with Python v0.1.12+: `tools` (`--tools`) base tools selection and `betas` (`--betas`) beta feature flags.
- Sandbox settings parity with Python v0.1.12+: `sandbox` merged into `--settings` as JSON when present.
- File checkpointing parity with Python v0.1.15+: `enable_file_checkpointing` env propagation plus `Client.rewind_files/2` and `rewind_files` control request encoding.

### Fixed

- Assistant error parsing now prefers `message.error` (with root-level fallback) to enable rate-limit detection parity with Python v0.1.16+.

### Changed

- No explicit write lock added for transport writes: GenServer serialization already prevents the Python Trio concurrency issue.

## [0.6.4] - 2025-11-29

### Added

- Cooperative cancellation for hooks and permission callbacks via `control_cancel_request`, abort signals passed into callback contexts, and pending callback tracking.
- SessionStart, SessionEnd, and Notification hook events are now validated and supported.
- SDK MCP routing now replies to `resources/list`, `prompts/list`, and `notifications/initialized` for forward compatibility.
- New example: `examples/archive/runtime_control/cancellable_callbacks.exs` demonstrating abortable callbacks.

### Changed

- Pending callbacks are cancelled during shutdown to avoid leaked work when transports or clients stop.

### Added

- Centralized Claude CLI discovery/version tracking via `ClaudeAgentSDK.CLI` (ADR 0005a), with min-version warning and shared lookup across Process/Streaming/Client/Transport/AuthChecker.
- Initialize control wait now honors `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (ms) with a 60s floor (parity with Python) and is documented for operators handling slow MCP/server startups.
- Updated live structured output example and documentation to highlight the new initialization timeout override for real CLI runs.
- Hook matcher timeouts (ADR 0002): per-matcher `timeout_ms` flows to `"timeout"` in initialize, bounds hook callback execution, and is showcased in the live `examples/hooks/complete_workflow.exs` plus README/HOOKS_GUIDE updates.
- Assistant message error field parity (ADR 0004): optional `error` enum on assistant messages, streaming `message_stop` propagation, and a live demo in `examples/assistant_error_live.exs` with README/docs updates.

## [0.6.3] - 2025-11-29

### Added

- Control protocol parity updates:
  - `Client.set_permission_mode/2` now issues control requests to the CLI and tracks acknowledgements.
  - `ClaudeAgentSDK.query/2` auto-selects the control client when hooks, permission callbacks, agents, or non-default permission modes are configured (not just SDK MCP servers).
  - `Client.stream_messages/1` forwards partial `stream_event` frames as `%{type: :stream_event, event: ...}` so typewriter UIs can consume deltas alongside messages.
- Transport enhancements honor the `user` option across erlexec/streaming/port flows (env + user flag), enabling execution under an alternate OS account when permitted.
- Documentation updates reflecting the 2025-11-29 gap analysis and the new control/streaming behaviors.

## [0.6.2] - 2025-11-29

### Added

- Structured outputs parity with Python SDK: JSON Schema options flag, parsed
  `structured_output` on results and streaming, ContentExtractor fallback, and
  a live example that pretty prints validated JSON.

### Changed

- Upgraded test harness to Supertester 0.3.1 (ExUnitFoundation) and hardened
  streaming/custom transport tests by waiting for subscriber registration.

### Fixed

- Auth checker Bedrock/Vertex tests now isolate `ANTHROPIC_API_KEY` to prevent
  environment bleed and ensure deterministic branch coverage.

## [0.6.1] - 2025-11-11

### Added

- **Runtime control parity**:
  - `Client.interrupt/1` to stop active runs.
  - `Client.get_server_info/1` to surface CLI initialization metadata.
  - `Client.receive_response/1` for single-response workflows.
- **Options surface area**:
  - Support for `max_budget_usd`, `continue_conversation`, `resume`, `settings`, `setting_sources`, `plugins`, `extra_args`, `env`, `user`, `max_thinking_tokens`, `max_buffer_size`, and additive `add_dirs`.
  - Extended CLI argument builder plus dedicated unit tests (`options_extended_test.exs`).
- **Transport & Process tests** covering env propagation and custom CLI scripts.
- **Documentation**:
  - New `docs/20251111/elixir_python_gap_report.md` to track parity.
  - README + Python comparison updated with the new APIs.

### Changed

- **Transport.Port** now honors `Options.env`, `cwd`, buffer limits, and stamps `CLAUDE_AGENT_SDK_VERSION`/`CLAUDE_CODE_ENTRYPOINT`.
- **Process** uses the same env overrides when spawning erlexec-based CLI runs.
- **Streaming control adapter** now uses the new `Client.subscribe/1` contract for deterministic subscription handling (no sleeps).
- **Tests** were hardened with Supertester helpers instead of `Process.sleep/1`.

## [0.6.0] - 2025-10-26

### Added - Streaming + Tools Unification 🎉

- **StreamingRouter**: Automatic transport selection based on features
  - Intelligently selects CLI-only (fast) vs control client (full features)
  - Detects hooks, SDK MCP servers, permission callbacks, runtime agents
  - Explicit override via `preferred_transport` option
  - Pure function with <0.1ms overhead

- **Client Streaming Support**: Control protocol now supports partial messages
  - Added `include_partial_messages` option to enable character-level streaming
  - Stream event handling integrated with EventParser
  - Reference-based subscriber queue for concurrent streaming
  - Text accumulation across deltas
  - Unsubscribe handler with automatic queue processing

- **Streaming Facade Integration**: Transparent transport switching
  - `Streaming.start_session/1` now uses StreamingRouter
  - Polymorphic API works with both CLI-only and control client sessions
  - `stream_via_control_client/2` adapter for mixed event/message streams
  - Automatic `include_partial_messages: true` for streaming sessions

- **EventAdapter Utilities**: Helpers for heterogeneous streams
  - `to_events/1` - Normalize Message structs to event maps
  - `text_only/1` - Filter to text-related events
  - `tools_only/1` - Filter to tool-related events
  - `accumulate_text/1` - Build complete text from deltas
  - `collect_type/2` - Collect events of specific type

- **Comprehensive Examples**:
  - `examples/streaming_tools/basic_streaming_with_hooks.exs` - Security hooks with streaming
  - `examples/streaming_tools/sdk_mcp_streaming.exs` - SDK MCP tools with streaming
  - `examples/archive/streaming_tools/liveview_pattern.exs` - Phoenix LiveView integration

### Fixed

- **Stream event wrapping compatibility**
  - Protocol now correctly handles CLI's wrapped stream events: `{"type": "stream_event", "event": {...}}`
  - Client unwraps events for EventParser while maintaining test compatibility
  - Streaming examples now display character-by-character output correctly
  - Fixes streaming not working with hooks/MCP/permissions

- **Test suite reliability**
  - Eliminated all Process.sleep calls from streaming tests (12 instances removed)
  - Replaced timing-based sync with Supertester's state-based synchronization
  - Fixed subscription race condition in test setup with :sys.get_state sync
  - Tests are now deterministic and 100% reliable (previously 40-50% flaky)

- **Transport.Port streaming flag propagation**
  - Client now passes Options to Transport.Port via transport_opts
  - Ensures --include-partial-messages flag reaches CLI in all modes
  - Transport.Port builds CLI command from Options when provided

- **Example streaming patterns**
  - Changed Enum.take to Stream.take_while for real-time event processing
  - Examples now process events as they arrive instead of buffering
  - Improved typewriter effect visibility in demonstrations

### Changed

- **Options struct**: Added new fields for streaming control
  - `include_partial_messages` (boolean) - Enable streaming events
  - `preferred_transport` (:auto | :cli | :control) - Override router decision

- **Client.subscribers**: Changed from list to map (%{ref => pid})
  - Enables reference-based subscription tracking
  - Maintains backwards compatibility with legacy subscribe

- **Protocol message classification**: Extended to recognize streaming events
  - `message_start`, `message_stop`, `message_delta`
  - `content_block_start`, `content_block_delta`, `content_block_stop`

### Migration Guide

**No breaking changes!** This is a fully backwards-compatible release.

Existing code continues to work unchanged:
```elixir
# Works exactly as before
{:ok, session} = Streaming.start_session()
Streaming.send_message(session, "Hello")
```

To use new streaming + tools features:
```elixir
# Streaming with hooks (automatic control client selection)
options = %Options{
  hooks: %{pre_tool_use: [my_hook]}
}
{:ok, session} = Streaming.start_session(options)
Streaming.send_message(session, "Run command")
|> Stream.each(fn event -> handle_event(event) end)
|> Stream.run()
```

### Technical Details

- **Test Suite**: 602 tests passing (125 new tests added)
- **Code Coverage**: >95% on new code
- **Performance**: <10% latency regression on any path
- **Architecture**: Clean separation via router pattern
- **Type Safety**: Full Dialyzer coverage

## [0.5.3] - 2025-10-25

### Fixed - Process Timeout Configuration

- **Fixed erlexec timeout propagation**
  - Added `:timeout` option to erlexec base_options in `build_exec_options/1`
  - Ensures configured timeout_ms is properly passed to erlexec subprocess
  - Previously, timeout was only used in receive block, not in erlexec itself
  - Added debug logging to display configured timeout value
  - Prevents premature process termination for long-running operations

### Changed

- Improved timeout debugging with runtime logging of configured timeout values
- Better integration between Options.timeout_ms and erlexec process management

## [0.5.2] - 2025-10-25

### Fixed - Timeout Handling & Error Recovery

- **Configurable timeout for command execution** (`Options.timeout_ms`)
  - Added `timeout_ms` field to Options struct (default: 4,500,000ms = 75 minutes)
  - Process module now respects configured timeout value
  - Timeout error messages display human-readable format (minutes/seconds)
  - Allows long-running operations to complete without premature termination

- **Improved error handling for Jason dependency**
  - Fixed `Jason.DecodeError` pattern matching in DebugMode
  - Changed from direct struct match to struct check with `is_struct/1`
  - Prevents compilation warnings when Jason is not available

- **Test updates for model validation**
  - Updated model tests to use CLI short forms (opus, sonnet, haiku)
  - Tests now verify short form preservation instead of expansion
  - Updated full model version strings to match current Claude releases

### Changed

- Default timeout increased from 30 seconds to 75 minutes for complex operations
- Better error messages for timeout scenarios
- Model test assertions updated to match CLI behavior

## [0.5.1] - 2025-10-24

### Changed - Default Model Switch to Haiku

- **Changed default model from Sonnet to Haiku** across all modules and examples
  - Updated `Model.ex` to use CLI short forms (opus, sonnet, haiku) with correct model mappings
  - Updated `OptionBuilder.ex` to reflect Haiku as the default for most operations
  - Updated all 13 example files to use "haiku" instead of "claude-sonnet-4"
  - Updated `basic_example.exs` to use simpler query for faster response
  - Benefits: Lower cost, faster responses, better for simple queries and high-volume use

### Fixed - Model Validation

- Updated `Model.ex` to support both CLI short forms and full model IDs
- Added support for `sonnet[1m]` variant (1M context)
- Improved model validation and normalization
- Fixed documentation to reflect correct model naming conventions

### Documentation

- Updated README.md to reflect Haiku as default model
- Updated model selection examples to show proper defaults
- Clarified model capabilities and use cases

## [0.5.0] - 2025-10-24

### Added - Runtime Control & Transport Abstraction (2025-10-24)

- Added `ClaudeAgentSDK.Client.set_model/2` to switch models without restarting the client, including validation, pending request tracking, and broadcast updates for subscribers.
- Introduced the `ClaudeAgentSDK.Transport` behaviour plus default port implementation; `Client.start_link/2` now accepts `:transport` and `:transport_opts` for custom backends.
- Expanded the control protocol with `encode_set_model_request/2` and `decode_set_model_response/1` helpers to keep transports lightweight.
- Documented runtime control workflows and custom transport expectations in `docs/RUNTIME_CONTROL.md` and `docs/CUSTOM_TRANSPORTS.md`.

### Added - Deterministic Supertester Harness (2025-10-24)

- Adopted the `supertester` dependency (test-only) and new `ClaudeAgentSDK.SupertesterCase` to stabilise asynchronous suites.
- Shipped a mock transport and helper assertions for reproducible CLI message flows in tests.
- Captured upgrade guidance and new testing patterns in `docs/MIGRATION_V0_5.md`.

### Added - Hybrid Query System for Future SDK MCP Support (2025-10-17)

**Complete SDK MCP infrastructure ready for when CLI adds support!**

We've implemented full SDK MCP server support matching the Python SDK. While the Claude Code CLI doesn't support SDK servers yet (confirmed by Python SDK Issue #207), our infrastructure is complete and ready.

#### New Modules
- **`ClaudeAgentSDK.Query.ClientStream`** - Wraps Client GenServer as a Stream for SDK MCP support
  - Provides same Stream interface as Process.stream
  - Handles bidirectional control protocol automatically
  - Manages Client lifecycle (start, stream, cleanup)

#### Enhanced Query System
- **`Query.run/2`** - Now auto-detects SDK MCP servers and routes appropriately:
  - SDK servers detected → Uses ClientStream (bidirectional control protocol)
  - No SDK servers → Uses Process.stream (simple unidirectional)
  - **Transparent to users** - same API, different backend
- **`has_sdk_mcp_servers?/1`** - Helper to detect SDK servers in options

#### Control Protocol Updates
- Enhanced initialize request to include SDK MCP server metadata
- Client prepares and sends SDK server info during initialization
- Infrastructure ready for when CLI adds SDK MCP support

#### Documentation
- Added comprehensive SDK MCP status document explaining:
  - Why SDK MCP doesn't work with current CLI (Python SDK has same issue)
  - Infrastructure we've built and why it's ready
  - Workarounds using external MCP servers
  - Will work automatically when CLI adds support

#### Examples Fixed (2025-10-17)
- Fixed `sdk_mcp_live_demo.exs` response parsing to handle both string and array content
- Fixed `file_reviewer.exs` - Changed default to small file, improved text extraction
- Fixed `simple_batch.exs` - Now shows analysis inline + saves to files, filters tool messages
- Updated all examples with corrected paths after reorganization

### Changed - Examples Reorganization (2025-10-17)
- Merged `examples/v0_5_0/` into `examples/v0_4_0/` (all features are v0.4.0)
- Renamed `examples/v0_4_0/` → `examples/advanced_features/` (functionality-based naming)
- Updated all documentation and script references to use new paths
- Benefits: clearer organization, no version confusion, easier navigation

### Fixed - Live Examples (2025-10-17)
- **`file_reviewer.exs`** - Changed default file to small example (24 lines) to avoid timeouts
- **`simple_batch.exs`** - Now displays analysis inline (not just saves to files)
- **Both examples** - Improved `extract_assistant_content` to filter out tool_use messages, show only text

### Important Notes

**SDK MCP Servers Status:** Infrastructure complete but **awaiting CLI support**. The Claude Code CLI (v2.0.22 tested) does not yet recognize SDK MCP servers. This is not a bug in our SDK - it's a planned CLI feature. See `docs/SDK_MCP_STATUS.md` for details.

**When CLI Adds Support:** Our implementation will work automatically! No code changes needed.

**Live Examples Status:** All live examples tested and working with CLI v2.0.22:
- ✅ `simple_analyzer.exs` - Clean analysis output
- ✅ `file_reviewer.exs` - Code review with small files
- ✅ `simple_batch.exs` - Batch processing with inline output

---

## [0.4.0] - 2025-10-17

### 🎉 MILESTONE: 95%+ Feature Parity with Python SDK

This release achieves near-complete feature parity with the Python Claude Agent SDK by implementing the three most critical missing features using Test-Driven Development (TDD).

### Added - MCP Tool System 🛠️

**Complete in-process MCP tool support!**

#### Core Modules
- `ClaudeAgentSDK.Tool` - Tool definition macro for creating SDK-based MCP tools
  - `deftool/3` and `deftool/4` macros for declarative tool definition
  - Automatic tool module generation with metadata
  - In-process tool execution (no subprocess overhead)
  - Compile-time tool registration
  - Full type specs and documentation

- `ClaudeAgentSDK.Tool.Registry` - Tool registry GenServer
  - Dynamic tool registration and lookup
  - Tool execution with error handling
  - Concurrent tool access support
  - Process-safe tool management

- `ClaudeAgentSDK.create_sdk_mcp_server/1` - SDK MCP server creation
  - Creates in-process MCP servers from tool modules
  - No subprocess overhead compared to external MCP servers
  - Registry-based tool management
  - Compatible with Options.mcp_config

#### Features
- Define tools using simple `deftool` macro
- Tools generate `execute/1` and `__tool_metadata__/0` functions automatically
- Tools return Claude-compatible content blocks
- Support for complex input schemas (nested objects, arrays, etc.)
- Error handling and validation
- Large payload support
- Concurrent tool execution
- Image content support

### Added - Agent Definitions System 🤖

**Multi-agent support with runtime switching!**

#### Core Modules
- `ClaudeAgentSDK.Agent` - Agent definition struct
  - Agent profiles with custom prompts, tools, and models
  - Validation for agent configuration
  - CLI argument conversion

#### Client Enhancements
- `Client.set_agent/2` - Switch agents at runtime
- `Client.get_agent/1` - Get current active agent
- `Client.get_available_agents/1` - List all configured agents
- Automatic application of agent settings (prompt, allowed_tools, model)
- Agent validation on Client initialization
- Context preservation during agent switching

#### Features
- Define multiple agent profiles in Options
- Each agent has custom system prompt, allowed tools, and model
- Runtime agent switching without losing context
- Validation ensures only valid agents are used
- Agents stored in Options.agents map (agent_name => agent_definition)

### Added - Permission System 🔒

**Fine-grained tool permission control!**

#### Core Modules
- `ClaudeAgentSDK.Permission` - Permission system core
  - 4 permission modes: `:default`, `:accept_edits`, `:plan`, `:bypass_permissions`
  - Permission callback validation
  - Mode validation and conversion

- `ClaudeAgentSDK.Permission.Context` - Permission context
  - Tool name, input, session ID, and suggestions
  - Built from control protocol requests

- `ClaudeAgentSDK.Permission.Result` - Permission results
  - Allow/deny decisions with reasons
  - Input modification support (updated_input)
  - Interrupt capability for critical violations
  - JSON serialization for control protocol

#### Client Enhancements
- `Client.set_permission_mode/2` - Change permission mode at runtime
- Permission callback invocation via control protocol
  - `can_use_tool` callback support
  - Timeout protection (60s)
  - Exception handling (auto-deny on error)
  - Context building from CLI requests

#### Features
- Define permission callbacks to control tool access
- Four permission modes for different security levels
- Modify tool inputs before execution (e.g., redirect file paths)
- Interrupt execution on critical security violations
- Runtime permission mode switching
- Full integration with hooks system

### Test Coverage
- **87 new tests added** (42 MCP + 38 Agent + 49 Permission - some overlap)
- **389/389 tests passing** (100% success rate)
- **30 tests skipped** (intentional - live/integration tests)
- **Zero test warnings**
- **95%+ code coverage** for new modules

### Documentation
- Comprehensive gap analysis (6 documents, 3,414 lines)
- MCP implementation plan with TDD workflow
- Implementation results documentation
- Updated all module documentation
- Added @doc and @spec to all public functions

### Infrastructure
- Added `elixirc_paths/1` to compile test/support modules
- Created test/support/test_tools.ex for shared test tools
- Created test/support/edge_case_tools.ex for edge case testing
- Improved test organization and reusability

### Breaking Changes
None - all changes are additive and backward compatible.

### Migration from 0.3.0
No migration needed - all existing code continues to work. New features are opt-in.

---

## [0.3.0] - 2025-10-16

### Added - Hooks System 🎣

**Complete hooks implementation matching Python SDK functionality!**

#### Core Modules
- `ClaudeAgentSDK.Hooks` - Type definitions and utilities for hook events
  - 6 supported hook events: PreToolUse, PostToolUse, UserPromptSubmit, Stop, SubagentStop, PreCompact
  - Event string conversion (atom ↔ CLI string)
  - Hook configuration validation
  - Full type specs and documentation

- `ClaudeAgentSDK.Hooks.Matcher` - Pattern-based hook matching
  - Exact tool matching ("Bash")
  - Regex patterns ("Write|Edit")
  - Wildcard matching ("*" or nil)
  - Multiple hooks per matcher
  - CLI format conversion

- `ClaudeAgentSDK.Hooks.Output` - Hook output helpers
  - Permission decisions (allow/deny/ask)
  - Context injection (add_context)
  - Execution control (stop/block/continue)
  - Combinator functions (with_system_message, with_reason, suppress_output)
  - JSON serialization

- `ClaudeAgentSDK.Hooks.Registry` - Callback registration system
  - Unique ID assignment for callbacks
  - Bidirectional lookup (ID ↔ callback)
  - Idempotent registration
  - Helper functions (all_callbacks, count)

- `ClaudeAgentSDK.ControlProtocol.Protocol` - Control protocol message handling
  - Initialize request encoding
  - Hook response encoding
  - Message decoding and classification
  - Request ID generation

- `ClaudeAgentSDK.Client` - Bidirectional GenServer client
  - Persistent connection to Claude CLI
  - Control protocol request/response handling
  - Runtime hook callback invocation
  - Message streaming with subscribers
  - Port management with proper cleanup
  - Timeout protection for hooks (60s default)
  - Error handling and recovery

#### Options Integration
- Added `hooks` field to `ClaudeAgentSDK.Options` struct
- Type: `%{hook_event() => [Matcher.t()]} | nil`
- Fully integrated with existing options system
- Backward compatible (all existing tests pass)

#### Documentation
- **Technical Design Document** (47KB): `docs/design/hooks_implementation.md`
  - Complete architecture with diagrams
  - Detailed implementation specifications
  - 5-week phased implementation plan
  - Comparison with Python SDK
  - Control protocol message examples

- **User Guide** (25KB): `HOOKS_GUIDE.md`
  - Quick start with examples
  - All hook events documented
  - Hook output reference
  - Best practices and patterns
  - API reference
  - Debugging guide
  - Migration guide from CLI hooks

- **Implementation Summary**: `HOOKS_IMPLEMENTATION_SUMMARY.md`
  - What was implemented
  - Test coverage statistics
  - Performance metrics
  - Next steps

#### Examples
Five complete, working examples in `examples/hooks/`:
- `basic_bash_blocking.exs` - Security validation with PreToolUse
- `context_injection.exs` - Auto-inject project context
- `file_policy_enforcement.exs` - Comprehensive file access policies
- `logging_and_audit.exs` - Complete audit trail
- `complete_workflow.exs` - All hooks working together
- `README.md` - Examples guide and learning path

#### Testing
- **102 new tests** for hooks functionality
- 100% test pass rate (265/265 tests passing)
- Complete unit test coverage:
  - Hooks module: 22 tests
  - Matcher module: 10 tests
  - Output module: 25 tests
  - Registry module: 19 tests
  - Control Protocol: 17 tests
  - Client GenServer: 9 tests
- Zero dialyzer errors
- All tests use TDD methodology
- All phases implemented following test-first approach

#### Features
**Hook Events:**
- ✅ PreToolUse - Intercept before tool execution, can block/allow/ask
- ✅ PostToolUse - Process after execution, can add context
- ✅ UserPromptSubmit - Add context to prompts, can block
- ✅ Stop - Control agent completion, can force continuation
- ✅ SubagentStop - Control subagent completion
- ✅ PreCompact - Monitor context compaction

**Capabilities:**
- Pattern-based tool matching with regex support
- Permission control (allow/deny/ask user)
- Context injection for intelligent conversations
- Execution control (stop/continue)
- User and Claude messaging (systemMessage/reason)
- Output suppression for transcript
- Multiple hooks per event
- Type-safe callback signatures
- Validation and error handling

### Changed
- Updated `README.md` with Client and hooks sections with working examples
- Updated implementation status to v0.3.0
- Updated `mix.exs` version to 0.3.0
- Added hooks and control protocol modules to documentation groups
- Reorganized planned features (hooks complete in v0.3.0)

### Technical Details

**Architecture:**
- Full bidirectional communication via Port
- Control protocol over stdin/stdout
- GenServer-based client for state management
- Registry pattern for callback management
- Message routing and classification
- Timeout protection for hook execution

**Code Quality:**
- 1,420 LOC implementation
- 950 LOC tests
- 1,266 LOC examples
- 93KB+ documentation
- 100% test pass rate (265 tests)
- Zero dialyzer errors
- Zero credo issues
- Complete type specifications

**Performance:**
- Hook invocation overhead < 10ms
- Registry lookup O(1)
- No overhead when hooks not configured
- Efficient message routing

### Notes
- **Full end-to-end implementation complete**
- Hooks work at runtime with real Claude CLI
- Client GenServer enables bidirectional streaming
- Matches Python SDK feature parity
- Production-ready with comprehensive testing
- No breaking changes - fully backward compatible!

### Migration Guide
- Existing code works without changes
- Hooks are optional (nil by default)
- Add `Client` for bidirectional communication with hooks
- See `HOOKS_GUIDE.md` for usage patterns

## [0.2.2] - 2025-10-10

### Changed
- **Repository Rename**: Migrated from `claude_code_sdk_elixir` to `claude_agent_sdk` for consistency
- Updated all documentation, URLs, and references to reflect new repository name
- GitHub repository URL: https://github.com/nshkrdotcom/claude_agent_sdk

### Fixed
- Documentation cleanup and standardization across all markdown files
- Internal path references updated to match new repository structure

## [0.2.1] - 2025-10-09

### Added - Bidirectional Streaming

#### Real-Time Character-by-Character Streaming
- **ClaudeAgentSDK.Streaming module** - Public API for bidirectional streaming sessions
- **Streaming.Session GenServer** - Manages persistent subprocess with stdin/stdout pipes
- **EventParser** - Parses SSE events (message_start, text_delta, content_block_stop, message_stop)
- **Text delta events** - Character-by-character streaming for typewriter effects
- **Multi-turn conversations** - Full context preservation across multiple messages in one session
- **Message queueing** - Sequential processing of messages with automatic dequeuing
- **Subscriber management** - Proper event routing to active subscriber only
- **Multiple concurrent sessions** - True parallelism by running multiple independent sessions

#### Streaming Features
- `start_session/1` - Start persistent bidirectional connection
- `send_message/2` - Send message and receive streaming events
- `close_session/1` - Clean subprocess termination
- `get_session_id/1` - Retrieve Claude session ID
- Phoenix LiveView integration examples
- Comprehensive event types (text_delta, tool_use, thinking, errors)

### Fixed
- Event parser unwraps `stream_event` wrapper from Claude CLI output
- Added required `--verbose` flag for `stream-json` output format
- Proper `:DOWN` message handling for erlexec subprocess monitoring
- Subscriber queue prevents message crosstalk in concurrent scenarios
- Sequential message processing within single session (prevents race conditions)

### Changed
- Streaming uses CLI flags: `--input-format stream-json --output-format stream-json --include-partial-messages --verbose`
- Messages within one session are processed sequentially (by design)
- For parallelism, use multiple independent sessions

### Testing
- `test_streaming.exs` - Basic streaming functionality with statistics
- `test_bidirectional.exs` - Multi-turn, rapid sequential, concurrent sessions, message queueing

## [0.2.0] - 2025-10-07

### Added - Session Management & Coverage Improvements

#### Session Persistence
- **SessionStore GenServer** - Persistent session storage and management
- **Session helper module** - Extract metadata from message lists
- **File-based storage** - Sessions saved in `~/.claude_sdk/sessions/`
- **ETS caching** - Fast in-memory access to session metadata
- **Tag system** - Organize sessions with custom tags
- **Search functionality** - Find sessions by tags, date range, cost
- **Automatic cleanup** - Remove sessions older than 30 days
- **Session metadata** - Track cost, message count, model used, timestamps

#### Additional CLI Flags (Quick Wins)
- **`fork_session`** - Create new session ID when resuming (`--fork-session`)
- **`add_dir`** - Work across multiple directories (`--add-dir`)
- **`strict_mcp_config`** - Isolated MCP server usage (`--strict-mcp-config`)

### Changed
- **Options struct** - Added `fork_session`, `add_dir`, `strict_mcp_config` fields
- **CLI argument generation** - Extended with 3 additional flags
- **Coverage** - Now 84% of Claude Code 2.0 CLI features (was 76%)

### Documentation
- **Rate Limiting Best Practices** - Comprehensive guide using hammer/:fuse
- **Next Features Recommendation** - Analysis of remaining gaps
- **Session features example** - Complete demonstration of all session capabilities

### Examples
- `examples/session_features_example.exs` - Session persistence, forking, multi-dir
- `test_session_persistence_live.exs` - Live API validation

## [0.1.0] - 2025-10-07

### Added - Production Orchestration Features

#### Authentication Management
- **AuthManager GenServer** - Automatic token management with persistence
- **TokenStore** - Secure token storage in `~/.claude_sdk/token.json`
- **Multi-provider support** - Anthropic OAuth, AWS Bedrock, GCP Vertex AI
- **Mix task** - `mix claude.setup_token` for easy authentication setup
- **Auto-refresh** - Tokens automatically refresh before expiry (1 year validity)
- **Environment variable support** - `CLAUDE_AGENT_OAUTH_TOKEN` and `ANTHROPIC_API_KEY`

#### Model Selection & Custom Agents
- **Model selection** - Choose Opus, Sonnet, Haiku, or specific model versions
- **Fallback models** - Automatic fallback when primary model is overloaded
- **Custom agents** - Define specialized agents with custom prompts and tools
- **OptionBuilder helpers** - `with_opus()`, `with_sonnet()`, `with_haiku()`, `with_agent()`
- **CLI mapping** - Full support for `--model`, `--fallback-model`, `--agents` flags

#### Concurrent Orchestration
- **Orchestrator module** - Parallel query execution with concurrency control
- **Parallel execution** - `query_parallel/2` runs multiple queries concurrently (3-5x speedup)
- **Pipeline workflows** - `query_pipeline/2` for sequential multi-step tasks with context passing
- **Retry logic** - `query_with_retry/3` with exponential backoff
- **Error aggregation** - Comprehensive error reporting across concurrent queries
- **Performance tracking** - Cost, duration, and success metrics for all queries

### Changed
- **Options struct** - Added `model`, `fallback_model`, `agents`, `session_id` fields
- **CLI argument generation** - Extended to support all Claude Code CLI v2.0.10 features

### Fixed
- **OAuth token support** - Updated to parse `sk-ant-oat01-` format from CLI v2.0.10
- **Token validity** - Corrected from 30 days to 1 year for OAuth tokens

### Examples
- `examples/model_selection_example.exs` - Model selection demonstration
- `examples/custom_agents_example.exs` - Custom agent workflows
- `examples/week_1_2_showcase.exs` - Comprehensive feature showcase

### Documentation
- Detailed implementation plans in `docs/20251007/`
- Comprehensive architectural review in `REVIEW_20251007.md`
- Week 1-2 progress report in `WEEK_1_2_PROGRESS.md`

## [0.0.1] - 2025-07-05

### Added
- Initial release of Claude Code SDK for Elixir
- Core functionality for interacting with Claude Code CLI
- Support for synchronous and streaming queries
- Authentication management via `ClaudeAgentSDK.AuthChecker`
- Process management with `ClaudeAgentSDK.Process`
- Message handling and formatting
- Mock support for testing without API calls
- Mix tasks:
  - `mix showcase` - Demonstrate SDK capabilities
  - `mix run.live` - Interactive live testing
  - `mix test.live` - Run tests with live API
- Comprehensive test suite
- Documentation and examples
- Support for custom Claude Code CLI options
- Debug mode for troubleshooting
- Mermaid diagram support in documentation

### Features
- Simple, idiomatic Elixir API
- Stream-based response handling
- Automatic retry on authentication challenges
- Configurable timeouts and options
- Full compatibility with Claude Code CLI features

[Unreleased]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.14.0...HEAD
[0.14.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.9.2...v0.10.0
[0.9.2]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.7.7...v0.8.0
[0.7.7]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.7.6...v0.7.7
[0.7.6]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.7.5...v0.7.6
[0.7.5]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.7.4...v0.7.5
[0.7.4]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.7.3...v0.7.4
[0.7.3]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.7.2...v0.7.3
[0.7.2]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.10...v0.7.0
[0.6.10]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.9...v0.6.10
[0.6.9]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.8...v0.6.9
[0.6.8]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.7...v0.6.8
[0.6.7]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.6...v0.6.7
[0.6.6]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.5...v0.6.6
[0.6.5]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.4...v0.6.5
[0.6.4]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.3...v0.6.4
[0.6.3]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.5.3...v0.6.0
[0.5.3]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/claude_agent_sdk/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/nshkrdotcom/claude_agent_sdk/releases/tag/v0.0.1
