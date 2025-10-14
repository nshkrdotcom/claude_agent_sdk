# Claude Code SDK for Elixir - CLI Manual

A complete reference showing how to use the official Claude Code SDK features in our Elixir implementation.

## Implementation Status Checklist

### ✅ **Core Features (Implemented)**

- [x] **Basic SDK Usage**
  - [x] `query/2` function for simple prompts
  - [x] `continue/2` for continuing conversations  
  - [x] `resume/3` for resuming specific sessions
  - [x] Stream-based message processing

- [x] **Authentication**
  - [x] CLI authentication delegation (`claude login`)
  - [x] Support for ANTHROPIC_API_KEY environment variable
  - [x] Third-party provider support (AWS Bedrock, Google Vertex AI)

- [x] **Options Configuration**
  - [x] Complete `ClaudeAgentSDK.Options` struct
  - [x] All CLI arguments mapped to Elixir options
  - [x] Type-safe option definitions

- [x] **Message Types**
  - [x] `:system` messages with session initialization
  - [x] `:user` messages for user inputs
  - [x] `:assistant` messages for Claude responses
  - [x] `:result` messages with final statistics

- [x] **Output Formats**
  - [x] Text output (default)
  - [x] JSON output
  - [x] Streaming JSON output (`stream_json`)

- [x] **Session Management**
  - [x] Continue most recent conversation
  - [x] Resume specific conversations by session ID
  - [x] Session ID extraction from system messages

- [x] **Subprocess Management**
  - [x] Robust erlexec integration
  - [x] Process lifecycle management
  - [x] Stream processing with lazy evaluation

### ✅ **Advanced Features (Implemented)**

- [x] **Advanced Options**
  - [x] Custom system prompts  
  - [x] Tool allow/disallow lists
  - [x] Permission modes (`accept_edits`, `bypass_permissions`, `plan`)
  - [x] Working directory control

- [x] **Helper Modules**
  - [x] `AuthChecker` for authentication validation and diagnostics
  - [x] `ContentExtractor` for message text extraction and processing
  - [x] `OptionBuilder` for smart preset configurations
  - [x] `DebugMode` for comprehensive troubleshooting and performance analysis

- [x] **Authentication & Environment**
  - [x] Multi-provider support (Anthropic, AWS Bedrock, Google Vertex AI)
  - [x] Environment diagnostics and health checks
  - [x] API key source detection and validation

- [x] **Testing Infrastructure**
  - [x] Comprehensive mocking system for cost-free testing
  - [x] Live vs mock mode testing with `mix test.live`
  - [x] CI/CD integration with GitHub Actions

### ⏳ **Advanced Features (Planned)**

- [ ] **MCP Support**
  - [ ] MCP server configuration
  - [ ] MCP tool management (`mcp__server__tool` format)
  - [ ] Permission prompt tools

- [ ] **Error Handling & Recovery**
  - [ ] Retry mechanisms with exponential backoff
  - [ ] Advanced timeout handling
  - [ ] Comprehensive error classification

- [ ] **Performance Features**
  - [ ] Query result caching
  - [ ] Parallel processing for batch operations
  - [ ] Memory optimization for large responses

### ❌ **Not Supported**

- [ ] **Interactive Mode** (Elixir SDK is non-interactive only)
- [ ] **Input Streaming** (multi-turn JSON input)
- [ ] **Live Collaboration** (real-time editing)

---

## Core Usage Patterns

### Basic Query Execution

```elixir
# Simple text query
ClaudeAgentSDK.query("Write a function to calculate Fibonacci numbers")
|> Enum.to_list()

# With basic options
options = %ClaudeAgentSDK.Options{
  max_turns: 3,
  output_format: :stream_json,
  verbose: true
}

ClaudeAgentSDK.query("Build a REST API", options)
|> Enum.each(fn msg ->
  case msg.type do
    :assistant -> IO.puts("Claude: #{inspect(msg.data)}")
    :result -> IO.puts("Done! Cost: $#{msg.data.total_cost_usd}")
    _ -> :ok
  end
end)
```

### Session Management

```elixir
# Continue the most recent conversation
ClaudeAgentSDK.continue("Now add error handling")
|> Enum.to_list()

# Resume a specific session
session_id = "550e8400-e29b-41d4-a716-446655440000"
ClaudeAgentSDK.resume(session_id, "Add unit tests")
|> Enum.to_list()

# Extract session ID from messages
session_id = 
  ClaudeAgentSDK.query("Initial query")
  |> Enum.find(&(&1.type == :system))
  |> case do
    %{data: %{session_id: id}} -> id
    _ -> nil
  end
```

### Stream Processing

