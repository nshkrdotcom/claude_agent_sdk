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

### Key Features

- **Stream-based Processing**: Efficient handling of large responses through Elixir Streams
- **Subprocess Management**: Robust process handling using erlexec
- **Authentication Delegation**: Uses existing Claude CLI authentication
- **Full Feature Parity**: Supports all Claude Code CLI options and modes
- **Type Safety**: Structured message parsing with clear types
- **Error Recovery**: Comprehensive error handling and recovery mechanisms

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

- **`ClaudeCodeSDK`**: Main public API interface
- **`ClaudeCodeSDK.Query`**: Query construction and execution
- **`ClaudeCodeSDK.Process`**: Subprocess management with erlexec
- **`ClaudeCodeSDK.Message`**: Message parsing and type definitions
- **`ClaudeCodeSDK.Options`**: Configuration and CLI argument building
- **`ClaudeCodeSDK.JSON`**: Custom JSON parsing without external dependencies

### Data Flow

1. **Query Construction**: User prompt and options are converted to CLI arguments
2. **Process Spawning**: Claude CLI is spawned as a subprocess with proper arguments
3. **Stream Processing**: JSON responses are parsed and converted to Elixir structs
4. **Message Delivery**: Structured messages are yielded through an Elixir Stream

## Installation & Setup

### Dependencies

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:erlexec, "~> 2.0"},
    {:ex_doc, "~> 0.31", only: :dev, runtime: false}
  ]
end
```

### Prerequisites

1. **Node.js**: Required for Claude CLI
2. **Claude CLI**: Install globally
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```
3. **Authentication**: Authenticate once
   ```bash
   claude login
   ```

### Project Setup

```bash
# Clone or create your project
git clone your-project
cd your-project

# Install dependencies
mix deps.get

# Verify installation
mix run -e "ClaudeCodeSDK.query(\"Hello\") |> Enum.take(1) |> IO.inspect"
```

## Authentication

The SDK delegates all authentication to the Claude CLI, providing a simplified authentication model:

### One-Time Setup

```bash
# Authenticate with Anthropic
claude login

# Verify authentication
claude auth status
```

### Authentication in Code

```elixir
# No API keys needed in code!
# The SDK automatically uses CLI authentication

# Error handling for unauthenticated sessions
ClaudeCodeSDK.query("Hello")
|> Enum.each(fn msg ->
  case msg do
    %{type: :result, subtype: :error_during_execution} ->
      IO.puts("❌ Authentication required. Run 'claude login'")
    _ -> 
      # Process normal messages
  end
end)
```

### Authentication Status Check

```elixir
defmodule AuthChecker do
  def check_auth do
    case System.cmd("claude", ["auth", "status"]) do
      {output, 0} -> 
        IO.puts("✅ Authenticated: #{String.trim(output)}")
        true
      {error, _} -> 
        IO.puts("❌ Not authenticated: #{error}")
        false
    end
  end
end
```

## Core API Reference

### Primary Functions

#### `ClaudeCodeSDK.query/2`

Executes a single query with optional configuration.

```elixir
@spec query(String.t(), Options.t() | nil) :: Stream.t()

# Basic usage
ClaudeCodeSDK.query("Write a hello world function")

# With options
options = %ClaudeCodeSDK.Options{
  max_turns: 3,
  output_format: :stream_json,
  verbose: true
}
ClaudeCodeSDK.query("Complex task", options)
```

#### `ClaudeCodeSDK.continue/2`

Continues the most recent conversation.

```elixir
@spec continue(String.t() | nil, Options.t() | nil) :: Stream.t()

# Continue without additional prompt
ClaudeCodeSDK.continue()

# Continue with new prompt
ClaudeCodeSDK.continue("Now add error handling")

# Continue with options
options = %ClaudeCodeSDK.Options{max_turns: 5}
ClaudeCodeSDK.continue("Refactor for performance", options)
```

#### `ClaudeCodeSDK.resume/3`

Resumes a specific conversation by session ID.

```elixir
@spec resume(String.t(), String.t() | nil, Options.t() | nil) :: Stream.t()

# Resume existing session
session_id = "550e8400-e29b-41d4-a716-446655440000"
ClaudeCodeSDK.resume(session_id, "Add tests")

# Resume with options
ClaudeCodeSDK.resume(session_id, "Deploy", %ClaudeCodeSDK.Options{
  permission_mode: :bypass_permissions
})
```

### Options Configuration

The `ClaudeCodeSDK.Options` struct supports all Claude CLI options:

```elixir
%ClaudeCodeSDK.Options{
  # Conversation control
  max_turns: 10,                    # Limit conversation turns
  
  # System prompts
  system_prompt: "Custom prompt",   # Override system prompt
  append_system_prompt: "Extra",    # Append to default prompt
  
  # Output control
  output_format: :stream_json,      # :text, :json, :stream_json
  verbose: true,                    # Enable verbose logging
  
  # Tool management
  allowed_tools: ["Bash", "Read"],  # Allowed tool list
  disallowed_tools: ["Write"],      # Disallowed tool list
  
  # MCP configuration
  mcp_config: "/path/to/mcp.json",  # MCP server config
  permission_prompt_tool: "mcp__auth__prompt",
  
  # Permission modes
  permission_mode: :accept_edits,   # :default, :accept_edits, 
                                   # :bypass_permissions, :plan
  
  # Environment
  cwd: "/project/path",             # Working directory
  executable: "node",               # JavaScript runtime
  executable_args: ["--max-memory"], # Runtime arguments
  
  # Advanced
  path_to_claude_code_executable: "/custom/path/claude",
  abort_ref: make_ref()             # For cancellation
}
```

### Option Builder Pattern

