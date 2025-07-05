# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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