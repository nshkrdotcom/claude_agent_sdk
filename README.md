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

## Available Files to Run

### Test Files
- `mix run final_test.exs` - Complete test showing message parsing and interaction
- `mix run test_full.exs` - Alternative test format
- `mix run test_mix.exs` - Basic erlexec functionality test

### Example Files  
- `mix run example.exs` - Basic usage example
- `mix run debug_test.exs` - Debugging script (if present)

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

### 📚 Documentation Generation
```elixir
# Generate API documentation
ClaudeCodeSDK.query("Generate comprehensive docs for this module: #{file_content}")
|> Enum.filter(&(&1.type == :assistant))
|> Enum.map(&extract_content/1)
```

### 🧪 Test Generation
```elixir
# Create test suites automatically
options = %ClaudeCodeSDK.Options{max_turns: 5}
ClaudeCodeSDK.query("Generate ExUnit tests for this module", options)
```

### 🔄 Code Refactoring
```elixir
# Multi-step refactoring with session management
session_id = start_refactoring_session("lib/legacy_code.ex")
ClaudeCodeSDK.resume(session_id, "Now optimize for performance")
ClaudeCodeSDK.resume(session_id, "Add proper error handling")
```

### 🤖 Interactive Development Assistant
```elixir
# Pair programming sessions
ClaudeCodeSDK.query("I'm working on a GenServer. Help me implement proper state management")
|> Stream.each(&IO.puts(extract_content(&1)))
|> Stream.run()
```

### 🏗️ Project Scaffolding
```elixir
# Generate boilerplate code
ClaudeCodeSDK.query("""
Create a Phoenix LiveView component for user authentication with:
- Login/logout functionality  
- Session management
- Form validation
""")
```

## 📖 Comprehensive Documentation

For detailed documentation covering all features, advanced patterns, and integration examples, see:

**[📋 COMPREHENSIVE_MANUAL.md](COMPREHENSIVE_MANUAL.md)**

The comprehensive manual includes:
- 🏗️ **Architecture Deep Dive** - Internal workings and design patterns
- ⚙️ **Advanced Configuration** - MCP support, security, performance tuning  
- 🔧 **Integration Patterns** - Phoenix LiveView, OTP applications, task pipelines
- 🛡️ **Security & Best Practices** - Input validation, permission management
- 🐛 **Troubleshooting Guide** - Common issues and debugging techniques
- 💡 **Real-World Examples** - Code analysis, test generation, refactoring tools

## License

Apache License 2.0