```elixir
defmodule OptionBuilder do
  def build_development_options do
    ClaudeCodeSDK.Options.new(
      max_turns: 5,
      verbose: true,
      allowed_tools: ["Bash", "Read", "Write"],
      permission_mode: :accept_edits
    )
  end
  
  def build_production_options do
    ClaudeCodeSDK.Options.new(
      max_turns: 3,
      verbose: false,
      permission_mode: :plan,
      disallowed_tools: ["Bash"]
    )
  end
  
  def build_mcp_options(mcp_config_path) do
    ClaudeCodeSDK.Options.new(
      mcp_config: mcp_config_path,
      allowed_tools: ["mcp__filesystem__read", "mcp__github__search"],
      permission_prompt_tool: "mcp__auth__approve"
    )
  end
end
```

## Message Types & Processing

### Message Structure

All messages follow a consistent structure:

```elixir
%ClaudeCodeSDK.Message{
  type: :system | :user | :assistant | :result,
  subtype: atom() | nil,
  data: map(),
  raw: map()
}
```

### System Messages

Emitted at conversation start with session information:

```elixir
%{
  type: :system,
  subtype: :init,
  data: %{
    session_id: "550e8400-e29b-41d4-a716-446655440000",
    model: "claude-opus-4-20250514",
    cwd: "/project/path",
    tools: ["Bash", "Read", "Write"],
    mcp_servers: [%{name: "filesystem", status: "ready"}],
    permission_mode: "default",
    api_key_source: "env"
  }
}
```

### Assistant Messages

Claude's responses with structured content:

```elixir
%{
  type: :assistant,
  data: %{
    message: %{
      "role" => "assistant",
      "content" => "Response text here" # or structured content
    },
    session_id: "session-id"
  }
}
```

### User Messages

User inputs (when using multi-turn conversations):

```elixir
%{
  type: :user,
  data: %{
    message: %{
      "role" => "user",
      "content" => "User input here"
    },
    session_id: "session-id"
  }
}
```

### Result Messages

Final messages with conversation statistics:

```elixir
# Success result
%{
  type: :result,
  subtype: :success,
  data: %{
    result: "Final response text",
    session_id: "session-id",
    total_cost_usd: 0.025,
    duration_ms: 3420,
    duration_api_ms: 2100,
    num_turns: 3,
    is_error: false
  }
}

# Error result
%{
  type: :result,
  subtype: :error_max_turns, # or :error_during_execution
  data: %{
    session_id: "session-id",
    total_cost_usd: 0.015,
    duration_ms: 5000,
    num_turns: 10,
    is_error: true,
    error: "Max turns exceeded"
  }
}
```

### Content Extraction Helpers

```elixir
defmodule ContentExtractor do
  def extract_text(message) do
    case message do
      %{type: :assistant, data: %{message: %{"content" => content}}} ->
        extract_content_text(content)
      _ -> 
        nil
    end
  end
  
  defp extract_content_text(content) when is_binary(content), do: content
  defp extract_content_text([%{"text" => text}]), do: text
  defp extract_content_text(content_list) when is_list(content_list) do
    content_list
    |> Enum.map(fn
      %{"text" => text} -> text
      %{"type" => "tool_use"} = tool -> "[Tool: #{tool["name"]}]"
      other -> inspect(other)
    end)
    |> Enum.join(" ")
  end
  defp extract_content_text(other), do: inspect(other)
end
```

## Advanced Usage Patterns

### Stream Processing Patterns

#### Filter and Transform

```elixir
# Extract only assistant responses
assistant_responses = 
  ClaudeCodeSDK.query("Explain quantum computing")
  |> Stream.filter(&(&1.type == :assistant))
  |> Stream.map(&ContentExtractor.extract_text/1)
  |> Enum.join("\n")

# Process messages in real-time
ClaudeCodeSDK.query("Generate a large report")
|> Stream.each(fn msg ->
  case msg.type do
    :assistant -> 
      IO.puts("📝 #{ContentExtractor.extract_text(msg)}")
    :result -> 
      IO.puts("💰 Cost: $#{msg.data.total_cost_usd}")
    _ -> 
      :ok
  end
end)
|> Stream.run()
```

#### Chunked Processing

```elixir
# Process messages in chunks
ClaudeCodeSDK.query("Generate 100 test cases")
|> Stream.chunk_every(5)
|> Stream.each(fn chunk ->
  IO.puts("Processing chunk of #{length(chunk)} messages...")
  # Process chunk
end)
|> Stream.run()
```

#### Early Termination

```elixir
# Stop when specific condition is met
ClaudeCodeSDK.query("Find all bugs in this codebase")
|> Stream.take_while(fn msg ->
  case msg do
    %{type: :result} -> false  # Stop at result
    %{type: :assistant} -> 
      text = ContentExtractor.extract_text(msg)
      not String.contains?(text, "CRITICAL_BUG_FOUND")
    _ -> true
  end
end)
|> Enum.to_list()
```

### Session Management

#### Session Tracking

```elixir
defmodule SessionManager do
  use GenServer
  
  # Client API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def track_session(prompt, options \\ nil) do
    GenServer.call(__MODULE__, {:track_session, prompt, options})
  end
  
  def get_recent_sessions(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_recent_sessions, limit})
  end
  
  def continue_session(session_id, prompt) do
    GenServer.call(__MODULE__, {:continue_session, session_id, prompt})
  end
  
  # Server callbacks
  def init(state) do
    {:ok, %{sessions: [], current_session: nil}}
  end
  
  def handle_call({:track_session, prompt, options}, _from, state) do
    stream = ClaudeCodeSDK.query(prompt, options)
    
    # Extract session info from first message
    session_info = 
      stream
      |> Enum.find(&(&1.type == :system))
      |> case do
        %{data: %{session_id: id}} -> 
          %{id: id, prompt: prompt, started_at: DateTime.utc_now()}
        _ -> 
          nil
      end
    
    new_state = 
      if session_info do
        %{state | 
          sessions: [session_info | state.sessions],
          current_session: session_info.id
        }
      else
        state
      end
    
    {:reply, stream, new_state}
  end
  
  def handle_call({:get_recent_sessions, limit}, _from, state) do
    recent = state.sessions |> Enum.take(limit)
    {:reply, recent, state}
  end
  
  def handle_call({:continue_session, session_id, prompt}, _from, state) do
    stream = ClaudeCodeSDK.resume(session_id, prompt)
    {:reply, stream, state}
  end
end
```

