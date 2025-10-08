<p align="center">
  <img src="assets/logo.svg" alt="Claude Code Elixir SDK Logo" width="200"/>
</p>

<h1 align="center">Claude Code SDK for Elixir</h1>

<p align="center">
  <a href="https://github.com/nshkrdotcom/claude_code_sdk_elixir/actions/workflows/elixir.yaml">
    <img src="https://github.com/nshkrdotcom/claude_code_sdk_elixir/actions/workflows/elixir.yaml/badge.svg" alt="CI">
  </a>
</p>

> **Note:** This SDK is fully compatible with the **Claude Code 2.0 CLI** and its latest features, including advanced authentication, model selection, and session management.

An Elixir SDK for programmatically interacting with Claude Code. This library provides a simple interface to query Claude and handle responses using the familiar Elixir streaming patterns.

## Architecture

```mermaid
graph TB
    subgraph "Your Elixir Application"
        A[ClaudeCodeSDK] --> B[Process Manager]
        B --> C[Message Parser]
        B --> D[Auth Checker]
    end
    
    subgraph "Claude Code CLI"
        E[claude-code executable]
        E --> F[API Communication]
    end
    
    subgraph "Claude API"
        G[Claude Service]
    end
    
    A -->|spawn & control| E
    E -->|HTTPS| G
    G -->|Responses| E
    E -->|JSON stream| B
    C -->|Parsed Messages| A
    
    style A fill:#4a9eff,stroke:#2d7dd2,stroke-width:2px,color:#000
    style G fill:#ff6b6b,stroke:#ff4757,stroke-width:2px,color:#000
```

## Prerequisites

This SDK requires the Claude Code CLI to be installed:

```bash
npm install -g @anthropic-ai/claude-code
```

## Installation

Add `claude_code_sdk` to your list of dependencies in `mix.exs`:

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

## Quick Start

1. **Authenticate the CLI** (do this once):
   ```bash
   claude login
   ```

2. **Install dependencies**:
   ```bash
   mix deps.get
   ```

3. **Run the showcase**:
   ```bash
   # Safe demo with mocks (no API costs)
   mix showcase
   
   # Live demo with real API calls (requires authentication)
   mix showcase --live
   ```

4. **Try the live script runner**:
   ```bash
   # Run example scripts with live API calls
   mix run.live examples/basic_example.exs
   mix run.live examples/simple_analyzer.exs lib/claude_code_sdk.ex
   ```

## Implementation Status

### ✅ **Currently Implemented (v0.2.0)**
- **Core SDK Functions**: `query/2`, `continue/2`, `resume/3` with stdin support
- **Live Script Runner**: `mix run.live` for executing scripts with real API calls
- **Message Processing**: Structured message types with proper parsing
- **Options Configuration**: Full CLI argument mapping with smart presets and correct CLI formats
- **Subprocess Management**: Robust erlexec integration with stdin support
- **JSON Parsing**: Custom parser without external dependencies
- **Authentication Management**: AutoManager with OAuth token support (v2.0.10+)
  - Automatic token setup via `mix claude.setup_token`
  - Token persistence and auto-refresh (1 year validity)
  - Multi-provider support (Anthropic/Bedrock/Vertex)
  - Environment variable fallback (`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`)
- **Model Selection**: Choose Opus, Sonnet, Haiku, or specific versions
  - Automatic fallback when model overloaded
  - Full model name support (e.g., `claude-sonnet-4-5-20250929`)
- **Custom Agents**: Define specialized agents with custom prompts
- **Concurrent Orchestration**: Parallel query execution and workflows
  - `Orchestrator.query_parallel/2` - Run queries concurrently (3-5x faster)
  - `Orchestrator.query_pipeline/2` - Sequential workflows with context passing
  - `Orchestrator.query_with_retry/3` - Automatic retry with exponential backoff
- **Session Persistence** (v0.2.0): Save and resume sessions across restarts
  - `SessionStore` GenServer for session management
  - Save/load sessions with tags and metadata
  - Search by tags, date range, cost
  - Automatic cleanup of old sessions
- **Advanced Session Flags** (v0.2.0): Additional CLI capabilities
  - Session forking (`fork_session`) - Experiment with different approaches
  - Multiple directories (`add_dir`) - Work across project boundaries
  - Strict MCP config (`strict_mcp_config`) - Isolated MCP testing