```elixir
# Filter and process assistant responses only
assistant_content = 
  ClaudeAgentSDK.query("Explain quantum computing")
  |> Stream.filter(&(&1.type == :assistant))
  |> Stream.map(fn msg -> 
    # Extract text content from message
    case msg.data do
      %{message: %{"content" => content}} when is_binary(content) -> content
      %{message: %{"content" => [%{"text" => text}]}} -> text
      _ -> inspect(msg.data)
    end
  end)
  |> Enum.join("\n")

# Real-time processing with early termination
ClaudeAgentSDK.query("Generate a large report")
|> Stream.take_while(fn msg ->
  case msg.type do
    :result -> false  # Stop at final result
    _ -> true
  end
end)
|> Stream.each(&IO.inspect/1)
|> Stream.run()
```

---

## Official SDK Feature Mapping

### Command Line Options → Elixir Options

| **CLI Flag** | **Elixir Option** | **Type** | **Example** |
|-------------|------------------|----------|-------------|
| `--print` | *Always applied* | - | Built into `query/2` |
| `--output-format` | `:output_format` | `:text \| :json \| :stream_json` | `output_format: :stream_json` |
| `--max-turns` | `:max_turns` | `integer()` | `max_turns: 5` |
| `--system-prompt` | `:system_prompt` | `String.t()` | `system_prompt: "You are a helpful assistant"` |
| `--append-system-prompt` | `:append_system_prompt` | `String.t()` | `append_system_prompt: "Focus on security"` |
| `--allowedTools` | `:allowed_tools` | `[String.t()]` | `allowed_tools: ["Bash", "Read", "Write"]` |
| `--disallowedTools` | `:disallowed_tools` | `[String.t()]` | `disallowed_tools: ["Bash"]` |
| `--mcp-config` | `:mcp_config` | `String.t()` | `mcp_config: "/path/to/config.json"` |
| `--permission-prompt-tool` | `:permission_prompt_tool` | `String.t()` | `permission_prompt_tool: "mcp__auth__approve"` |
| `--permission-mode` | `:permission_mode` | `:default \| :accept_edits \| :bypass_permissions \| :plan` | `permission_mode: :accept_edits` |
| `--verbose` | `:verbose` | `boolean()` | `verbose: true` |
| `--continue` | `continue/2` function | - | `ClaudeAgentSDK.continue("new prompt")` |
| `--resume` | `resume/3` function | - | `ClaudeAgentSDK.resume(session_id, "prompt")` |

### Authentication Methods

| **Official SDK** | **Elixir Implementation** | **Setup** |
|------------------|---------------------------|-----------|
| Anthropic API key | ✅ Supported via CLI | `claude login` or `ANTHROPIC_API_KEY=...` |
| Amazon Bedrock | ✅ Supported via CLI | `CLAUDE_AGENT_USE_BEDROCK=1` + AWS credentials |
| Google Vertex AI | ✅ Supported via CLI | `CLAUDE_AGENT_USE_VERTEX=1` + GCP credentials |

### Output Format Comparison

| **Format** | **CLI Example** | **Elixir Usage** |
|------------|-----------------|------------------|
| **Text** | `claude -p "prompt"` | `%Options{output_format: :text}` (default) |
| **JSON** | `claude -p "prompt" --output-format json` | `%Options{output_format: :json}` |
| **Stream JSON** | `claude -p "prompt" --output-format stream-json` | `%Options{output_format: :stream_json}` |

---

## Advanced Configuration Examples

### Smart Option Configuration with OptionBuilder

The SDK includes the `OptionBuilder` module for intelligent option presets:

```elixir
alias ClaudeAgentSDK.OptionBuilder

# Environment-aware options (recommended)
options = OptionBuilder.for_environment()  # Auto-detects dev/test/prod

# Pre-configured option sets
dev_options = OptionBuilder.build_development_options()     # Permissive, verbose
prod_options = OptionBuilder.build_production_options()     # Restrictive, safe
analysis_options = OptionBuilder.build_analysis_options()  # Read-only tools
chat_options = OptionBuilder.build_chat_options()          # Simple Q&A

# Customize presets
options = OptionBuilder.merge(:development, %{max_turns: 15})

# Builder pattern
options = 
  OptionBuilder.build_analysis_options()
  |> OptionBuilder.with_system_prompt("You are a security expert")
  |> OptionBuilder.with_turn_limit(10)

# Sandboxed execution
sandbox_options = OptionBuilder.sandboxed("/tmp/safe", ["Read", "Write"])
```

### MCP Integration (Planned)

```elixir
# MCP configuration with multiple servers
mcp_options = %ClaudeAgentSDK.Options{
  mcp_config: "/path/to/mcp_servers.json",
  allowed_tools: [
    "mcp__filesystem__read_file",
    "mcp__github__search_issues", 
    "mcp__slack__send_message"
  ],
  permission_prompt_tool: "mcp__auth__approve"
}

ClaudeAgentSDK.query("Search for performance issues and notify team", mcp_options)
```

