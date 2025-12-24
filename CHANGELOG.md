# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[0.0.1]: https://github.com/nshkrdotcom/claude_agent_sdk/releases/tag/v0.0.1