- **Error Handling**: Improved error detection and timeout handling
- **Stream Processing**: Lazy evaluation with Elixir Streams
- **Mocking System**: Comprehensive testing without API calls (supports stdin workflows)
- **Code Quality**: Full dialyzer and credo compliance with refactored complex functions
- **Developer Tools**: ContentExtractor, AuthChecker, OptionBuilder, DebugMode, AuthManager
- **Smart Configuration**: Environment-aware defaults and preset configurations

### 🔮 **Planned Features (v0.3.0+)**
- **Bidirectional Streaming**: Character-level streaming for chat UIs
- **Telemetry Integration**: Production observability with :telemetry events
- **Performance Optimization**: Caching, memory optimization
- **Integration Patterns**: Phoenix LiveView examples, OTP applications, worker pools
- **Advanced Examples**: Code analysis pipelines, test generators, refactoring tools
- **Plugin System**: Extensible architecture for custom behaviors

## Basic Usage

```elixir
# Simple query with smart content extraction
alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

# Use preset development options
options = OptionBuilder.build_development_options()

ClaudeCodeSDK.query("Say exactly: Hello from Elixir!", options)
|> Enum.each(fn msg ->
  case msg.type do
    :assistant ->
      content = ContentExtractor.extract_text(msg)
      IO.puts("🤖 Claude: #{content}")
      
    :result ->
      if msg.subtype == :success do
        IO.puts("✅ Success! Cost: $#{msg.data.total_cost_usd}")
      end
  end
end)
```

## Testing with Mocks

The SDK includes a comprehensive mocking system for testing without making actual API calls.

### Running Tests

```bash
# Run tests with mocks (default)
mix test

# Run tests with live API calls
MIX_ENV=test mix test.live

# Run specific test with live API
MIX_ENV=test mix test.live test/specific_test.exs
```

### Using Mocks in Your Code

```elixir
# Enable mocking
Application.put_env(:claude_code_sdk, :use_mock, true)

# Start the mock server
{:ok, _} = ClaudeCodeSDK.Mock.start_link()

# Set a mock response
ClaudeCodeSDK.Mock.set_response("hello", [
  %{
    "type" => "assistant",
    "message" => %{"content" => "Hello from mock!"}
  }
])

# Query will return mock response
ClaudeCodeSDK.query("say hello") |> Enum.to_list()
```

### Mock Demo

Run the included demo to see mocking in action:

```bash
mix run demo_mock.exs
```

For detailed documentation about the mocking system, see [MOCKING.md](MOCKING.md).

## Available Files to Run

### 🎯 Showcase (Recommended Starting Point)
```bash
# Safe demo with mocks (no API costs)  
mix showcase

# Live demo with real API calls (requires authentication)
mix showcase --live
```

### Additional Examples & Tests
- `mix run final_test.exs` - Complete test showing message parsing and interaction
- `mix run example.exs` - Basic usage example
- `mix run demo_mock.exs` - Mock system demonstration
- `mix run test_full.exs` - Alternative test format
- `mix run test_mix.exs` - Basic erlexec functionality test

**🌟 Start with `mix showcase` for a complete overview of all features!**

## Live Script Runner

The SDK includes a powerful `mix run.live` task for executing Elixir scripts with live Claude API calls:

### Usage

```bash
# Run any .exs script with live API
mix run.live script.exs [args...]

# Examples
mix run.live examples/basic_example.exs
mix run.live examples/simple_analyzer.exs lib/claude_code_sdk.ex
mix run.live examples/file_reviewer.exs path/to/your/file.txt
```

### Features

- **🔴 Live API Integration**: Makes real Claude API calls with proper stdin handling
- **⚠️ Cost Warnings**: Clear warnings about API usage and costs
- **📄 Argument Passing**: Supports passing arguments to scripts
- **🛡️ Safe by Default**: Requires explicit live mode activation
- **🎭 Mock Fallback**: Scripts can still run in mock mode during development

### Difference from Regular `mix run`

| **Command** | **API Calls** | **Costs** | **Authentication Required** |
|-------------|---------------|-----------|---------------------------|
| `mix run script.exs` | None (mock mode) | $0.00 | No |
| `mix run.live script.exs` | Real API calls | Real costs | Yes (`claude login`) |

### Example Scripts

The SDK includes several example scripts you can run immediately:

```bash
# Basic factorial function generation
mix run.live examples/basic_example.exs

# Code analysis with file input
mix run.live examples/simple_analyzer.exs lib/claude_code_sdk.ex

# Simple batch processing
mix run.live examples/simple_batch.exs

# File review and analysis
mix run.live examples/file_reviewer.exs README.md
```