---

## Error Handling Patterns

### Authentication Errors

```elixir
ClaudeAgentSDK.query("test")
|> Enum.each(fn msg ->
  case msg do
    %{type: :result, subtype: :error_during_execution} ->
      IO.puts("❌ Authentication required. Run 'claude login'")
      
    %{type: :result, subtype: :success} ->
      IO.puts("✅ Query completed successfully")
      
    _ ->
      # Process other message types
      :ok
  end
end)
```

### Timeout and Error Recovery

```elixir
# Wrap in a task with timeout
task = Task.async(fn ->
  ClaudeAgentSDK.query("complex query") |> Enum.to_list()
end)

case Task.yield(task, 30_000) do
  {:ok, messages} -> 
    IO.puts("Query completed with #{length(messages)} messages")
    
  nil -> 
    Task.shutdown(task, :brutal_kill)
    IO.puts("Query timed out after 30 seconds")
end
```

---

## Message Processing Utilities

### Content Extraction with ContentExtractor

The SDK now includes the built-in `ContentExtractor` module for easy message processing:

```elixir
alias ClaudeAgentSDK.ContentExtractor

# Extract text from any message
content = ContentExtractor.extract_text(message)

# Check if message has extractable text
if ContentExtractor.has_text?(message) do
  text = ContentExtractor.extract_text(message)
  IO.puts("Response: #{text}")
end

# Extract all text from a stream with custom separator
all_text = ContentExtractor.extract_all_text(messages, " | ")

# Get a summary/preview of long content
preview = ContentExtractor.summarize(message, 100)

# Real usage example
ClaudeAgentSDK.query("Explain this code")
|> Stream.filter(&ContentExtractor.has_text?/1)
|> Stream.map(&ContentExtractor.extract_text/1)
|> Enum.join("\n")
```

### Cost and Statistics Tracking

```elixir
defmodule StatsCollector do
  def collect_stats(stream) do
    messages = Enum.to_list(stream)
    
    result = Enum.find(messages, &(&1.type == :result))
    
    %{
      total_messages: length(messages),
      assistant_messages: Enum.count(messages, &(&1.type == :assistant)),
      cost_usd: get_in(result, [:data, :total_cost_usd]) || 0.0,
      duration_ms: get_in(result, [:data, :duration_ms]) || 0,
      turns: get_in(result, [:data, :num_turns]) || 0,
      session_id: get_in(result, [:data, :session_id]),
      success: result && result.subtype == :success
    }
  end
end

# Usage
stats = 
  ClaudeAgentSDK.query("Generate documentation")
  |> StatsCollector.collect_stats()

IO.puts("Cost: $#{stats.cost_usd}, Duration: #{stats.duration_ms}ms")
```

---

## Testing Patterns

### Mock Testing

```elixir
# In test files
defmodule MyAppTest do
  use ExUnit.Case
  
  setup do
    # Enable mocking for tests
    Application.put_env(:claude_agent_sdk, :use_mock, true)
    {:ok, _} = ClaudeAgentSDK.Mock.start_link()
    :ok
  end
  
  test "processes Claude responses correctly" do
    ClaudeAgentSDK.Mock.set_response("test", [
      %{
        "type" => "assistant",
        "message" => %{"content" => "Hello from mock!"}
      },
      %{
        "type" => "result",
        "subtype" => "success",
        "total_cost_usd" => 0.001
      }
    ])
    
    result = ClaudeAgentSDK.query("test") |> Enum.to_list()
    assert length(result) == 2
  end
end
```

### Live Testing

```elixir
# Set environment for live testing
# MIX_ENV=test mix test.live

defmodule LiveIntegrationTest do
  use ExUnit.Case
  
  @tag :live
  test "real API integration" do
    # Only runs with mix test.live
    result = 
      ClaudeAgentSDK.query("Say exactly: test response")
      |> Enum.to_list()
    
    assert Enum.any?(result, &(&1.type == :assistant))
    assert Enum.any?(result, &(&1.type == :result))
  end
end
```

---

## Real-World Usage Examples

### Code Analysis Pipeline

```elixir
defmodule CodeAnalyzer do
  def analyze_file(file_path) do
    content = File.read!(file_path)
    
    analysis = 
      ClaudeAgentSDK.query("""
      Analyze this code for security issues and best practices:
      
      ```
      #{content}
      ```
      
      Provide specific recommendations.
      """, %ClaudeAgentSDK.Options{
        max_turns: 3,
        system_prompt: "You are a security-focused code reviewer"
      })
      |> Stream.filter(&(&1.type == :assistant))
      |> Stream.map(&ContentHelper.extract_text/1)
      |> Enum.join("\n")
    
    %{
      file: file_path,
      analysis: analysis,
      timestamp: DateTime.utc_now()
    }
  end
end
```

