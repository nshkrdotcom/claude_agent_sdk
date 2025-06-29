# Claude Code SDK for Elixir

An Elixir SDK for programmatically interacting with Claude Code. This library provides a simple interface to query Claude and handle responses using the familiar Elixir streaming patterns.

## Prerequisites

This SDK requires the Claude Code CLI to be installed:

```bash
npm install -g @anthropic-ai/claude-code
```

## Installation

Add dependencies to your `mix.exs`:

```elixir
def deps do
  [
    {:erlexec, "~> 2.0"},
    {:ex_doc, "~> 0.31", only: :dev, runtime: false}
  ]
end
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

## Implementation Status

### ✅ **Currently Implemented**
- **Core SDK Functions**: `query/2`, `continue/2`, `resume/3` 
- **Message Processing**: Structured message types with proper parsing
- **Options Configuration**: Full CLI argument mapping with smart presets
- **Subprocess Management**: Robust erlexec integration
- **JSON Parsing**: Custom parser without external dependencies
- **Authentication**: CLI delegation with status checking and diagnostics
- **Error Handling**: Basic error detection and reporting
- **Stream Processing**: Lazy evaluation with Elixir Streams
- **Mocking System**: Comprehensive testing without API calls
- **Code Quality**: Full dialyzer and credo compliance
- **Developer Tools**: ContentExtractor, AuthChecker, OptionBuilder, DebugMode
- **Smart Configuration**: Environment-aware defaults and preset configurations

### 🔮 **Planned Features** 
- **Advanced Error Handling**: Retry logic, timeout handling, comprehensive error recovery
- **Performance Optimization**: Caching, parallel processing, memory optimization
- **Integration Patterns**: Phoenix LiveView, OTP applications, worker pools
- **Security Features**: Input validation, permission management, sandboxing
- **Developer Tools**: Debug mode, troubleshooting helpers, session management
- **Advanced Examples**: Code analysis pipelines, test generators, refactoring tools
- **MCP Support**: Model Context Protocol integration and tool management

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

This SDK uses your already-authenticated Claude CLI instance. No API keys needed - just run `claude login` once and the SDK uses the stored session.

### Authentication Checking

Use `AuthChecker` to verify your setup before making queries:

```elixir
alias ClaudeCodeSDK.AuthChecker

# Quick boolean check
if AuthChecker.authenticated?() do
  # Proceed with queries
  ClaudeCodeSDK.query("Hello!")
else
  IO.puts("Please run: claude login")
end

# Full diagnostic check
diagnosis = AuthChecker.diagnose()
# Returns: %{
#   cli_installed: true,
#   authenticated: true, 
#   status: :ready,
#   recommendations: []
# }

# Ensure ready or raise error
AuthChecker.ensure_ready!()
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

Apache License 2.0