#### Conversation Chains

```elixir
defmodule ConversationChain do
  def run_chain(prompts, options \\ nil) when is_list(prompts) do
    [first_prompt | rest_prompts] = prompts
    
    # Start with first prompt
    session_id = get_session_id(ClaudeCodeSDK.query(first_prompt, options))
    
    # Continue with remaining prompts
    Enum.reduce(rest_prompts, session_id, fn prompt, acc_session_id ->
      stream = ClaudeCodeSDK.resume(acc_session_id, prompt, options)
      
      # Process stream and return session_id
      stream |> Enum.to_list()
      acc_session_id
    end)
  end
  
  defp get_session_id(stream) do
    stream
    |> Enum.find(&(&1.type == :system))
    |> case do
      %{data: %{session_id: id}} -> id
      _ -> nil
    end
  end
end

# Usage
conversation_steps = [
  "Create a new React component",
  "Add TypeScript types to the component", 
  "Write unit tests for the component",
  "Add documentation and examples"
]

ConversationChain.run_chain(conversation_steps)
```

### Concurrent Processing

#### Parallel Queries

```elixir
defmodule ParallelProcessor do
  def run_parallel_queries(prompts, options \\ nil) do
    prompts
    |> Enum.map(fn prompt ->
      Task.async(fn ->
        ClaudeCodeSDK.query(prompt, options)
        |> Enum.to_list()
      end)
    end)
    |> Enum.map(&Task.await(&1, 60_000))  # 60 second timeout
  end
  
  def run_with_rate_limit(prompts, rate_limit_ms \\ 1000) do
    prompts
    |> Enum.map(fn prompt ->
      result = ClaudeCodeSDK.query(prompt) |> Enum.to_list()
      Process.sleep(rate_limit_ms)
      result
    end)
  end
end

# Usage
prompts = [
  "Explain async/await in JavaScript",
  "Show me Python list comprehensions", 
  "Describe Rust ownership model"
]

results = ParallelProcessor.run_parallel_queries(prompts)
```

## Error Handling & Recovery

### Error Types

#### Authentication Errors

```elixir
defmodule ErrorHandler do
  def handle_auth_error(stream) do
    stream
    |> Stream.each(fn msg ->
      case msg do
        %{type: :result, subtype: :error_during_execution} ->
          raise "Authentication required. Run 'claude login' first."
        _ -> 
          :ok
      end
    end)
    |> Stream.run()
  end
end
```

#### Timeout Handling

```elixir
defmodule TimeoutHandler do
  def query_with_timeout(prompt, timeout_ms \\ 30_000) do
    task = Task.async(fn ->
      ClaudeCodeSDK.query(prompt) |> Enum.to_list()
    end)
    
    case Task.yield(task, timeout_ms) do
      {:ok, result} -> 
        {:ok, result}
      nil -> 
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end
end
```

#### Retry Logic

```elixir
defmodule RetryHandler do
  def query_with_retry(prompt, max_retries \\ 3, delay_ms \\ 1000) do
    do_query_with_retry(prompt, max_retries, delay_ms, 0)
  end
  
  defp do_query_with_retry(prompt, max_retries, delay_ms, attempt) do
    try do
      result = ClaudeCodeSDK.query(prompt) |> Enum.to_list()
      {:ok, result}
    rescue
      error ->
        if attempt < max_retries do
          IO.puts("Retry #{attempt + 1}/#{max_retries} after error: #{inspect(error)}")
          Process.sleep(delay_ms)
          do_query_with_retry(prompt, max_retries, delay_ms, attempt + 1)
        else
          {:error, error}
        end
    end
  end
end
```

#### Comprehensive Error Handler

```elixir
defmodule ComprehensiveErrorHandler do
  def safe_query(prompt, options \\ nil) do
    try do
      ClaudeCodeSDK.query(prompt, options)
      |> Stream.map(&validate_message/1)
      |> Enum.to_list()
      |> case do
        [] -> {:error, :no_messages}
        messages -> classify_result(messages)
      end
    rescue
      error -> {:error, {:exception, error}}
    catch
      :exit, reason -> {:error, {:exit, reason}}
    end
  end
  
  defp validate_message(msg) do
    case msg do
      %ClaudeCodeSDK.Message{} -> msg
      other -> 
        IO.warn("Invalid message format: #{inspect(other)}")
        msg
    end
  end
  
  defp classify_result(messages) do
    case List.last(messages) do
      %{type: :result, subtype: :success} = result ->
        {:ok, messages, extract_stats(result)}
        
      %{type: :result, subtype: :error_max_turns} ->
        {:error, :max_turns_exceeded, messages}
        
      %{type: :result, subtype: :error_during_execution} ->
        {:error, :execution_error, messages}
        
      _ ->
        {:error, :incomplete_conversation, messages}
    end
  end
  
  defp extract_stats(%{data: data}) do
    %{
      cost: data.total_cost_usd,
      duration: data.duration_ms,
      turns: data.num_turns,
      session_id: data.session_id
    }
  end
end
```

