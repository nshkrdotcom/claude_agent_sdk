# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- **User Guide** (25KB): `docs/HOOKS_GUIDE.md`
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
- See `docs/HOOKS_GUIDE.md` for usage patterns

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