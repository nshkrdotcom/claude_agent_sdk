# Claude Code SDK for Elixir - Comprehensive Manual

An exhaustive guide to the Elixir implementation of the Claude Code SDK, covering all functionality, advanced usage patterns, error handling, and integration strategies.

## Table of Contents

- [Overview](#overview)
- [Architecture Deep Dive](#architecture-deep-dive)
- [Installation & Setup](#installation--setup)
- [Authentication](#authentication)
- [Core API Reference](#core-api-reference)
- [Message Types & Processing](#message-types--processing)
- [Advanced Usage Patterns](#advanced-usage-patterns)
- [Error Handling & Recovery](#error-handling--recovery)
- [Performance Optimization](#performance-optimization)
- [Integration Patterns](#integration-patterns)
- [MCP Support](#mcp-support)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)
- [Examples & Use Cases](#examples--use-cases)

## Overview

The Claude Code SDK for Elixir provides a native Elixir interface to Claude Code, enabling developers to build AI-powered applications that leverage Claude's capabilities through familiar Elixir patterns. Unlike direct API integrations, this SDK uses the Claude CLI as a subprocess, providing access to all Claude Code features including tool usage, file operations, and interactive capabilities.

## Implementation Status

### ✅ **Currently Implemented (v0.2.0)**
- **Core SDK Functions**: `query/2`, `continue/2`, `resume/3` with stdin support.
- **Authentication Management**: `AuthManager` for automatic token handling, `mix claude.setup_token` task, multi-provider support, and environment variable fallbacks.
- **Model Selection & Custom Agents**: Full support for Opus, Sonnet, Haiku, fallback models, and custom agent definitions via `OptionBuilder`.
- **Concurrent Orchestration**: `Orchestrator` module for parallel queries (`query_parallel/2`), sequential pipelines (`query_pipeline/2`), and retries (`query_with_retry/3`).
- **Session Persistence**: `SessionStore` GenServer for saving, loading, and searching sessions with tagging and metadata.
- **Advanced Session Flags**: Support for forking sessions, adding multiple directories, and strict MCP configs.
- **Developer Tools**: A suite of helper modules including `OptionBuilder`, `AuthChecker`, `ContentExtractor`, and `DebugMode`.
- **Robust Subprocess Management**: Integration with `erlexec` for stable process control.
- **Comprehensive Mocking System**: For testing without live API calls.
- **Live Script Runner**: `mix run.live` for executing scripts with real API calls.
- **Error Handling**: Improved error detection and timeout handling.

### 🔮 **Planned Features (v0.3.0+)**
- **Bidirectional Streaming**: For real-time, character-level streaming suitable for chat UIs.
- **Telemetry Integration**: For production observability.
- **Advanced Integration Patterns**: Examples for Phoenix LiveView, OTP applications, and worker pools.
- **Plugin System**: An extensible architecture for custom behaviors.
- **Advanced Examples**: In-depth examples for code analysis, test generation, and refactoring.
- **Full MCP Support**: Deeper integration with the Model Context Protocol.

## Architecture Deep Dive

### Component Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User Code     │───▶│  ClaudeCodeSDK  │───▶│   Claude CLI    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │  Message Stream │
                       └─────────────────┘
```

### Module Structure

- **`ClaudeCodeSDK`**: Main public API interface.
- **`ClaudeCodeSDK.Query`**: Query construction and execution.
- **`ClaudeCodeSDK.Process`**: Subprocess management with erlexec.
- **`ClaudeCodeSDK.Message`**: Message parsing and type definitions.
- **`ClaudeCodeSDK.Options`**: Configuration and CLI argument building.
- **`ClaudeCodeSDK.JSON`**: Custom JSON parsing without external dependencies.
- **`ClaudeCodeSDK.AuthManager`**: Manages authentication tokens and status.
- **`ClaudeCodeSDK.Orchestrator`**: Handles concurrent and sequential query execution.
- **`ClaudeCodeSDK.SessionStore`**: Manages session persistence.

### Data Flow

1. **Query Construction**: User prompt and options are converted to CLI arguments.
2. **Process Spawning**: Claude CLI is spawned as a subprocess with proper arguments.
3. **Stream Processing**: JSON responses are parsed and converted to Elixir structs.
4. **Message Delivery**: Structured messages are yielded through an Elixir Stream.

## Installation & Setup

### Prerequisites

1. **Node.js**: Required for Claude CLI.
2. **Claude CLI**: Install globally.
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```
3. **Authentication**: Authenticate once using the new helper task.
   ```bash
   mix claude.setup_token
   ```

### Project Setup

Add to your `mix.exs`:
```elixir
def deps do
  [
    {:claude_code_sdk, "~> 0.2.0"}
  ]
end
```

Then run:
```bash
mix deps.get
```

## Authentication

The SDK provides robust authentication management via the `AuthManager` module.

### One-Time Setup (Recommended)

The easiest way to authenticate is with the included Mix task. This will generate a long-lived OAuth token (1 year) and store it securely.

```bash
# This requires a Claude subscription
mix claude.setup_token
```

### Authentication in Code

The SDK automatically detects and uses the stored token. You can also check the authentication status programmatically.

```elixir
alias ClaudeCodeSDK.AuthManager

# Check authentication status
status = AuthManager.status()
# => %{
#   authenticated: true,
#   provider: :anthropic,
#   token_present: true,
#   expires_at: ~U[2026-10-07 ...],
#   time_until_expiry_hours: 8760.0
# }

# Ensure authenticated (will prompt for setup if needed)
:ok = AuthManager.ensure_authenticated()
```

### Environment Variables (for CI/CD)
You can also provide the token via environment variables:
```bash
export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-your-token-here
```

## Core API Reference

### Primary Functions

#### `ClaudeCodeSDK.query/2`
Executes a single query with optional configuration.
```elixir
@spec query(String.t(), Options.t() | nil) :: Stream.t()
ClaudeCodeSDK.query("Write a hello world function")
```

#### `ClaudeCodeSDK.continue/2`
Continues the most recent conversation.
```elixir
@spec continue(String.t() | nil, Options.t() | nil) :: Stream.t()
ClaudeCodeSDK.continue("Now add error handling")
```

#### `ClaudeCodeSDK.resume/3`
Resumes a specific conversation by session ID.
```elixir
@spec resume(String.t(), String.t() | nil, Options.t() | nil) :: Stream.t()
ClaudeCodeSDK.resume("session-id-here", "Add tests")
```

### Options & Smart Presets

Use the `OptionBuilder` to create configurations for common use cases.

```elixir
alias ClaudeCodeSDK.OptionBuilder

# Development: permissive settings, verbose logging
options = OptionBuilder.build_development_options()

# Production: restricted settings, minimal tools
options = OptionBuilder.build_production_options()

# Analysis: read-only tools for code analysis
options = OptionBuilder.build_analysis_options()

# Combine presets with custom options
options = OptionBuilder.merge(:development, %{max_turns: 5})

# Manually configure options
options = %ClaudeCodeSDK.Options{
  max_turns: 10,
  system_prompt: "You are a helpful assistant.",
  model: "opus"
}

ClaudeCodeSDK.query("My query", options)
```

## Message Types & Processing

### Message Structure
All messages are `ClaudeCodeSDK.Message` structs:
```elixir
%ClaudeCodeSDK.Message{
  type: :system | :user | :assistant | :result,
  subtype: atom() | nil,
  data: map(),
  raw: map()
}
```

- **`:system`**: Session initialization info (session_id, model, etc.).
- **`:assistant`**: Claude's responses.
- **`:user`**: The user's input messages.
- **`:result`**: The final result of the conversation with stats (`:success` or an error subtype).

### Content Extraction
Use the `ContentExtractor` to easily get text from messages.

```elixir
alias ClaudeCodeSDK.ContentExtractor

ClaudeCodeSDK.query("Your prompt")
|> Stream.filter(fn msg -> msg.type == :assistant end)
|> Stream.map(&ContentExtractor.extract_text/1)
|> Enum.each(&IO.puts/1)
```

## Advanced Usage Patterns

### Session Management
Persist and resume conversations using the `SessionStore`.

```elixir
alias ClaudeCodeSDK.{SessionStore, Session}

# Start the session store (in your application supervisor)
{:ok, _pid} = SessionStore.start_link()

# Execute a query
messages = ClaudeCodeSDK.query("Build a user authentication system") |> Enum.to_list()

# Save the session
session_id = Session.extract_session_id(messages)
:ok = SessionStore.save_session(session_id, messages,
  tags: ["feature-dev", "auth"],
  description: "Building user auth"
)

# Later, load and resume
{:ok, session_data} = SessionStore.load_session(session_id)
ClaudeCodeSDK.resume(session_id, "Now add password reset functionality")

# Search for sessions
auth_sessions = SessionStore.search(tags: ["auth"])
```

### Concurrent Processing
Execute multiple queries in parallel for significant speed improvements using the `Orchestrator`.

```elixir
alias ClaudeCodeSDK.Orchestrator

queries = [
  {"Analyze file1.ex", analysis_opts},
  {"Analyze file2.ex", analysis_opts},
  {"Analyze file3.ex", analysis_opts}
]

# Run up to 3 queries in parallel
{:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 3)

# results is a list of %Orchestrator.Result{} structs
Enum.each(results, fn result ->
  IO.puts("Prompt: #{result.prompt}, Success: #{result.success}, Cost: $#{result.cost}")
end)
```

### Conversation Chains
Create multi-step workflows where the output of one query is the input to the next.

```elixir
alias ClaudeCodeSDK.Orchestrator

steps = [
  {"Analyze this code for quality.", analysis_opts},
  {"Suggest refactorings based on the previous analysis.", refactor_opts},
  {"Generate tests for the refactored code.", test_opts}
]

# `use_context: true` passes the conversation history to the next step
{:ok, final_result} = Orchestrator.query_pipeline(steps, use_context: true)
```

## Error Handling & Recovery

### Error Types
The final `:result` message will have a subtype indicating the outcome.
- `:success`
- `:error_max_turns`
- `:error_during_execution`
- `:error_auth`

### Retry Logic
The `Orchestrator` provides built-in retry logic with exponential backoff.

```elixir
alias ClaudeCodeSDK.Orchestrator

# Retry a query up to 3 times on failure
{:ok, result} = Orchestrator.query_with_retry(
  "A prompt for a flaky operation",
  options,
  max_retries: 3,
  backoff_ms: 1000
)
```

## Performance Optimization

### Parallel Processing
Use `Orchestrator.query_parallel/2` for batch processing tasks like analyzing multiple files. This is the most significant performance optimization available.

### Caching Strategies (FUTURE/PLANNED)
For frequently repeated queries, a caching layer can be implemented.

```elixir
defmodule QueryCache do  # FUTURE/PLANNED - Not yet implemented
  use GenServer
  # ... Caching logic using a GenServer or ETS ...
end
```

## Integration Patterns (FUTURE/PLANNED)

This section outlines planned examples and integrations.

### Phoenix LiveView Integration
An example LiveView will be provided to show how to build real-time, streaming UIs.

### OTP Application Integration
Best practices for integrating the SDK's GenServers (`AuthManager`, `SessionStore`) into a supervised OTP application will be documented.

## MCP Support
The SDK has basic support for MCP (Model Context Protocol) via the `--strict-mcp-config` flag, but full, dynamic MCP server management is a planned feature.

## Security Considerations (FUTURE/PLANNED)
Future versions will include guides and potentially helpers for:
- **Input Validation**: Sanitizing prompts to prevent injection-style attacks.
- **Permission Management**: Scoping tool permissions based on environment or user roles.

## Troubleshooting

### Authentication Problems
Use the built-in `AuthChecker` and `DebugMode` to diagnose issues.

```elixir
# Check authentication and environment readiness
ClaudeCodeSDK.AuthChecker.diagnose()

# Run a full diagnostic check
ClaudeCodeSDK.DebugMode.run_diagnostics()
```
If issues persist, re-run the setup task: `mix claude.setup_token`.

### Debug Mode
Use `DebugMode` for detailed query analysis.

```elixir
alias ClaudeCodeSDK.DebugMode

# Execute a query with detailed logging and timing
messages = DebugMode.debug_query("My test query")

# Benchmark performance
results = DebugMode.benchmark("Test query", nil, 3)

# Analyze message statistics
stats = DebugMode.analyze_messages(messages)
```

## Examples & Use Cases (FUTURE/PLANNED)
This section will be expanded with detailed examples for common use cases:
- **Code Analysis Pipeline**: A multi-stage pipeline to analyze code quality, find bugs, and suggest improvements.
- **Documentation Generator**: A tool to automatically generate documentation for Elixir modules.
- **Test Generator**: A tool to create ExUnit test suites for existing code.
- **Interactive Development Assistant**: A command-line tool for pair programming with Claude.
- **Automated Refactoring Tool**: A tool to perform complex, multi-file refactorings.

This comprehensive manual covers all aspects of the Claude Code SDK for Elixir, from basic usage to advanced integration patterns. It provides practical examples for real-world use cases while maintaining security and performance best practices.