## Performance Optimization

### Stream Optimization

```elixir
defmodule PerformanceOptimizer do
  # Lazy evaluation for large responses
  def lazy_process_large_response(prompt) do
    ClaudeCodeSDK.query(prompt)
    |> Stream.filter(&(&1.type == :assistant))
    |> Stream.map(&extract_and_process_content/1)
    |> Stream.chunk_every(10)  # Process in chunks
  end
  
  # Memory-efficient content extraction
  defp extract_and_process_content(msg) do
    # Process content without holding entire response in memory
    content = ContentExtractor.extract_text(msg)
    
    # Immediate processing to reduce memory usage
    content
    |> String.split("\n")
    |> Enum.filter(&(String.length(&1) > 0))
    |> length()  # Just return count, not content
  end
  
  # Parallel processing with backpressure
  def parallel_with_backpressure(prompts, concurrency \\ 3) do
    prompts
    |> Task.async_stream(
      fn prompt ->
        ClaudeCodeSDK.query(prompt) |> Enum.to_list()
      end,
      max_concurrency: concurrency,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
    end)
  end
end
```

### Caching Strategies

```elixir
defmodule QueryCache do
  use GenServer
  
  # Cache based on prompt hash
  def cached_query(prompt, options \\ nil, ttl_ms \\ 300_000) do
    cache_key = :erlang.phash2({prompt, options})
    
    case GenServer.call(__MODULE__, {:get, cache_key}) do
      {:hit, result} -> 
        IO.puts("🎯 Cache hit for prompt")
        result
      :miss ->
        IO.puts("💾 Cache miss, executing query")
        result = ClaudeCodeSDK.query(prompt, options) |> Enum.to_list()
        GenServer.cast(__MODULE__, {:put, cache_key, result, ttl_ms})
        result
    end
  end
  
  # Server implementation
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(_) do
    {:ok, %{cache: %{}, timers: %{}}}
  end
  
  def handle_call({:get, key}, _from, %{cache: cache} = state) do
    result = case Map.get(cache, key) do
      nil -> :miss
      value -> {:hit, value}
    end
    {:reply, result, state}
  end
  
  def handle_cast({:put, key, value, ttl_ms}, state) do
    # Cancel existing timer
    if timer_ref = state.timers[key] do
      Process.cancel_timer(timer_ref)
    end
    
    # Set new timer
    timer_ref = Process.send_after(self(), {:expire, key}, ttl_ms)
    
    new_state = %{
      cache: Map.put(state.cache, key, value),
      timers: Map.put(state.timers, key, timer_ref)
    }
    
    {:noreply, new_state}
  end
  
  def handle_info({:expire, key}, state) do
    new_state = %{
      cache: Map.delete(state.cache, key),
      timers: Map.delete(state.timers, key)
    }
    {:noreply, new_state}
  end
end
```

## Integration Patterns

### Phoenix LiveView Integration

```elixir
defmodule MyAppWeb.ClaudeLive do
  use MyAppWeb, :live_view
  
  def mount(_params, _session, socket) do
    socket = 
      socket
      |> assign(:messages, [])
      |> assign(:query_stream, nil)
      |> assign(:loading, false)
    
    {:ok, socket}
  end
  
  def handle_event("send_query", %{"prompt" => prompt}, socket) do
    if socket.assigns.loading do
      {:noreply, socket}
    else
      # Start query stream
      query_stream = ClaudeCodeSDK.query(prompt)
      
      # Process stream asynchronously
      pid = self()
      Task.start(fn ->
        query_stream
        |> Enum.each(fn msg ->
          send(pid, {:claude_message, msg})
        end)
        send(pid, :claude_complete)
      end)
      
      socket = 
        socket
        |> assign(:loading, true)
        |> assign(:query_stream, query_stream)
      
      {:noreply, socket}
    end
  end
  
  def handle_info({:claude_message, msg}, socket) do
    case msg.type do
      :assistant ->
        content = ContentExtractor.extract_text(msg)
        new_message = %{type: :assistant, content: content, timestamp: DateTime.utc_now()}
        
        socket = update(socket, :messages, &[new_message | &1])
        {:noreply, socket}
        
      :result ->
        new_message = %{
          type: :result, 
          content: "Query completed. Cost: $#{msg.data.total_cost_usd}",
          timestamp: DateTime.utc_now()
        }
        
        socket = 
          socket
          |> update(:messages, &[new_message | &1])
          |> assign(:loading, false)
        
        {:noreply, socket}
        
      _ ->
        {:noreply, socket}
    end
  end
  
  def handle_info(:claude_complete, socket) do
    {:noreply, assign(socket, :loading, false)}
  end
end
```

### OTP Application Integration

```elixir
defmodule ClaudeCodeApp.Supervisor do
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  def init(_init_arg) do
    children = [
      {SessionManager, []},
      {QueryCache, []},
      {ClaudeWorkerPool, pool_size: 3}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule ClaudeWorkerPool do
  use GenServer
  
  def start_link(opts) do
    pool_size = Keyword.get(opts, :pool_size, 3)
    GenServer.start_link(__MODULE__, pool_size, name: __MODULE__)
  end
  
  def query(prompt, options \\ nil) do
    GenServer.call(__MODULE__, {:query, prompt, options}, 60_000)
  end
  
  def init(pool_size) do
    workers = for i <- 1..pool_size do
      {:ok, pid} = ClaudeWorker.start_link(name: :"claude_worker_#{i}")
      pid
    end
    
    {:ok, %{workers: workers, current: 0}}
  end
  
  def handle_call({:query, prompt, options}, _from, state) do
    worker = Enum.at(state.workers, state.current)
    next_index = rem(state.current + 1, length(state.workers))
    
    result = ClaudeWorker.query(worker, prompt, options)
    
    {:reply, result, %{state | current: next_index}}
  end
end
```