### Batch Processing

```elixir
defmodule BatchProcessor do
  def process_files(file_paths) do
    file_paths
    |> Task.async_stream(
      fn file_path ->
        content = File.read!(file_path)
        
        ClaudeAgentSDK.query("Summarize this file: #{content}")
        |> Enum.filter(&(&1.type == :result && &1.subtype == :success))
        |> List.first()
      end,
      max_concurrency: 3,
      timeout: 60_000
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
```

### Interactive Session Manager

```elixir
defmodule SessionManager do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def new_session(prompt) do
    GenServer.call(__MODULE__, {:new_session, prompt})
  end
  
  def continue_session(session_id, prompt) do
    GenServer.call(__MODULE__, {:continue, session_id, prompt})
  end
  
  def init(_) do
    {:ok, %{sessions: %{}}}
  end
  
  def handle_call({:new_session, prompt}, _from, state) do
    stream = ClaudeAgentSDK.query(prompt)
    messages = Enum.to_list(stream)
    
    session_id = 
      messages
      |> Enum.find(&(&1.type == :system))
      |> case do
        %{data: %{session_id: id}} -> id
        _ -> :crypto.strong_rand_bytes(16) |> Base.encode16()
      end
    
    new_sessions = Map.put(state.sessions, session_id, messages)
    
    {:reply, {session_id, messages}, %{state | sessions: new_sessions}}
  end
  
  def handle_call({:continue, session_id, prompt}, _from, state) do
    messages = ClaudeAgentSDK.resume(session_id, prompt) |> Enum.to_list()
    new_sessions = Map.put(state.sessions, session_id, messages)
    
    {:reply, messages, %{state | sessions: new_sessions}}
  end
end
```

---

## Performance Considerations

### Memory Efficiency

```elixir
# Good: Stream processing (lazy evaluation)
ClaudeAgentSDK.query("large task")
|> Stream.filter(&(&1.type == :assistant))
|> Stream.take(10)  # Only process first 10 assistant messages
|> Enum.to_list()

# Avoid: Loading entire response into memory
# large_response = ClaudeAgentSDK.query("huge task") |> Enum.to_list()
```

### Rate Limiting

```elixir
defmodule RateLimitedClient do
  def query_with_delay(prompt, delay_ms \\ 1000) do
    result = ClaudeAgentSDK.query(prompt) |> Enum.to_list()
    Process.sleep(delay_ms)
    result
  end
  
  def batch_with_rate_limit(prompts, delay_ms \\ 1000) do
    prompts
    |> Enum.map(fn prompt ->
      result = query_with_delay(prompt, delay_ms)
      {prompt, result}
    end)
  end
end
```

---

## Troubleshooting Guide

### Common Issues

| **Problem** | **Symptom** | **Solution** |
|-------------|-------------|--------------|
| **Authentication** | `error_during_execution` result | Run `claude login` or set `ANTHROPIC_API_KEY` |
| **CLI not found** | Process spawn error | Install: `npm install -g @anthropic-ai/claude-code` |
| **Hanging queries** | Process never returns | Check timeout, verify CLI works: `claude --version` |
| **Empty responses** | No messages in stream | Check prompt format and authentication |
| **Parse errors** | JSON decode failures | Enable verbose mode: `verbose: true` |

### Debug Information with DebugMode

The SDK includes comprehensive debugging tools:

```elixir
alias ClaudeAgentSDK.DebugMode

# Run full environment diagnostics
DebugMode.run_diagnostics()
# Output: Complete system health check with CLI status, auth, environment

# Debug a specific query with detailed logging
messages = DebugMode.debug_query("Hello, Claude!")
# Output: Real-time debug info with timing, auth status, message analysis

# Performance profiling
{messages, profile} = DebugMode.profile_query("Complex task")
IO.puts("Peak memory: #{profile.peak_memory_mb}MB")
IO.puts("Execution time: #{profile.execution_time_ms}ms")

# Benchmark performance across multiple runs
results = DebugMode.benchmark("Test query", nil, 3)
IO.puts("Average duration: #{results.avg_duration_ms}ms")
IO.puts("Average cost: $#{results.avg_cost_usd}")

# Analyze message statistics
stats = DebugMode.analyze_messages(messages)
# Returns detailed analysis: message counts, costs, tools used, errors

# Inspect individual messages
formatted = DebugMode.inspect_message(message)
# Returns: "Message[assistant]: \"Hello!\" (6 chars)"
```

---

This manual provides complete coverage of the Claude Code SDK functionality as implemented in our Elixir version, with clear examples showing the mapping between official CLI features and our Elixir API.