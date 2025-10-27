# Elixir Claude Agent SDK - Comprehensive Feature Overview

**Version:** 0.6.0  
**Status:** Production-ready with continuous development  
**Repository:** https://github.com/nshkrdotcom/claude_agent_sdk

---

## Table of Contents
1. [Core Features & Capabilities](#core-features--capabilities)
2. [Main Modules & Architecture](#main-modules--architecture)
3. [Configuration & Options](#configuration--options)
4. [Hook System (v0.3.0+)](#hook-system-v030)
5. [MCP Integration](#mcp-integration)
6. [Tool Permission System (v0.4.0+)](#tool-permission-system-v040)
7. [Error Handling](#error-handling)
8. [Advanced Features](#advanced-features)
9. [Version History](#version-history)

---

## Core Features & Capabilities

### 1. **Query Interface** (Basic)
- **Function:** `ClaudeAgentSDK.query(prompt, options)`
- **Returns:** Stream of Message structs
- **Features:**
  - Simple text-based prompting
  - Optional configuration via Options struct
  - Returns lazy stream (memory efficient)
  - Non-blocking with streaming support

### 2. **Bidirectional Streaming** (v0.2.1+)
- **Module:** `ClaudeAgentSDK.Streaming`
- **Functions:**
  - `start_session(options)` - Start persistent session
  - `send_message(session, text)` - Send message
  - `close_session(session)` - Clean up
  - `get_session_id(session)` - Get session identifier
- **Features:**
  - Real-time character-by-character text streaming (typewriter effect)
  - Persistent session across multiple messages
  - Context preservation across turns
  - Partial message support via `--include-partial-messages`
  - Returns stream of events (text_delta, message_stop, tool_use_start, etc.)
  - Phoenix LiveView ready

### 3. **Session Management** (v0.2.0+)
- **Module:** `ClaudeAgentSDK.SessionStore`
- **Functions:**
  - `save_session(session_id, messages, opts)` - Persist session
  - `load_session(session_id)` - Retrieve saved session
  - `search(filters)` - Query by tags, date range, cost
  - Auto-cleanup of old sessions (configurable age)
- **Features:**
  - Session metadata tracking (created_at, cost, turn count)
  - Tag-based organization
  - Description/notes support
  - Multi-format export/import
  - Stored in `~/.claude_sdk/sessions/` by default

### 4. **Session Operations**
- **Functions:**
  - `ClaudeAgentSDK.continue(prompt, options)` - Continue last conversation
  - `ClaudeAgentSDK.resume(session_id, prompt, options)` - Resume specific session
  - `fork_session` option - Create branch from existing session
  - Session ID tracking and correlation

### 5. **Concurrent Query Orchestration** (Orchestrator module)
- **Functions:**
  - `query_parallel(queries, opts)` - Run queries concurrently (3-5x faster)
  - `query_pipeline(queries, opts)` - Sequential workflows with context passing
  - `query_with_retry(prompt, options, opts)` - Auto-retry with exponential backoff
- **Features:**
  - Configurable max concurrency
  - Timeout per query
  - Cost tracking and statistics
  - Error aggregation
  - Rate limiting support

### 6. **Model Selection & Fallback** (v0.1.0+)
- **Supported Models:**
  - `"opus"` - Claude Opus 4.1 (full name: claude-opus-4-1-20250805)
  - `"sonnet"` - Claude Sonnet 4.5 (full name: claude-sonnet-4-5-20250929)
  - `"haiku"` - Claude Haiku 4.5 (full name: claude-haiku-4-5-20251001) [default]
  - `"sonnet[1m]"` - Sonnet 4.5 with 1M context
  - Full model IDs also accepted
- **Features:**
  - Model validation and normalization
  - Fallback model support
  - Runtime model switching via `Client.set_model(pid, model)`
  - Model suggestions on invalid input

### 7. **Custom Agents** (v0.1.0+)
- **Module:** `ClaudeAgentSDK.Agent`
- **Features:**
  - Define specialized agent personalities
  - Custom system prompts per agent
  - Agent-specific tool restrictions
  - Agent-specific model selection
  - Runtime agent switching via `Client.set_agent(pid, agent_name)`
  - Query available agents via `Client.get_available_agents(pid)`
- **Configuration:**
  ```elixir
  agents = %{
    researcher: Agent.new(
      description: "Research specialist",
      prompt: "You are an expert researcher...",
      allowed_tools: ["Read", "Grep"],
      model: "opus"
    ),
    coder: Agent.new(
      description: "Code expert",
      prompt: "You excel at coding...",
      allowed_tools: ["Bash", "Write", "Edit"]
    )
  }
  ```

### 8. **Client GenServer** (Bidirectional Control)
- **Module:** `ClaudeAgentSDK.Client`
- **Features:**
  - Persistent connection to Claude CLI
  - Hook callback invocation
  - Control protocol request/response handling
  - Message queueing and delivery
  - Runtime configuration changes
  - Streaming with control features
- **Functions:**
  - `start_link(options)` - Start client
  - `send_message(pid, message)` - Send message
  - `stream_messages(pid)` - Get message stream
  - `set_model(pid, model)` - Switch model at runtime
  - `set_permission_mode(pid, mode)` - Change permission handling
  - `set_agent(pid, agent_name)` - Switch agent at runtime
  - `stop(pid)` - Graceful shutdown

---

## Main Modules & Architecture

### Core Modules

| Module | Purpose | Key Functions |
|--------|---------|----------------|
| `ClaudeAgentSDK` | Main entry point | `query/2`, `continue/2`, `resume/3`, `create_sdk_mcp_server/1` |
| `ClaudeAgentSDK.Client` | Bidirectional streaming | `start_link/2`, `send_message/2`, `stream_messages/1` |
| `ClaudeAgentSDK.Streaming` | Simple streaming API | `start_session/1`, `send_message/2`, `close_session/1` |
| `ClaudeAgentSDK.Query` | Query routing | `run/2`, `continue/2`, `resume/3` |
| `ClaudeAgentSDK.Process` | Subprocess execution | `stream/3` using erlexec |
| `ClaudeAgentSDK.Message` | Message parsing | `from_json/1` with custom parser |
| `ClaudeAgentSDK.Options` | Configuration struct | All option definitions |
| `ClaudeAgentSDK.Orchestrator` | Concurrent execution | `query_parallel/2`, `query_pipeline/2`, `query_with_retry/3` |
| `ClaudeAgentSDK.SessionStore` | Session persistence | `save_session/3`, `load_session/1`, `search/1` |

### Specialized Modules

| Module | Purpose |
|--------|---------|
| `ClaudeAgentSDK.Tool` | Tool definition macro for SDK MCP |
| `ClaudeAgentSDK.Tool.Registry` | In-process tool registry |
| `ClaudeAgentSDK.Agent` | Agent definition |
| `ClaudeAgentSDK.Model` | Model validation/normalization |
| `ClaudeAgentSDK.AuthManager` | Authentication token management |
| `ClaudeAgentSDK.DebugMode` | Query debugging and diagnostics |
| `ClaudeAgentSDK.ContentExtractor` | Text extraction from messages |
| `ClaudeAgentSDK.Hooks.*` | Hook system modules |
| `ClaudeAgentSDK.Permission.*` | Permission system modules |
| `ClaudeAgentSDK.Streaming.*` | Streaming implementation |

---

## Configuration & Options

### Options Struct (`ClaudeAgentSDK.Options`)

#### Query Control
- `max_turns` - Max conversation turns (integer)
- `system_prompt` - Custom system prompt (string)
- `append_system_prompt` - Additional system prompt (string)

#### Tool Configuration
- `allowed_tools` - List of allowed tool names
- `disallowed_tools` - List of disallowed tool names
- `mcp_servers` - Map of MCP servers (SDK and external)
- `mcp_config` - Path to MCP config file (backward compat)
- `permission_prompt_tool` - Tool for permission prompts

#### Model & Agent Control
- `model` - Model selection (opus, sonnet, haiku, or full ID)
- `fallback_model` - Fallback when primary overloaded
- `agents` - Map of custom agent definitions
- `agent` - Active agent (atom key)

#### Permission System
- `permission_mode` - `:default | :accept_edits | :plan | :bypass_permissions`
- `can_use_tool` - Permission callback function

#### Execution Control
- `cwd` - Working directory
- `executable` - Custom executable
- `executable_args` - Arguments for custom executable
- `timeout_ms` - Execution timeout (default: 4,500,000ms = 75 minutes)
- `verbose` - Enable verbose output

#### Session Management
- `session_id` - Explicit session ID (UUID)
- `fork_session` - Create new session when resuming
- `add_dir` - Additional directories for tool access
- `strict_mcp_config` - Only use MCP servers from config

#### Streaming + Tools (v0.6.0)
- `include_partial_messages` - Enable character-level streaming
- `preferred_transport` - `:auto | :cli | :control`
  - `:auto` - Intelligent selection (default)
  - `:cli` - Force CLI-only (fast, no control features)
  - `:control` - Force control client (full features)

#### Hooks & Callbacks
- `hooks` - Hook configuration map

### Output Format Options
- `:text` - Plain text output
- `:json` - JSON output
- `:stream_json` - JSON stream (default for streaming)

---

## Hook System (v0.3.0+)

### Overview
Hooks enable intercepting Claude's execution at specific lifecycle events. Fully implemented and production-ready.

### Supported Hook Events
1. **`:pre_tool_use`** - Before tool execution
   - Control: Allow/deny tool use
   - Can modify input
   - Security policy enforcement

2. **`:post_tool_use`** - After tool execution
   - Add context for Claude
   - Tool result augmentation
   - Logging/auditing

3. **`:user_prompt_submit`** - When user submits prompt
   - Inject contextual information
   - Prompt augmentation
   - Pre-processing

4. **`:stop`** - When agent finishes
   - Cleanup operations
   - Logging

5. **`:subagent_stop`** - When subagent finishes
   - Subagent cleanup

6. **`:pre_compact`** - Before context compaction
   - Context preservation decisions

### Hook Configuration
```elixir
hooks = %{
  pre_tool_use: [
    Matcher.new("Bash", [&check_bash_safety/3]),
    Matcher.new("Write|Edit", [&check_file_access/3]),
    Matcher.new("*", [&log_all_tools/3])
  ],
  post_tool_use: [
    Matcher.new("Bash", [&log_bash_output/3])
  ]
}

options = %Options{hooks: hooks}
```

### Hook Callback Signature
```elixir
def my_hook(input, tool_use_id, context) do
  # input: Hook input map (tool_name, tool_input, etc.)
  # tool_use_id: Unique ID for this tool use
  # context: Contextual information (empty map or with signal)
  
  Output.allow()  # or Output.deny(...), Output.add_context(...), etc.
end
```

### Hook Matcher
- Regex pattern matching on tool names
- `"Bash"` - Match exact tool
- `"Bash|Python"` - Match multiple
- `"*"` - Match all tools
- Multiple callbacks per matcher

### Hook Output Helper
- `Output.allow(reason)` - Allow tool execution
- `Output.deny(reason)` - Deny tool execution
- `Output.ask()` - Ask user for permission
- `Output.add_context(event, context)` - Add context
- `Output.stop(reason)` - Stop execution
- `Output.with_system_message(msg)` - User message
- `Output.with_reason(reason)` - Claude-visible feedback

### Hook Matchers Module
- `Matcher.new(pattern, [callbacks])` - Create matcher
- Supports multiple callbacks per pattern
- Regex pattern matching on tool names

---

## MCP Integration

### Two Types of MCP Servers

#### 1. **SDK MCP Servers** (In-process, v0.5.0+)
- Tools run directly in Elixir process
- No subprocess overhead
- Perfect for Elixir-native tools

**Definition:**
```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool
  
  deftool :calculate, "Math operation", %{
    type: "object",
    properties: %{
      expression: %{type: "string"}
    }
  } do
    def execute(%{"expression" => expr}) do
      result = eval(expr)
      {:ok, %{"content" => [%{"type" => "text", "text" => "Result: #{result}"}]}}
    end
  end
end
```

**Creation:**
```elixir
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [MyTools.Calculate]
)

options = %Options{
  mcp_servers: %{"calc" => server}
}
```

#### 2. **External MCP Servers** (Subprocess-based)
- Run external MCP servers
- Support for stdio, SSE, HTTP transports

**Configuration:**
```elixir
mcp_servers = %{
  "filesystem" => %{
    type: :stdio,
    command: "path/to/server",
    args: ["arg1", "arg2"]
  }
}
```

### MCP Features
- Tool listing and execution
- JSONRPC 2.0 protocol
- Control protocol integration
- Tool result streaming
- Automatic transport selection for streaming + MCP

---

## Tool Permission System (v0.4.0+)

### Overview
Programmatic control over tool execution permissions with runtime switching.

### Permission Modes
1. **`:default`** - All tools go through permission callback
2. **`:accept_edits`** - Edit tools (Write, Edit, MultiEdit) auto-allowed
3. **`:plan`** - Claude creates plan, shows to user, user approves
4. **`:bypass_permissions`** - All tools auto-allowed

### Permission Callback
```elixir
def permission_callback(context) do
  case context.tool_name do
    "Bash" ->
      if dangerous_command?(context.tool_input["command"]) do
        Result.deny("Dangerous command detected")
      else
        Result.allow()
      end
    
    "Write" ->
      # Redirect sensitive file writes
      if String.starts_with?(context.tool_input["file_path"], "/etc/") do
        safe_path = "/tmp/" <> Path.basename(context.tool_input["file_path"])
        Result.allow(updated_input: %{context.tool_input | "file_path" => safe_path})
      else
        Result.allow()
      end
    
    _ ->
      Result.allow()
  end
end

options = %Options{
  can_use_tool: &permission_callback/1,
  permission_mode: :default
}
```

### Runtime Mode Switching
```elixir
{:ok, client} = Client.start_link(options)

# Switch modes at runtime
:ok = Client.set_permission_mode(client, :plan)
:ok = Client.set_permission_mode(client, :accept_edits)
:ok = Client.set_permission_mode(client, :bypass_permissions)
```

### Permission Context
- `tool_name` - Name of tool being used
- `tool_input` - Input arguments to tool
- `session_id` - Current session ID
- `suggestions` - CLI permission suggestions

### Permission Result
- `allow()` - Allow tool execution
- `deny(reason)` - Deny with reason
- `allow(updated_input: new_input)` - Allow with modified input
- Validation and error handling

---

## Error Handling

### Error Types & Handling

#### Message Errors
```elixir
messages = ClaudeAgentSDK.query("prompt", options) |> Enum.to_list()

# Check for errors
error_msg = Enum.find(messages, &(&1.type == :result and &1.subtype != :success))

case error_msg do
  %{subtype: :error_max_turns} -> "Max turns exceeded"
  %{subtype: :error_during_execution} -> "Execution error"
  %{data: %{error: reason}} -> "Error: #{reason}"
  nil -> "Success"
end
```

#### Message Types
- `:system` (subtype: `:init`) - Session initialization
- `:user` - User input echo
- `:assistant` - Claude response
- `:result` (subtypes):
  - `:success` - Successful completion
  - `:error_max_turns` - Max turn limit exceeded
  - `:error_during_execution` - Error during execution

#### Result Data Fields
- `total_cost_usd` - API cost
- `duration_ms` - Total duration
- `num_turns` - Number of turns
- `session_id` - Session identifier
- `error` - Error message (if error)
- `is_error` - Boolean flag

### Timeout & Limits
- Default timeout: 4,500,000ms (75 minutes)
- Configurable per-query in Options
- Hook callback timeout: 60 seconds
- Permission callback timeout: 60 seconds

### Debugging
- **Module:** `ClaudeAgentSDK.DebugMode`
- **Functions:**
  - `debug_query(prompt, options)` - Detailed execution logging
  - `run_diagnostics()` - Full environment check
  - `benchmark(prompt, options, runs)` - Performance analysis
  - `analyze_messages(messages)` - Message statistics

### Error Recovery
- Automatic retry with exponential backoff via Orchestrator
- Graceful shutdown with proper resource cleanup
- EPIPE error prevention during cleanup
- Port/transport cleanup on termination

---

## Advanced Features

### 1. **Streaming + Tools Unification** (v0.6.0)
- **Problem Solved:** Previously had to choose between fast streaming (CLI-only) OR control features (Client)
- **Solution:** Smart transport routing
  - Detects if hooks, MCP, permissions, or agents configured
  - Routes to CLI-only if no features → Fast streaming
  - Routes to Control Client if features present → Full streaming with control
- **Configuration:**
  - `:preferred_transport` option to override automatic selection
  - `:cli` - Force CLI-only (ignores hooks/MCP/permissions)
  - `:control` - Force control client (even without features)
  - `:auto` - Default, intelligent selection

### 2. **StreamingRouter**
- **Module:** `ClaudeAgentSDK.Transport.StreamingRouter`
- Analyzes Options to determine transport
- Transparent to user code
- Enables polymorphic API (same code works with both transports)

### 3. **Authentication System** (v0.2.0+)
- **Module:** `ClaudeAgentSDK.AuthManager`
- **Providers:**
  - Anthropic (ANTHROPIC_API_KEY)
  - AWS Bedrock
  - GCP Vertex
- **Features:**
  - Automatic token setup via `mix claude.setup_token`
  - Token persistence in `~/.claude_sdk/`
  - Token expiry detection (1 year validity)
  - Auto-refresh 1 day before expiry
  - Environment variable fallback
- **Usage:**
  ```elixir
  {:ok, token} = ClaudeAgentSDK.AuthManager.setup_token()
  # Subsequent queries use stored token
  ```

### 4. **Mock System** (Testing)
- **Module:** `ClaudeAgentSDK.Mock`
- **Usage:**
  ```elixir
  {:ok, _} = ClaudeAgentSDK.Mock.start_link()
  # All queries return mock responses
  ```
- **Environment Variable:** `LIVE_MODE=true` overrides MIX_ENV=test
- **Mix Commands:**
  - `mix showcase` - Run with mocks (no API costs)
  - `mix showcase --live` - Run with real API

### 5. **Content Extraction**
- **Module:** `ClaudeAgentSDK.ContentExtractor`
- **Functions:**
  - `extract_text(message)` - Extract text from message
  - `has_text?(message)` - Check if message has text
  - Handles various content formats (simple, blocks, tool responses)

### 6. **Option Builder**
- **Module:** `ClaudeAgentSDK.OptionBuilder`
- Convenience functions:
  - `with_haiku()` - Haiku model preset
  - `with_opus()` - Opus model preset
  - `with_sonnet()` - Sonnet model preset
  - `with_verbose()` - Enable verbose logging
  - `with_max_turns(n)` - Set max turns

### 7. **Live Script Runner**
- **Command:** `mix run.live examples/file.exs`
- Automatically enables real API calls (ignores mock mode)
- Perfect for development and demos
- Uses `LIVE_MODE=true` environment variable

### 8. **Control Protocol**
- **Module:** `ClaudeAgentSDK.ControlProtocol.Protocol`
- Bidirectional communication with Claude CLI
- Handles:
  - Hook callback requests
  - Permission requests
  - Model change requests
  - Agent switching
  - MCP requests
- Request/response serialization
- Timeout handling

### 9. **Multi-Turn Conversation Context**
- Session preservation across messages
- Message history tracking
- Context-aware continuations
- Session forking for experimentation

### 10. **Transport Abstraction**
- **Default:** Port-based (erlexec)
- **Pluggable:** Transport interface for custom implementations
- **Streaming Router:** Routes between transports transparently

---

## Version History

### v0.6.0 (Latest)
- ✅ **Streaming + Tools Unification**: Automatic transport selection
- ✅ **StreamingRouter**: Intelligent routing between CLI and control client
- ✅ **Partial Messages**: Character-level streaming support
- ✅ **Tool Events**: :tool_use_start, :tool_input_delta in streaming

### v0.5.0
- ✅ SDK MCP Server support
- ✅ In-process tool execution
- ✅ Tool registry and discovery

### v0.4.0
- ✅ Permission System
- ✅ Permission modes (default, accept_edits, plan, bypass)
- ✅ Permission callbacks
- ✅ Runtime mode switching

### v0.3.0
- ✅ Hook System (6 event types)
- ✅ Hook matchers with regex patterns
- ✅ Hook output helpers
- ✅ Hook callback registry

### v0.2.1
- ✅ Bidirectional Streaming
- ✅ Persistent Sessions
- ✅ Typewriter effect support
- ✅ Multi-turn conversations

### v0.2.0
- ✅ Session Persistence (SessionStore)
- ✅ Session metadata tracking
- ✅ Session search by tags/date/cost
- ✅ Advanced session flags (fork, add_dir, strict_mcp_config)

### v0.1.0
- ✅ Core API (query, continue, resume)
- ✅ Model Selection (opus, sonnet, haiku)
- ✅ Custom Agents
- ✅ Concurrent Orchestrator
- ✅ Basic Error Handling

### v0.0.x
- ✅ Initial SDK with basic querying

---

## Testing & Examples

### Example Categories
1. **Basic Examples**
   - `basic_example.exs` - Simple query
   - `simple_analyzer.exs` - Code analysis
   - `factorial_example.exs` - Simple calculation

2. **Advanced Features**
   - `custom_agents_example.exs` - Agent definitions
   - `model_selection_example.exs` - Model switching
   - `session_features_example.exs` - Session persistence

3. **Streaming Examples**
   - `streaming_tools/basic_streaming_with_hooks.exs` - Streaming with hooks
   - `streaming_tools/sdk_mcp_streaming.exs` - SDK MCP with streaming
   - `streaming_tools/liveview_pattern.exs` - Phoenix integration

4. **Hook Examples**
   - `hooks/basic_bash_blocking.exs` - Simple security
   - `hooks/file_policy_enforcement.exs` - File access control
   - `hooks/context_injection.exs` - Context augmentation
   - `hooks/logging_and_audit.exs` - Audit logging

5. **Advanced Control**
   - `runtime_control/model_switcher.exs` - Runtime model changes
   - `runtime_control/agent_switching.exs` - Runtime agent changes
   - `runtime_control/subscriber_broadcast.exs` - Multi-subscriber patterns

6. **Orchestration**
   - `simple_batch.exs` - Batch processing
   - `week_1_2_showcase.exs` - Feature showcase

### Testing Framework
- **Supertester** - For structured testing
- **ETS Caching** - For session store tests
- **Mock System** - For offline testing
- **LIVE_MODE** - For live API testing

---

## Dependency Stack

### Core Dependencies
- **erlexec** (~2.0) - Subprocess management
- **jason** (~1.4) - JSON handling
- **ex_doc** (~0.31) - Documentation

### Development Dependencies
- **dialyxir** (~1.0) - Type checking
- **credo** (~1.6) - Code quality
- **supertester** (~0.2.1) - Testing

---

## Key Design Patterns

### 1. **Stream-Based API**
All functions return lazy Streams for memory efficiency and composability.

### 2. **GenServer for State Management**
- Client for bidirectional communication
- SessionStore for persistence
- Streaming.Session for streaming

### 3. **Options Pattern**
Centralized configuration in Options struct with sensible defaults.

### 4. **Hook Registry**
Callbacks registered at startup, looked up during execution via unique IDs.

### 5. **Transport Abstraction**
Pluggable transport layer enables multiple backend implementations.

### 6. **Message Parsing Pipeline**
Custom JSON parser + structured Message struct + ContentExtractor utility.

### 7. **Graceful Shutdown**
Port cleanup with proper EPIPE handling and timeout support.

---

## Comparison with Python SDK

The Elixir SDK achieves feature parity with Python SDK and includes:
- ✅ All query modes (query, continue, resume)
- ✅ Streaming with tools
- ✅ Hook system (6 events)
- ✅ Permission system (4 modes)
- ✅ MCP integration (SDK + external)
- ✅ Custom agents
- ✅ Model selection & fallback
- ✅ Session persistence
- ✅ Concurrent orchestration
- ✅ Authentication management
- ✅ Comprehensive error handling
- ✅ Content extraction utilities
- ✅ Debug diagnostics

**Unique to Elixir SDK:**
- Bidirectional streaming (persistent sessions)
- Streaming + Tools unification (v0.6.0)
- SDK MCP servers (in-process tools)
- Hook matchers with regex
- Runtime capability switching
- Concurrent orchestrator with pipelines

