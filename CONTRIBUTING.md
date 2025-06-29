# Contributing to Claude Code SDK for Elixir

Welcome to the Claude Code SDK for Elixir! This guide is designed for senior Elixir developers who want to contribute to this project. The SDK provides a robust Elixir interface to Claude Code CLI using erlexec for subprocess management.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Core Dependencies](#core-dependencies)
- [Development Setup](#development-setup)
- [Code Organization](#code-organization)
- [Erlexec Integration](#erlexec-integration)
- [Testing Strategy](#testing-strategy)
- [Contributing Guidelines](#contributing-guidelines)
- [Release Process](#release-process)

## Architecture Overview

The Claude Code SDK for Elixir is a wrapper around the Claude Code CLI tool that uses **erlexec** for robust subprocess management. The architecture follows functional programming principles with clear separation of concerns:

```
User Code → ClaudeCodeSDK → Query → Process → erlexec → claude CLI
                                ↓
                            Message ← JSON Parser
```

### Key Design Decisions

1. **Erlexec over Port**: We use erlexec instead of native Elixir `Port.open/2` for superior process management, IO handling, and error recovery
2. **Stream-based Processing**: Lazy evaluation using Elixir Streams for memory efficiency
3. **Structured Messages**: All CLI output is parsed into typed `ClaudeCodeSDK.Message` structs
4. **Zero External JSON Dependencies**: Custom JSON parser to avoid external dependencies
5. **Synchronous Execution**: Using erlexec's `:sync` mode for reliable output capture

## Core Dependencies

### Erlexec (Primary Dependency)

**Version**: `~> 2.0`  
**Purpose**: Robust OS process execution and management

Erlexec is our primary dependency and the foundation of the SDK's reliability. It provides:

- **Robust Process Management**: Battle-tested subprocess spawning and monitoring
- **Proper IO Handling**: Built-in stdout/stderr redirection without EPIPE errors
- **Synchronous Execution**: `:sync` mode captures complete output before processing
- **Process Monitoring**: Native support for process lifecycle management
- **Signal Handling**: Comprehensive exit status and error reporting

### Development Dependencies

- **jason** (`~> 1.4`): JSON parsing and pretty-printing for error formatting
- **ex_doc** (`~> 0.31`): Documentation generation
- **dialyxir** (`~> 1.0`): Static analysis with Dialyzer
- **credo** (`~> 1.6`): Code quality and style checking

## Development Setup

### Prerequisites

1. **Elixir 1.14+** with OTP 25+
2. **Claude Code CLI**: Install via npm
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude login  # Authenticate once
   ```
3. **API Access**: Ensure you have Claude API access configured

### Setup Steps

```bash
# Clone and setup
git clone <repository-url>
cd claude_code_sdk_elixir

# Install dependencies
mix deps.get

# Compile with warnings as errors
mix compile --warnings-as-errors

# Run tests
mix test

# Run example
mix run final_test.exs
```

### Verification

Run the comprehensive test to verify everything works:

```bash
mix run final_test.exs
```

Expected output should show successful API connection, message processing, and cost reporting.

## Code Organization

### Module Structure

```
lib/claude_code_sdk/
├── claude_code_sdk.ex      # Public API (query, continue, resume)
├── query.ex                # Query orchestration and CLI args building  
├── process.ex              # Erlexec subprocess management
├── message.ex              # Message parsing and type definitions
├── options.ex              # Configuration struct and CLI conversion
└── json.ex                 # Custom JSON parser (no external deps)
```

### Key Modules Deep Dive

#### `ClaudeCodeSDK.Process` - Erlexec Integration

This is the core module that interfaces with erlexec:

```elixir
# Synchronous execution pattern
case :exec.run(cmd, [:sync, :stdout, :stderr]) do
  {:ok, result} -> parse_sync_result(result)
  {:error, reason} -> handle_error(reason)
end
```

**Key Features**:
- Uses `:sync` mode for complete output capture
- Handles both stdout and stderr streams
- Implements proper shell escaping for command arguments
- Converts erlexec results to Elixir Streams

#### `ClaudeCodeSDK.Message` - Type System

Structured message types with comprehensive parsing:

```elixir
@type message_type :: :assistant | :user | :result | :system
@type result_subtype :: :success | :error_max_turns | :error_during_execution
```

**Design Principles**:
- Immutable message structs
- Exhaustive pattern matching
- Graceful fallback parsing for malformed JSON
- Type safety with Dialyzer specs

#### `ClaudeCodeSDK.Options` - Configuration

Comprehensive configuration system that maps to Claude CLI arguments:

```elixir
%ClaudeCodeSDK.Options{
  max_turns: 10,
  output_format: :stream_json,
  system_prompt: "Custom prompt",
  verbose: true
}
```

## Erlexec Integration

### Why Erlexec?

We chose erlexec over native Elixir `Port.open/2` for several critical reasons:

1. **EPIPE Prevention**: Native ports often cause broken pipe errors with the Claude CLI
2. **Robust IO Handling**: Erlexec properly manages stdout/stderr redirection
3. **Production Stability**: Battle-tested in high-traffic Erlang/OTP systems
4. **Synchronous Execution**: Built-in support for capturing complete output
5. **Process Monitoring**: Native process lifecycle management

### Implementation Pattern

Our erlexec usage follows this pattern:

```elixir
defp start_claude_process(args, options) do
  # Ensure erlexec is started
  case Application.ensure_all_started(:erlexec) do
    {:ok, _} -> :ok
    {:error, reason} -> raise "Failed to start erlexec: #{inspect(reason)}"
  end

  # Build command with proper escaping
  cmd = build_claude_command(args, options)
  
  # Execute synchronously
  case :exec.run(cmd, [:sync, :stdout, :stderr]) do
    {:ok, result} -> parse_and_stream_result(result)
    {:error, reason} -> create_error_message(reason)
  end
end
```

### Command Building

We carefully construct shell commands with proper escaping:

```elixir
defp shell_escape(arg) do
  if String.contains?(arg, [" ", "!", "\"", "'", "$", "`", "\\", "|", "&", ";", "(", ")"]) do
    "\"#{String.replace(arg, "\"", "\\\"")}\""
  else
    arg
  end
end
```

### Stream Conversion

Erlexec's synchronous results are converted to lazy streams:

```elixir
Stream.resource(
  fn -> start_claude_process(args, options) end,
  &receive_messages/1,
  &cleanup_process/1
)
```

## Testing Strategy

### Test Categories

1. **Unit Tests** (`test/`): Module-level functionality
2. **Integration Tests** (`*_test.exs`): End-to-end CLI interaction  
3. **Example Scripts** (`example*.exs`): Manual verification
4. **Debug Scripts** (`debug_*.exs`): Troubleshooting tools

### Running Tests

```bash
# Unit tests
mix test

# Integration test with real API
mix run final_test.exs

# Basic erlexec functionality
mix run test_mix.exs

# Minimal example
mix run minimal_test.exs
```

### Test Requirements

- **Authentication**: Tests require `claude login` to be completed
- **API Access**: Some tests make real API calls (minimal cost)
- **Network**: Integration tests require internet connectivity
- **CLI Installation**: Claude CLI must be available in PATH

### Writing Tests

When adding tests:

1. **Mock External Dependencies**: Use ExUnit mocks for unit tests
2. **Test Error Paths**: Ensure robust error handling
3. **Verify Message Types**: Test all message type parsing
4. **Performance Testing**: Verify stream processing efficiency

## Contributing Guidelines

### Code Style

We follow standard Elixir conventions plus project-specific guidelines:

1. **Formatting**: Use `mix format` (configured in `.formatter.exs`)
2. **Credo**: Pass all `mix credo` checks
3. **Dialyzer**: Maintain type safety with `mix dialyzer`
4. **Documentation**: Comprehensive `@doc` and `@spec` annotations

### Pull Request Process

1. **Fork and Branch**: Create feature branches from `main`
2. **Test Coverage**: Ensure all new code has tests
3. **Documentation**: Update docs for API changes
4. **Type Safety**: Add Dialyzer specs for new functions
5. **Performance**: Consider memory usage and stream efficiency

### Code Review Checklist

- [ ] Proper error handling with meaningful messages
- [ ] Comprehensive tests covering edge cases
- [ ] Documentation updated for API changes
- [ ] Dialyzer specs for type safety
- [ ] Memory-efficient stream processing
- [ ] Proper resource cleanup (processes, files)

### Erlexec-Specific Guidelines

When modifying erlexec integration:

1. **Always Use `:sync` Mode**: For predictable output capture
2. **Handle All Exit Codes**: Test success and failure scenarios
3. **Proper Shell Escaping**: Prevent injection vulnerabilities
4. **Resource Cleanup**: Ensure processes are properly terminated
5. **Error Recovery**: Graceful handling of subprocess failures

### Common Patterns

#### Adding New CLI Options

1. Add field to `ClaudeCodeSDK.Options` struct
2. Update `to_args/1` function to convert to CLI argument
3. Add documentation and type specs
4. Test with integration tests

#### Adding New Message Types

1. Define type in `ClaudeCodeSDK.Message`
2. Update JSON parsing logic
3. Add pattern matching in examples
4. Document new message structure

#### Debugging Subprocess Issues

1. Use `debug_*.exs` scripts for testing
2. Enable verbose logging with `verbose: true`
3. Check erlexec application status
4. Verify CLI installation and authentication

## Release Process

### Version Management

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking API changes
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, backward compatible

### Release Checklist

1. **Update Version**: Bump version in `mix.exs`
2. **Update Changelog**: Document all changes
3. **Test Release**: Run full test suite
4. **Documentation**: Ensure docs are current
5. **Tag Release**: Create Git tag with version
6. **Publish**: `mix hex.publish` (if applicable)

### Breaking Changes

When introducing breaking changes:

1. **Deprecation Warnings**: Add warnings in previous version
2. **Migration Guide**: Document upgrade path
3. **Backward Compatibility**: Maintain when possible
4. **Communication**: Announce changes clearly

## Performance Considerations

### Memory Usage

- **Stream Processing**: Use lazy evaluation to minimize memory footprint
- **Message Buffering**: Avoid accumulating large message lists
- **JSON Parsing**: Custom parser optimized for our message formats

### Subprocess Management

- **Process Lifecycle**: Proper cleanup prevents resource leaks
- **Timeout Handling**: Reasonable timeouts for long-running operations
- **Error Recovery**: Graceful handling of subprocess failures

### Monitoring

Key metrics to monitor:

- **Memory Usage**: Stream processing should have constant memory usage
- **Process Count**: Ensure subprocess cleanup
- **Response Times**: Monitor API call latency
- **Error Rates**: Track subprocess failure rates

## Troubleshooting

### Common Issues

1. **Claude CLI Not Found**
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

2. **Authentication Errors**
   ```bash
   claude login
   ```

3. **Erlexec Start Failures**
   ```elixir
   Application.ensure_all_started(:erlexec)
   ```

4. **JSON Parsing Errors**
   - Check CLI output format
   - Verify `--output-format stream-json`

### Debug Tools

- `mix run debug_test.exs` - Basic functionality test
- `mix run port_debug.exs` - Subprocess communication test
- `mix run trace_test.exs` - Detailed execution tracing

### Getting Help

1. **Check Documentation**: Comprehensive docs in `COMPREHENSIVE_MANUAL.md`
2. **Review Examples**: Working examples in `examples/` directory
3. **Run Debug Scripts**: Use provided debugging tools
4. **Check Issues**: Review existing GitHub issues

---

Thank you for contributing to the Claude Code SDK for Elixir! Your expertise helps make this library more robust and useful for the Elixir community. 