### Task Processing Pipeline

```elixir
defmodule TaskPipeline do
  def process_code_review(file_path) do
    file_path
    |> read_file()
    |> analyze_complexity()
    |> generate_review()
    |> format_output()
  end
  
  defp read_file(path) do
    content = File.read!(path)
    %{path: path, content: content}
  end
  
  defp analyze_complexity(%{content: content} = data) do
    prompt = """
    Analyze the complexity of this code and identify potential issues:
    
    #{content}
    """
    
    analysis = 
      ClaudeCodeSDK.query(prompt)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    Map.put(data, :complexity_analysis, analysis)
  end
  
  defp generate_review(%{content: content, complexity_analysis: analysis} = data) do
    prompt = """
    Based on this complexity analysis:
    #{analysis}
    
    Generate a detailed code review for:
    #{content}
    
    Include specific suggestions for improvement.
    """
    
    review = 
      ClaudeCodeSDK.query(prompt)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    Map.put(data, :review, review)
  end
  
  defp format_output(%{path: path, review: review}) do
    """
    # Code Review for #{Path.basename(path)}
    
    #{review}
    
    Generated at: #{DateTime.utc_now()}
    """
  end
end
```

## MCP Support

### MCP Configuration

```elixir
defmodule MCPConfig do
  def filesystem_config do
    %{
      "mcpServers" => %{
        "filesystem" => %{
          "command" => "npx",
          "args" => ["-y", "@modelcontextprotocol/server-filesystem", "/allowed/path"]
        }
      }
    }
  end
  
  def github_config(token) do
    %{
      "mcpServers" => %{
        "github" => %{
          "command" => "npx", 
          "args" => ["-y", "@modelcontextprotocol/server-github"],
          "env" => %{
            "GITHUB_TOKEN" => token
          }
        }
      }
    }
  end
  
  def combined_config(github_token) do
    Map.merge(filesystem_config(), github_config(github_token))
  end
  
  def save_config(config, path) do
    Jason.encode!(config) |> then(&File.write!(path, &1))
  end
  
  def create_options_with_mcp(mcp_config_path, allowed_tools) do
    ClaudeCodeSDK.Options.new(
      mcp_config: mcp_config_path,
      allowed_tools: allowed_tools,
      permission_prompt_tool: "mcp__auth__approve"
    )
  end
end

# Usage
config = MCPConfig.combined_config("github_token_here")
MCPConfig.save_config(config, "/tmp/mcp_config.json")

options = MCPConfig.create_options_with_mcp(
  "/tmp/mcp_config.json",
  ["mcp__filesystem__read_file", "mcp__github__search_issues"]
)

ClaudeCodeSDK.query("Search for open issues about performance", options)
```

### MCP Tool Management

```elixir
defmodule MCPToolManager do
  def list_available_tools(mcp_config_path) do
    # This would need to be implemented by querying MCP servers
    # For now, return common patterns
    [
      "mcp__filesystem__read_file",
      "mcp__filesystem__write_file", 
      "mcp__filesystem__list_directory",
      "mcp__github__search_issues",
      "mcp__github__create_issue",
      "mcp__slack__send_message"
    ]
  end
  
  def build_tool_permissions(allowed_patterns) do
    allowed_patterns
    |> Enum.map(&expand_pattern/1)
    |> List.flatten()
    |> Enum.uniq()
  end
  
  defp expand_pattern("mcp__" <> server_name) do
    # Allow all tools from a server
    case server_name do
      "filesystem" -> [
        "mcp__filesystem__read_file",
        "mcp__filesystem__write_file",
        "mcp__filesystem__list_directory"
      ]
      "github" -> [
        "mcp__github__search_issues", 
        "mcp__github__create_issue",
        "mcp__github__get_repo"
      ]
      _ -> []
    end
  end
  defp expand_pattern(exact_tool), do: [exact_tool]
end
```

## Security Considerations

### Input Validation

```elixir
defmodule SecurityValidator do
  @max_prompt_length 50_000
  @dangerous_patterns [
    ~r/rm -rf/i,
    ~r/sudo/i,
    ~r/curl.*\|.*sh/i,
    ~r/eval\(/i
  ]
  
  def validate_prompt(prompt) when is_binary(prompt) do
    cond do
      String.length(prompt) > @max_prompt_length ->
        {:error, :prompt_too_long}
        
      contains_dangerous_pattern?(prompt) ->
        {:error, :dangerous_content}
        
      true ->
        {:ok, prompt}
    end
  end
  def validate_prompt(_), do: {:error, :invalid_type}
  
  defp contains_dangerous_pattern?(prompt) do
    Enum.any?(@dangerous_patterns, &Regex.match?(&1, prompt))
  end
  
  def validate_options(%ClaudeCodeSDK.Options{} = options) do
    with :ok <- validate_working_directory(options.cwd),
         :ok <- validate_tools(options.allowed_tools),
         :ok <- validate_mcp_config(options.mcp_config) do
      {:ok, options}
    end
  end
  
  defp validate_working_directory(nil), do: :ok
  defp validate_working_directory(cwd) when is_binary(cwd) do
    if String.starts_with?(Path.expand(cwd), "/allowed/path") do
      :ok
    else
      {:error, :invalid_working_directory}
    end
  end
  
  defp validate_tools(nil), do: :ok
  defp validate_tools(tools) when is_list(tools) do
    if Enum.all?(tools, &is_binary/1) do
      :ok
    else
      {:error, :invalid_tools}
    end
  end
  
  defp validate_mcp_config(nil), do: :ok
  defp validate_mcp_config(path) when is_binary(path) do
    if File.exists?(path) and Path.extname(path) == ".json" do
      :ok
    else
      {:error, :invalid_mcp_config}
    end
  end
end

# Secure query wrapper
defmodule SecureClaudeSDK do
  def secure_query(prompt, options \\ nil) do
    with {:ok, validated_prompt} <- SecurityValidator.validate_prompt(prompt),
         {:ok, validated_options} <- SecurityValidator.validate_options(options || %ClaudeCodeSDK.Options{}) do
      ClaudeCodeSDK.query(validated_prompt, validated_options)
    else
      error -> Stream.concat([%{type: :error, error: error}])
    end
  end
end
```

