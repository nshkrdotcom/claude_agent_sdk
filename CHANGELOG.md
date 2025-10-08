# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-10-07

### Added - Production Orchestration Features

#### Authentication Management
- **AuthManager GenServer** - Automatic token management with persistence
- **TokenStore** - Secure token storage in `~/.claude_sdk/token.json`
- **Multi-provider support** - Anthropic OAuth, AWS Bedrock, GCP Vertex AI
- **Mix task** - `mix claude.setup_token` for easy authentication setup
- **Auto-refresh** - Tokens automatically refresh before expiry (1 year validity)
- **Environment variable support** - `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_API_KEY`

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
- Authentication management via `ClaudeCodeSDK.AuthChecker`
- Process management with `ClaudeCodeSDK.Process`
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

[0.0.1]: https://github.com/nshkrdotcom/claude_code_sdk_elixir/releases/tag/v0.0.1