### Creating Your Own Live Scripts

Create scripts that automatically work in both mock and live modes:

```elixir
#!/usr/bin/env elixir

# Check if we're in live mode
if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

# Your script logic here...
response = ClaudeCodeSDK.query("Your prompt here")
|> extract_response()

IO.puts("Response: #{response}")
```

### 🎭 Mock vs Live Mode

**All examples and tests can run in two modes:**

| **Mode** | **Command Format** | **API Calls** | **Costs** | **Authentication Required** |
|----------|-------------------|---------------|-----------|---------------------------|
| **Mock** | `mix showcase` | None (mocked) | $0.00 | No |
| **Live** | `mix showcase --live` | Real API calls | Real costs | Yes (`claude login`) |

### 🎯 Showcase Features

The showcase demonstrates all SDK functionality:

| **Feature Demonstrated** | **What It Shows** |
|-------------------------|-------------------|
| **OptionBuilder** | Smart configuration presets for development, production, chat, analysis |
| **AuthChecker** | Environment validation and authentication diagnostics |
| **Basic SDK Usage** | Core query functionality with mocked/real responses |
| **ContentExtractor** | Easy text extraction from complex message formats |
| **DebugMode** | Message analysis, benchmarking, troubleshooting tools |
| **Mock System** | Complete testing infrastructure without API costs |
| **Advanced Configurations** | Real-world scenarios for different use cases |
| **Performance Features** | Benchmarking and timing analysis |

### 🚀 Running Examples

**⚠️ Live mode will make real API calls and incur costs. Always test with mock mode first!**

| **Command** | **Status** | **Notes** |
|-------------|------------|-----------|
| `mix showcase` | ✅ Working | Mock mode, fast, no costs |
| `mix showcase --live` | ✅ Working | Live mode, real API calls, no hanging |
| `mix test` | ✅ Working | Mock mode, 75 tests, 17 skipped |
| `mix test.live` | ✅ Working | Live mode, properly warns about costs |
| `mix run example.exs` | ✅ Working | Uses mock mode by default, auto-starts Mock |
| `mix run examples/simple_analyzer.exs` | ✅ Working | Uses mock mode by default |
| `mix run.live examples/basic_example.exs` | ✅ Working | Live mode, real API calls, stdin support |
| `mix run.live examples/simple_analyzer.exs` | ✅ Working | Live mode, file analysis with arguments |

## API Reference

### Main Functions

#### `ClaudeCodeSDK.query(prompt, options \\ nil)`
Runs a query against Claude Code and returns a stream of messages.

```elixir
# Simple query
ClaudeCodeSDK.query("Write a hello world function")
|> Enum.to_list()

# With options
options = %ClaudeCodeSDK.Options{max_turns: 5, verbose: true}
ClaudeCodeSDK.query("Complex task", options)
|> Enum.to_list()
```

#### `ClaudeCodeSDK.continue(prompt \\ nil, options \\ nil)`
Continues the most recent conversation.

```elixir
ClaudeCodeSDK.continue("Now add error handling")
|> Enum.to_list()
```

#### `ClaudeCodeSDK.resume(session_id, prompt \\ nil, options \\ nil)`
Resumes a specific conversation by session ID.

```elixir
ClaudeCodeSDK.resume("session-id-here", "Add tests")
|> Enum.to_list()
```

### Options & Smart Presets

Configure requests with `ClaudeCodeSDK.Options` or use smart presets:

```elixir
# Manual configuration
%ClaudeCodeSDK.Options{
  max_turns: 10,              # Maximum conversation turns
  system_prompt: "Custom...", # Override system prompt
  output_format: :stream_json,# Output format
  verbose: true,              # Enable verbose logging
  cwd: "/path/to/project"     # Working directory
}

# Smart presets with OptionBuilder
alias ClaudeCodeSDK.OptionBuilder

# Development: permissive settings, verbose logging
options = OptionBuilder.build_development_options()

# Production: restricted settings, minimal tools
options = OptionBuilder.build_production_options()

# Analysis: read-only tools for code analysis
options = OptionBuilder.build_analysis_options()

# Chat: simple conversations
options = OptionBuilder.build_chat_options()

# Auto-detect based on Mix.env()
options = OptionBuilder.for_environment()

# Custom combinations
options = OptionBuilder.merge(:development, %{max_turns: 5})
```

### Message Types

The SDK returns a stream of `ClaudeCodeSDK.Message` structs with these types:

- **`:system`** - Session initialization (session_id, model, tools)
- **`:user`** - User messages  
- **`:assistant`** - Claude's responses
- **`:result`** - Final result with cost/duration stats

### Message Processing

Use the built-in `ContentExtractor` for easy message processing:

```elixir
alias ClaudeCodeSDK.ContentExtractor

# Extract all assistant responses
content = ClaudeCodeSDK.query("Your prompt")
|> Stream.filter(fn msg -> msg.type == :assistant end)
|> Stream.map(&ContentExtractor.extract_text/1)
|> Enum.join("\n")

# Check if message has text content
if ContentExtractor.has_text?(message) do
  text = ContentExtractor.extract_text(message)
  IO.puts("Response: #{text}")
end
```

## Authentication

### Automatic Authentication (v0.1.0+)

The SDK now provides automatic token management with the AuthManager:

```bash
# One-time setup (requires Claude subscription)
$ mix claude.setup_token
```

This generates a long-lived OAuth token (1 year) and stores it securely. The SDK automatically uses this token for all queries.

### Environment Variable (Recommended for CI/CD)

```bash
# Set OAuth token
export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-your-token-here

# Or use API key (legacy)
export ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
```

The SDK automatically detects and uses these environment variables.

### Legacy: Manual CLI Login

```bash
# Still supported but requires re-authentication
$ claude login
```

This SDK also supports your already-authenticated Claude CLI session.

### Authentication Checking

Use `AuthManager` to check status:

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

# Ensure authenticated (auto-setup if needed)
:ok = AuthManager.ensure_authenticated()
```

## Model Selection (v0.1.0+)

Choose the best Claude model for your task:

```elixir
alias ClaudeCodeSDK.OptionBuilder

# Opus - Most capable, complex reasoning
options = OptionBuilder.with_opus()
ClaudeCodeSDK.query("Design a complex system architecture", options)

# Sonnet - Balanced, cost-effective (default)
options = OptionBuilder.with_sonnet()
ClaudeCodeSDK.query("Review this code", options)

# Haiku - Fastest, lowest cost
options = OptionBuilder.with_haiku()
ClaudeCodeSDK.query("What is 2+2?", options)

# Custom model with automatic fallback
options = %Options{
  model: "opus",
  fallback_model: "sonnet"  # If opus is overloaded
}

# Use specific model version
options = %Options{
  model: "claude-sonnet-4-5-20250929"
}
```

## Custom Agents (v0.1.0+)

Define specialized agents with custom prompts:

```elixir
# Define a security-focused agent
options = %Options{
  agents: %{
    "security_reviewer" => %{
      description: "Security vulnerability scanner",
      prompt: """
      You are a security expert specializing in OWASP Top 10.
      Review code for vulnerabilities and provide specific fixes.
      """
    }
  }
}

ClaudeCodeSDK.query("Review this authentication code", options)

# Or use OptionBuilder helper
options = OptionBuilder.build_analysis_options()
|> OptionBuilder.with_agent("security_reviewer", %{
  description: "Security expert",
  prompt: "Review for OWASP Top 10 vulnerabilities"
})
```

## Concurrent Orchestration (v0.1.0+)

Execute multiple queries in parallel for 3-5x speedup:

```elixir
alias ClaudeCodeSDK.Orchestrator

# Parallel execution
queries = [
  {"Analyze file1.ex", analysis_opts},
  {"Analyze file2.ex", analysis_opts},
  {"Analyze file3.ex", analysis_opts}
]

{:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 3)

Enum.each(results, fn result ->
  IO.puts("Prompt: #{result.prompt}")
  IO.puts("Success: #{result.success}")
  IO.puts("Cost: $#{result.cost}")
  IO.puts("Duration: #{result.duration_ms}ms")
end)

# Pipeline workflows (output → next input)
{:ok, final_result} = Orchestrator.query_pipeline([
  {"Analyze code quality", analysis_opts},
  {"Suggest refactorings", refactor_opts},
  {"Generate tests for refactored code", test_opts}
], use_context: true)

# Retry with exponential backoff
{:ok, result} = Orchestrator.query_with_retry(
  prompt,
  options,
  max_retries: 3,
  backoff_ms: 1000
)
```

## Session Persistence (v0.2.0+)

Save and resume Claude conversations across application restarts:

```elixir
alias ClaudeCodeSDK.{SessionStore, Session}

# Start the session store
{:ok, _pid} = SessionStore.start_link()