### Permission Management

```elixir
defmodule PermissionManager do
  def safe_options_for_environment(env) do
    case env do
      :development ->
        %ClaudeCodeSDK.Options{
          permission_mode: :accept_edits,
          allowed_tools: ["Read", "Write", "Bash"],
          max_turns: 10
        }
        
      :staging ->
        %ClaudeCodeSDK.Options{
          permission_mode: :plan,
          allowed_tools: ["Read"],
          disallowed_tools: ["Bash"],
          max_turns: 5
        }
        
      :production ->
        %ClaudeCodeSDK.Options{
          permission_mode: :plan,
          allowed_tools: ["Read"],
          disallowed_tools: ["Bash", "Write"],
          max_turns: 3
        }
    end
  end
  
  def create_sandboxed_options(sandbox_path) do
    %ClaudeCodeSDK.Options{
      cwd: sandbox_path,
      permission_mode: :bypass_permissions,
      allowed_tools: ["Read", "Write"],
      disallowed_tools: ["Bash"],
      max_turns: 5
    }
  end
end
```

## Troubleshooting

### Common Issues and Solutions

#### Authentication Problems

```elixir
defmodule TroubleshootAuth do
  def diagnose_auth_issue do
    case System.cmd("claude", ["auth", "status"]) do
      {output, 0} ->
        IO.puts("✅ Authentication OK: #{output}")
        
      {error, _code} ->
        IO.puts("❌ Authentication failed: #{error}")
        IO.puts("💡 Solution: Run 'claude login'")
    end
  end
  
  def check_cli_installation do
    case System.find_executable("claude") do
      nil ->
        IO.puts("❌ Claude CLI not found")
        IO.puts("💡 Install with: npm install -g @anthropic-ai/claude-code")
        
      path ->
        IO.puts("✅ Claude CLI found at: #{path}")
        
        case System.cmd("claude", ["--version"]) do
          {version, 0} -> IO.puts("   Version: #{String.trim(version)}")
          {error, _} -> IO.puts("   Error getting version: #{error}")
        end
    end
  end
end
```

#### Process and Stream Issues

```elixir
defmodule TroubleshootProcess do
  def diagnose_hanging_query(prompt) do
    IO.puts("🔍 Diagnosing query: #{inspect(prompt)}")
    
    # Test with timeout
    task = Task.async(fn ->
      ClaudeCodeSDK.query(prompt) |> Enum.take(3)
    end)
    
    case Task.yield(task, 10_000) do
      {:ok, messages} ->
        IO.puts("✅ Query completed with #{length(messages)} messages")
        Enum.each(messages, fn msg ->
          IO.puts("   #{msg.type}: #{inspect(msg.data, limit: :infinity)}")
        end)
        
      nil ->
        IO.puts("❌ Query timed out after 10 seconds")
        Task.shutdown(task, :brutal_kill)
        
        # Additional diagnostics
        IO.puts("💡 Checking process status...")
        System.cmd("ps", ["aux"]) 
        |> elem(0)
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "claude"))
        |> Enum.each(&IO.puts("   #{&1}"))
    end
  end
  
  def test_basic_connectivity do
    IO.puts("🔧 Testing basic Claude connectivity...")
    
    case System.cmd("claude", ["--print", "Say 'test'", "--output-format", "json"], 
                   stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("✅ Basic connectivity OK")
        try do
          Jason.decode!(output)
          IO.puts("✅ JSON parsing OK")
        rescue
          _ -> IO.puts("⚠️  JSON parsing failed, output: #{output}")
        end
        
      {error, code} ->
        IO.puts("❌ Basic connectivity failed (exit #{code}): #{error}")
    end
  end
end
```

### Debug Mode

```elixir
defmodule DebugMode do
  def debug_query(prompt, options \\ nil) do
    IO.puts("🐛 DEBUG MODE ENABLED")
    IO.puts("   Prompt: #{inspect(prompt)}")
    IO.puts("   Options: #{inspect(options)}")
    
    # Add debug options
    debug_options = case options do
      nil -> %ClaudeCodeSDK.Options{verbose: true}
      opts -> %{opts | verbose: true}
    end
    
    IO.puts("   Final options: #{inspect(debug_options)}")
    
    # Time the query
    start_time = System.monotonic_time(:millisecond)
    
    result = 
      ClaudeCodeSDK.query(prompt, debug_options)
      |> Stream.map(fn msg ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        IO.puts("   [#{elapsed}ms] #{msg.type}: #{inspect(msg.data, limit: 1)}")
        msg
      end)
      |> Enum.to_list()
    
    total_time = System.monotonic_time(:millisecond) - start_time
    IO.puts("🏁 Debug completed in #{total_time}ms with #{length(result)} messages")
    
    result
  end
end
```

## Examples & Use Cases

### Code Analysis Pipeline

