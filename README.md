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

3. **Run a test**:
   ```bash
   mix run final_test.exs
   ```

## Implementation Status

### ✅ **Currently Implemented**
- **Core SDK Functions**: `query/2`, `continue/2`, `resume/3` 
- **Message Processing**: Structured message types with proper parsing
- **Options Configuration**: Full CLI argument mapping
- **Subprocess Management**: Robust erlexec integration
- **JSON Parsing**: Custom parser without external dependencies
- **Authentication**: CLI delegation (no API keys needed)
- **Error Handling**: Basic error detection and reporting
- **Stream Processing**: Lazy evaluation with Elixir Streams
- **Mocking System**: Comprehensive testing without API calls
- **Code Quality**: Full dialyzer and credo compliance

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
# Simple query
ClaudeCodeSDK.query("Say exactly: Hello from Elixir!")
|> Enum.each(fn msg ->
  case msg.type do
    :assistant ->
      content = case msg.data.message do
        %{"content" => text} when is_binary(text) -> text
        %{"content" => [%{"text" => text}]} -> text
        _ -> inspect(msg.data.message)
      end
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

### Test Files
- `mix run final_test.exs` - Complete test showing message parsing and interaction
- `mix run test_full.exs` - Alternative test format
- `mix run test_mix.exs` - Basic erlexec functionality test

### Example Files  
- `mix run example.exs` - Basic usage example
- `mix run debug_test.exs` - Debugging script (if present)
- `mix run demo_mock.exs` - Mock system demonstration

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

### Options

Configure requests with `ClaudeCodeSDK.Options`:

```elixir
%ClaudeCodeSDK.Options{
  max_turns: 10,              # Maximum conversation turns
  system_prompt: "Custom...", # Override system prompt
  output_format: :stream_json,# Output format
  verbose: true,              # Enable verbose logging
  cwd: "/path/to/project"     # Working directory
}
```

### Message Types

The SDK returns a stream of `ClaudeCodeSDK.Message` structs with these types:

- **`:system`** - Session initialization (session_id, model, tools)
- **`:user`** - User messages  
- **`:assistant`** - Claude's responses
- **`:result`** - Final result with cost/duration stats

### Message Processing

```elixir
ClaudeCodeSDK.query("Your prompt")
|> Stream.filter(fn msg -> msg.type == :assistant end)
|> Stream.map(fn msg -> extract_content(msg) end)
|> Enum.join("\n")

defp extract_content(msg) do
  case msg.data.message do
    %{"content" => text} when is_binary(text) -> text
    %{"content" => [%{"text" => text}]} -> text
    _ -> inspect(msg.data.message)
  end
end
```

## Authentication

This SDK uses your already-authenticated Claude CLI instance. No API keys needed - just run `claude login` once and the SDK uses the stored session.

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

## Main Use Cases

### 🔍 Code Analysis & Review
```elixir
# Analyze code quality and security
ClaudeCodeSDK.query("""
Review this code for security vulnerabilities and performance issues:
#{File.read!("lib/user_auth.ex")}
""")
|> Stream.filter(&(&1.type == :assistant))
|> Enum.join("\n")
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