# Execute a query
messages = ClaudeCodeSDK.query("Build a user authentication system")
|> Enum.to_list()

# Save the session with tags
session_id = Session.extract_session_id(messages)

:ok = SessionStore.save_session(session_id, messages,
  tags: ["feature-dev", "auth", "important"],
  description: "Building user authentication"
)

# Later... load and resume
{:ok, session_data} = SessionStore.load_session(session_id)
# session_data.messages - Full conversation history
# session_data.metadata - Tags, cost, timestamps

# Resume the conversation
ClaudeCodeSDK.resume(session_id, "Now add password reset functionality")

# Search sessions
security_sessions = SessionStore.search(tags: ["auth", "security"])
expensive_sessions = SessionStore.search(min_cost: 0.10)
recent_sessions = SessionStore.search(after: ~D[2025-10-01])

# Session forking - experiment with different approaches
fork_options = %Options{
  fork_session: true  # Creates new session ID, preserves context
}

ClaudeCodeSDK.resume(session_id, "Try a different approach", fork_options)
```

## Error Handling

```elixir
ClaudeCodeSDK.query("prompt")
|> Enum.each(fn msg ->
  case msg do
    %{type: :result, subtype: :success} ->
      IO.puts("✅ Success!")
      
    %{type: :result, subtype: error_type} when error_type in [:error_max_turns, :error_during_execution] ->
      IO.puts("❌ Error: #{error_type}")
      
    _ -> 
      # Process other message types
  end
end)
```

## Architecture

The SDK works by:
1. Spawning the Claude CLI as a subprocess using `erlexec`
2. Communicating via JSON messages over stdout/stderr  
3. Parsing responses into Elixir structs
4. Returning lazy Streams for efficient processing

Key benefits:
- ✅ Uses existing CLI authentication
- ✅ Efficient streaming processing
- ✅ No external JSON dependencies
- ✅ Robust subprocess management with erlexec

## Troubleshooting

**Module not available error**: Run with `mix run` instead of plain `elixir`:
```bash
# ❌ Won't work
elixir final_test.exs

# ✅ Works
mix run final_test.exs
```

**Authentication errors**: Make sure Claude CLI is authenticated:
```bash
claude login
```

**Process errors**: Ensure Claude CLI is installed:
```bash
npm install -g @anthropic-ai/claude-code
```

**CLI argument format errors**: Recent improvements have fixed common CLI format issues:
- Output format: Now correctly uses `stream-json` instead of `stream_json`
- Permission modes: Now correctly uses `acceptEdits` instead of `accept_edits`
- These fixes ensure compatibility with the latest Claude CLI versions

**Live mode not working**: Make sure you're using `mix run.live` for live API calls:
```bash
# ❌ Won't make live API calls
mix run examples/basic_example.exs

# ✅ Makes live API calls
mix run.live examples/basic_example.exs
```

### Debug Mode

Use `DebugMode` for detailed troubleshooting:

```elixir
alias ClaudeCodeSDK.DebugMode

# Run full diagnostics
DebugMode.run_diagnostics()

# Debug a specific query with timing
messages = DebugMode.debug_query("Hello")

# Benchmark performance
results = DebugMode.benchmark("Test query", nil, 3)
# Returns timing and cost statistics

# Analyze message statistics
stats = DebugMode.analyze_messages(messages)
```

## Developer Tools

The SDK includes four powerful modules to enhance your development experience:

### 🔧 OptionBuilder - Smart Configuration
Pre-configured option sets for common use cases:
- `build_development_options()` - Permissive settings for dev work
- `build_production_options()` - Secure settings for production  
- `build_analysis_options()` - Read-only tools for code analysis
- `build_chat_options()` - Simple conversation settings
- `for_environment()` - Auto-detects based on Mix.env()
- `merge/2` - Combine presets with custom options

### 🔍 AuthChecker - Environment Validation  
Prevents authentication errors with proactive checking:
- `authenticated?/0` - Quick boolean check
- `diagnose/0` - Full diagnostic with recommendations
- `ensure_ready!/0` - Raises if not ready for queries
- Helpful error messages and setup instructions

### 📜 ContentExtractor - Message Processing
Simplifies extracting text from complex message formats:
- `extract_text/1` - Get text from any message type
- `has_text?/1` - Check if message contains text content
- Handles strings, arrays, tool responses gracefully
- No more manual message parsing

### 🐛 DebugMode - Troubleshooting Tools
Comprehensive debugging and performance analysis:
- `debug_query/2` - Execute queries with detailed logging
- `run_diagnostics/0` - Full environment health check
- `benchmark/3` - Performance testing with statistics
- `analyze_messages/1` - Extract insights from message streams

## Main Use Cases

### 🔍 Code Analysis & Review
```elixir
# Analyze code quality and security with smart configuration
alias ClaudeCodeSDK.{OptionBuilder, ContentExtractor}