```elixir
defmodule CodeAnalyzer do
  def analyze_project(project_path) do
    project_path
    |> find_source_files()
    |> Enum.map(&analyze_file/1)
    |> generate_summary_report()
  end
  
  defp find_source_files(path) do
    Path.wildcard("#{path}/**/*.{ex,exs,js,ts,py}")
  end
  
  defp analyze_file(file_path) do
    content = File.read!(file_path)
    
    analysis = 
      ClaudeCodeSDK.query("""
      Analyze this code file for:
      1. Code quality issues
      2. Security vulnerabilities  
      3. Performance concerns
      4. Best practice violations
      
      File: #{Path.basename(file_path)}
      ```
      #{content}
      ```
      
      Provide specific, actionable feedback.
      """)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    %{
      file: file_path,
      analysis: analysis,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp generate_summary_report(analyses) do
    all_issues = Enum.map_join(analyses, "\n\n", fn %{file: file, analysis: analysis} ->
      "## #{Path.basename(file)}\n#{analysis}"
    end)
    
    summary = 
      ClaudeCodeSDK.query("""
      Create a executive summary of these code analysis results:
      
      #{all_issues}
      
      Include:
      - Overall code quality assessment
      - Top 5 critical issues to address
      - Recommended next steps
      """)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    %{
      summary: summary,
      detailed_analyses: analyses,
      generated_at: DateTime.utc_now()
    }
  end
end
```

### Documentation Generator

```elixir
defmodule DocGenerator do
  def generate_api_docs(module_files) do
    module_files
    |> Enum.map(&extract_module_info/1)
    |> Enum.map(&generate_module_docs/1)
    |> combine_into_full_docs()
  end
  
  defp extract_module_info(file_path) do
    content = File.read!(file_path)
    
    # Extract basic info first
    module_info = 
      ClaudeCodeSDK.query("""
      Extract the following information from this Elixir module:
      
      1. Module name and purpose
      2. Public functions with their signatures
      3. Key dependencies and imports
      4. Any existing documentation
      
      Module file:
      ```elixir
      #{content}
      ```
      
      Format as structured data.
      """)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    %{
      file: file_path,
      content: content,
      extracted_info: module_info
    }
  end
  
  defp generate_module_docs(%{content: content, extracted_info: info} = module_data) do
    docs = 
      ClaudeCodeSDK.query("""
      Generate comprehensive documentation for this Elixir module:
      
      Extracted information:
      #{info}
      
      Full module code:
      ```elixir
      #{content}
      ```
      
      Generate:
      1. Module overview and purpose
      2. Installation/usage instructions  
      3. Function documentation with examples
      4. Common use cases
      5. Error handling patterns
      
      Use proper Markdown formatting.
      """)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    Map.put(module_data, :documentation, docs)
  end
  
  defp combine_into_full_docs(module_docs) do
    combined_content = 
      module_docs
      |> Enum.map(& &1.documentation)
      |> Enum.join("\n\n---\n\n")
    
    full_docs = 
      ClaudeCodeSDK.query("""
      Create a comprehensive API documentation index from these individual module docs:
      
      #{combined_content}
      
      Generate:
      1. Table of contents
      2. Quick start guide
      3. Module cross-references
      4. Common patterns and examples
      """)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    %{
      index: full_docs,
      modules: module_docs,
      generated_at: DateTime.utc_now()
    }
  end
end
```

### Test Generator

```elixir
defmodule TestGenerator do
  def generate_tests_for_module(module_file) do
    content = File.read!(module_file)
    
    # Generate comprehensive test suite
    test_content = 
      ClaudeCodeSDK.query("""
      Generate a comprehensive ExUnit test suite for this Elixir module:
      
      ```elixir
      #{content}
      ```
      
      Include:
      1. Setup and teardown functions
      2. Tests for all public functions
      3. Edge case testing
      4. Error condition testing  
      5. Property-based test suggestions
      6. Mock/stub patterns where needed
      
      Follow ExUnit best practices and naming conventions.
      """, %ClaudeCodeSDK.Options{max_turns: 5})
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    # Clean up and format the test code
    clean_tests = 
      ClaudeCodeSDK.query("""
      Clean up and optimize this test code:
      
      #{test_content}
      
      Ensure:
      1. Proper indentation and formatting
      2. No duplicate test cases
      3. Clear test descriptions
      4. Efficient test structure
      """)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    # Generate test file
    module_name = extract_module_name(content)
    test_file_path = "test/#{Macro.underscore(module_name)}_test.exs"
    
    %{
      test_content: clean_tests,
      test_file_path: test_file_path,
      original_module: module_file
    }
  end
  
  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([A-Z][A-Za-z0-9_.]*)/m, content) do
      [_, module_name] -> module_name
      _ -> "UnknownModule"
    end
  end
  
  def run_generated_tests(test_info) do
    # Write test file
    File.write!(test_info.test_file_path, test_info.test_content)
    
    # Run tests and capture output
    case System.cmd("mix", ["test", test_info.test_file_path]) do
      {output, 0} ->
        {:ok, output}
      {output, code} ->
        # Try to fix failing tests
        fix_tests(test_info, output)
    end
  end
  
  defp fix_tests(test_info, error_output) do
    fixed_content = 
      ClaudeCodeSDK.query("""
      Fix the failing tests based on this error output:
      
      Error output:
      #{error_output}
      
      Original test file:
      #{test_info.test_content}
      
      Provide the corrected test file content.
      """)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    # Write fixed tests and try again
    File.write!(test_info.test_file_path, fixed_content)
    System.cmd("mix", ["test", test_info.test_file_path])
  end
end
```

### Interactive Development Assistant

```elixir
defmodule DevAssistant do
  use GenServer
  
  # Client API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def ask(question) do
    GenServer.call(__MODULE__, {:ask, question})
  end
  
  def start_pair_programming_session(file_path) do
    GenServer.call(__MODULE__, {:start_session, file_path})
  end
  
  def continue_session(input) do
    GenServer.call(__MODULE__, {:continue, input})
  end
  
  # Server implementation
  def init(_) do
    {:ok, %{current_session: nil, context: %{}}}
  end
  
  def handle_call({:ask, question}, _from, state) do
    response = 
      ClaudeCodeSDK.query(question)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    {:reply, response, state}
  end
  
  def handle_call({:start_session, file_path}, _from, state) do
    content = File.read!(file_path)
    
    initial_prompt = """
    I'm starting a pair programming session on this file: #{file_path}
    
    ```
    #{content}
    ```
    
    Please analyze the code and suggest what we should work on together.
    """
    
    session_stream = ClaudeCodeSDK.query(initial_prompt)
    session_id = extract_session_id(session_stream)
    
    response = 
      session_stream
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    new_state = %{
      state | 
      current_session: session_id,
      context: %{file_path: file_path, content: content}
    }
    
    {:reply, response, new_state}
  end
  
  def handle_call({:continue, input}, _from, %{current_session: nil} = state) do
    {:reply, "No active session. Start with start_pair_programming_session/1", state}
  end
  
  def handle_call({:continue, input}, _from, %{current_session: session_id} = state) do
    response = 
      ClaudeCodeSDK.resume(session_id, input)
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.join("\n")
    
    {:reply, response, state}
  end
  
  defp extract_session_id(stream) do
    stream
    |> Enum.find(&(&1.type == :system))
    |> case do
      %{data: %{session_id: id}} -> id
      _ -> nil
    end
  end
end

# Usage example
# DevAssistant.start_link([])
# DevAssistant.ask("How do I optimize this Elixir function for performance?")
# DevAssistant.start_pair_programming_session("lib/my_module.ex") 
# DevAssistant.continue_session("Let's add better error handling")
```

### Automated Refactoring Tool

```elixir
defmodule RefactoringTool do
  def refactor_codebase(project_path, refactoring_goals) do
    project_path
    |> scan_codebase()
    |> analyze_refactoring_opportunities(refactoring_goals)
    |> plan_refactoring_steps()
    |> execute_refactoring()
    |> validate_refactoring()
  end
  
  defp scan_codebase(project_path) do
    elixir_files = Path.wildcard("#{project_path}/**/*.{ex,exs}")
    
    file_analyses = 
      elixir_files
      |> Enum.map(fn file ->
        content = File.read!(file)
        
        analysis = 
          ClaudeCodeSDK.query("""
          Analyze this Elixir file for refactoring opportunities:
          
          File: #{file}
          ```elixir
          #{content}
          ```
          
          Identify:
          1. Code smells
          2. Duplication patterns
          3. Complexity issues
          4. Naming improvements
          5. Structure optimization opportunities
          """)
          |> extract_assistant_content()
        
        %{file: file, content: content, analysis: analysis}
      end)
    
    %{project_path: project_path, files: file_analyses}
  end
  
  defp analyze_refactoring_opportunities(%{files: files}, goals) do
    combined_analysis = 
      files
      |> Enum.map(& &1.analysis)
      |> Enum.join("\n\n---\n\n")
    
    prioritized_opportunities = 
      ClaudeCodeSDK.query("""
      Based on these file analyses and refactoring goals:
      
      Goals: #{Enum.join(goals, ", ")}
      
      Analyses:
      #{combined_analysis}
      
      Create a prioritized list of refactoring opportunities that address the goals.
      Include impact assessment and effort estimation for each.
      """)
      |> extract_assistant_content()
    
    %{files: files, opportunities: prioritized_opportunities}
  end
  
  defp plan_refactoring_steps(%{opportunities: opportunities} = data) do
    refactoring_plan = 
      ClaudeCodeSDK.query("""
      Create a detailed refactoring execution plan:
      
      Opportunities:
      #{opportunities}
      
      Generate:
      1. Step-by-step refactoring sequence
      2. Dependencies between steps
      3. Risk assessment for each step
      4. Rollback strategies
      5. Testing requirements
      """)
      |> extract_assistant_content()
    
    Map.put(data, :plan, refactoring_plan)
  end
  
  defp execute_refactoring(%{files: files, plan: plan} = data) do
    IO.puts("🔧 Executing refactoring plan...")
    
    # This would implement actual refactoring
    # For now, we'll generate the refactored code
    refactored_files = 
      files
      |> Enum.map(fn %{file: file, content: content} ->
        refactored_content = 
          ClaudeCodeSDK.query("""
          Refactor this Elixir file according to the plan:
          
          Plan:
          #{plan}
          
          Original file (#{file}):
          ```elixir
          #{content}
          ```
          
          Provide the refactored code with explanations of changes made.
          """)
          |> extract_assistant_content()
        
        %{file: file, original: content, refactored: refactored_content}
      end)
    
    Map.put(data, :refactored_files, refactored_files)
  end
  
  defp validate_refactoring(%{refactored_files: refactored_files} = data) do
    validation_report = 
      ClaudeCodeSDK.query("""
      Validate this refactoring by comparing original and refactored code:
      
      #{Enum.map_join(refactored_files, "\n\n", fn %{file: file, original: orig, refactored: ref} ->
        "File: #{file}\nOriginal:\n#{orig}\n\nRefactored:\n#{ref}"
      end)}
      
      Check:
      1. Functionality preservation
      2. Code quality improvements
      3. Potential issues introduced
      4. Test coverage impact
      """)
      |> extract_assistant_content()
    
    Map.put(data, :validation: validation_report)
  end
  
  defp extract_assistant_content(stream) do
    stream
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.join("\n")
  end
end
```

This comprehensive manual covers all aspects of the Claude Code SDK for Elixir, from basic usage to advanced integration patterns. It provides practical examples for real-world use cases while maintaining security and performance best practices.