# Use analysis-specific options (read-only tools)
options = OptionBuilder.build_analysis_options()

analysis_result = ClaudeCodeSDK.query("""
Review this code for security vulnerabilities and performance issues:
#{File.read!("lib/user_auth.ex")}
""", options)
|> Stream.filter(&(&1.type == :assistant))
|> Stream.map(&ContentExtractor.extract_text/1)
|> Enum.join("\n")

IO.puts("📊 Analysis Result:\n#{analysis_result}")
```

### 📚 Documentation Generation **(FUTURE/PLANNED)**
```elixir
# Generate API documentation - FUTURE/PLANNED
ClaudeCodeSDK.query("Generate comprehensive docs for this module: #{file_content}")
|> Enum.filter(&(&1.type == :assistant))
|> Enum.map(&extract_content/1)  # extract_content helper not yet implemented
```

### 🧪 Test Generation **(FUTURE/PLANNED)**
```elixir
# Create test suites automatically - FUTURE/PLANNED
options = %ClaudeCodeSDK.Options{max_turns: 5}
ClaudeCodeSDK.query("Generate ExUnit tests for this module", options)
```

### 🔄 Code Refactoring **(FUTURE/PLANNED)**
```elixir
# Multi-step refactoring with session management - FUTURE/PLANNED
session_id = start_refactoring_session("lib/legacy_code.ex")  # Not yet implemented
ClaudeCodeSDK.resume(session_id, "Now optimize for performance")
ClaudeCodeSDK.resume(session_id, "Add proper error handling")
```

### 🤖 Interactive Development Assistant **(FUTURE/PLANNED)**
```elixir
# Pair programming sessions - FUTURE/PLANNED
ClaudeCodeSDK.query("I'm working on a GenServer. Help me implement proper state management")
|> Stream.each(&IO.puts(extract_content(&1)))  # extract_content helper not yet implemented
|> Stream.run()
```

### 🏗️ Project Scaffolding **(FUTURE/PLANNED)**
```elixir
# Generate boilerplate code - FUTURE/PLANNED  
ClaudeCodeSDK.query("""
Create a Phoenix LiveView component for user authentication with:
- Login/logout functionality  
- Session management
- Form validation
""")
```

## Testing and Development

### Environment Configuration

The SDK supports different configurations for different environments:

- **Test Environment**: Mocks enabled by default (`config/test.exs`)
- **Development Environment**: Real API calls (`config/dev.exs`)
- **Production Environment**: Real API calls (`config/prod.exs`)

### Writing Tests with Mocks

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  alias ClaudeCodeSDK.Mock

  setup do
    # Clear any existing mock responses
    Mock.clear_responses()
    :ok
  end

  test "my feature works correctly" do
    # Set up mock response
    Mock.set_response("analyze", [
      %{
        "type" => "assistant",
        "message" => %{"content" => "Analysis complete: No issues found."}
      }
    ])
    
    # Your code that uses ClaudeCodeSDK
    result = MyApp.analyze_code("def hello, do: :world")
    
    # Assertions
    assert result == "Analysis complete: No issues found."
  end
end
```

## 📖 Comprehensive Documentation

For detailed documentation covering all features, advanced patterns, and integration examples, see:

**[📋 COMPREHENSIVE_MANUAL.md](COMPREHENSIVE_MANUAL.md)**

The comprehensive manual includes:
- 🏗️ **Architecture Deep Dive** - Internal workings and design patterns ✅ **IMPLEMENTED**
- ⚙️ **Advanced Configuration** - MCP support, security, performance tuning **(FUTURE/PLANNED)**
- 🔧 **Integration Patterns** - Phoenix LiveView, OTP applications, task pipelines **(FUTURE/PLANNED)**
- 🛡️ **Security & Best Practices** - Input validation, permission management **(FUTURE/PLANNED)**
- 🐛 **Troubleshooting Guide** - Common issues and debugging techniques **(FUTURE/PLANNED)**
- 💡 **Real-World Examples** - Code analysis, test generation, refactoring tools **(FUTURE/PLANNED)**

## License

MIT License
