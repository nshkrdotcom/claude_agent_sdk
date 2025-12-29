# Claude Agent SDK - Elixir Implementation Documentation

> Comprehensive research documentation for the Claude Agent SDK Elixir implementation.
> Generated: 2024-12-29

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Main Module: ClaudeAgentSDK](#main-module-claudeagentsdk)
4. [Configuration: Options](#configuration-options)
5. [Query System](#query-system)
6. [Streaming Mechanisms](#streaming-mechanisms)
7. [Transport Layer](#transport-layer)
8. [MCP (Model Context Protocol) Support](#mcp-model-context-protocol-support)
9. [Tool Handling](#tool-handling)
10. [Hooks System](#hooks-system)
11. [Permission System](#permission-system)
12. [Session Management](#session-management)
13. [Message Types](#message-types)
14. [Error Handling](#error-handling)
15. [Authentication](#authentication)
16. [CLI Integration](#cli-integration)
17. [Helper Modules](#helper-modules)

---

## Overview

The Claude Agent SDK for Elixir provides a comprehensive, production-ready interface for interacting with Claude Code programmatically. It wraps the Claude CLI, providing:

- **Streaming queries** with real-time character-by-character updates
- **Session management** for multi-turn conversations
- **MCP server support** (both SDK-based in-process and external subprocess)
- **Hooks system** for lifecycle event interception
- **Permission system** for fine-grained tool access control
- **Pre-built option presets** for different environments and use cases

### Key Design Principles

1. **OTP-Friendly**: Uses GenServers, supervision trees, and standard Elixir patterns
2. **Stream-Based**: All queries return lazy streams for memory efficiency
3. **CLI Parity**: Maintains feature parity with Python SDK where possible
4. **Transport Agnostic**: Supports multiple transport mechanisms (CLI-only, control protocol)

---

## Architecture

```
                                 ClaudeAgentSDK (Main API)
                                         |
                    +--------------------+--------------------+
                    |                    |                    |
                Query.run()        Streaming.start_session()  create_sdk_mcp_server()
                    |                    |                    |
          +---------+---------+          |                    |
          |                   |          |                    |
     Process.stream()    ClientStream   Session           Tool.Registry
     (CLI-only)          (Control)    (GenServer)        (GenServer)
          |                   |          |
          +-------------------+----------+
                    |
              Transport Layer
         (CLI subprocess via erlexec)
```

### Module Dependency Graph

```
ClaudeAgentSDK (Main)
    |-- Options (Configuration)
    |-- Query (Query orchestration)
    |   |-- Process (CLI streaming)
    |   |-- ClientStream (Control protocol streaming)
    |   `-- StreamingRouter (Transport selection)
    |-- Streaming (Bidirectional streaming)
    |   |-- Session (GenServer for persistent sessions)
    |   `-- EventParser (Stream event parsing)
    |-- Client (Control protocol client)
    |-- Tool (Tool definition macro)
    |   `-- Registry (Tool registration GenServer)
    |-- Hooks (Lifecycle hooks)
    |   |-- Matcher (Hook pattern matching)
    |   |-- Output (Hook response builders)
    |   `-- Registry (Hook registration)
    |-- Permission (Permission system)
    |   |-- Context (Permission context struct)
    |   `-- Result (Permission result struct)
    |-- Message (Message parsing)
    |-- Session (Session utilities)
    |-- SessionStore (Persistent session storage)
    |-- CLI (CLI discovery and version checking)
    |-- AuthManager (Token management GenServer)
    |-- AuthChecker (Authentication validation)
    `-- Errors (Structured error types)
```

---

## Main Module: ClaudeAgentSDK

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk.ex`

The main entry point module providing the public API for all SDK operations.

### Public API Functions

#### `query/2`
```elixir
@spec query(String.t(), Options.t() | nil) :: Enumerable.t(ClaudeAgentSDK.Message.t())
```

Runs a query against Claude Code and returns a stream of messages.

**Parameters:**
- `prompt` - The prompt to send to Claude
- `options` - Optional `ClaudeAgentSDK.Options` struct

**Returns:** Stream of `ClaudeAgentSDK.Message` structs

**Example:**
```elixir
# Simple query
ClaudeAgentSDK.query("Write a Fibonacci function")
|> Enum.to_list()

# With options
opts = %ClaudeAgentSDK.Options{max_turns: 5}
ClaudeAgentSDK.query("Build a web server", opts)
|> Enum.to_list()
```

#### `continue/2`
```elixir
@spec continue(String.t() | nil, Options.t() | nil) :: Enumerable.t(ClaudeAgentSDK.Message.t())
```

Continues the most recent conversation.

**Parameters:**
- `prompt` - Optional new prompt to add
- `options` - Optional configuration options

#### `resume/3`
```elixir
@spec resume(String.t(), String.t() | nil, Options.t() | nil) :: Enumerable.t(ClaudeAgentSDK.Message.t())
```

Resumes a specific conversation by session ID.

**Parameters:**
- `session_id` - The session ID to resume
- `prompt` - Optional new prompt
- `options` - Optional configuration options

#### `list_sessions/1`
```elixir
@spec list_sessions(keyword()) :: {:ok, [SessionStore.session_metadata()]} | {:error, term()}
```

Lists saved Claude sessions from the SessionStore.

#### `create_sdk_mcp_server/1`
```elixir
@spec create_sdk_mcp_server(keyword()) :: %{
  type: :sdk,
  name: String.t(),
  version: String.t(),
  registry_pid: pid()
}
```

Creates an SDK-based MCP server for in-process tool execution.

**Parameters (keyword list):**
- `:name` - Server name (required)
- `:version` - Server version (required)
- `:tools` - List of tool modules (required)

**Example:**
```elixir
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calculator",
  version: "1.0.0",
  tools: [MyTools.Add, MyTools.Multiply]
)

options = %ClaudeAgentSDK.Options{
  mcp_servers: %{"calc" => server},
  allowed_tools: ["mcp__calc__add"]
}
```

---

## Configuration: Options

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/options.ex`

The `ClaudeAgentSDK.Options` struct defines all configuration options for SDK requests.

### Complete Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `max_turns` | `integer()` | Maximum conversation turns |
| `system_prompt` | `String.t() \| map()` | Custom system prompt or preset |
| `append_system_prompt` | `String.t()` | Additional prompt to append |
| `output_format` | `atom() \| map()` | Output format (`:text`, `:json`, `:stream_json`, or JSON schema) |
| `tools` | `list() \| map()` | Base tools set selection |
| `allowed_tools` | `[String.t()]` | List of allowed tool names |
| `disallowed_tools` | `[String.t()]` | List of disallowed tool names |
| `mcp_servers` | `map()` | MCP server configurations |
| `mcp_config` | `String.t()` | Path to MCP config file |
| `permission_mode` | `atom()` | Permission handling mode |
| `permission_prompt_tool` | `String.t()` | Tool for permission prompts |
| `can_use_tool` | `function()` | Permission callback function |
| `cwd` | `String.t()` | Working directory |
| `verbose` | `boolean()` | Enable verbose output |
| `model` | `String.t()` | Model selection |
| `fallback_model` | `String.t()` | Fallback model when primary busy |
| `betas` | `[String.t()]` | SDK beta feature flags |
| `agents` | `map()` | Custom agent definitions |
| `agent` | `atom()` | Active agent name |
| `session_id` | `String.t()` | Explicit session ID |
| `fork_session` | `boolean()` | Create new session when resuming |
| `hooks` | `map()` | Hook configurations |
| `timeout_ms` | `integer()` | Command timeout (default: 4,500,000ms / 75 min) |
| `sandbox` | `map()` | Sandbox settings |
| `enable_file_checkpointing` | `boolean()` | Enable file checkpointing |
| `include_partial_messages` | `boolean()` | Enable character-level streaming |
| `preferred_transport` | `atom()` | Transport selection (`:auto`, `:cli`, `:control`) |
| `add_dir` / `add_dirs` | `[String.t()]` | Additional directories |
| `plugins` | `[map()]` | Plugin configurations |
| `extra_args` | `map()` | Additional CLI arguments |
| `env` | `map()` | Environment variable overrides |
| `max_thinking_tokens` | `integer()` | Max thinking tokens |
| `max_budget_usd` | `number()` | Maximum budget in USD |

### Output Format Types

```elixir
@type output_format :: :text | :json | :stream_json | structured_output_format()

@type structured_output_format ::
  {:json_schema, map()} |
  %{
    type: :json_schema | String.t(),
    schema: map(),
    output_format: :json | :stream_json | String.t()  # optional
  }
```

### Permission Modes

```elixir
@type permission_mode :: :default | :accept_edits | :bypass_permissions | :plan
```

- `:default` - All tools go through permission callback
- `:accept_edits` - Edit operations auto-allowed
- `:plan` - Creates plan, shows to user, executes after approval
- `:bypass_permissions` - All tools allowed without callback

### Transport Preference

```elixir
@type transport_preference :: :auto | :cli | :control
```

- `:auto` - Automatic selection based on features (default)
- `:cli` - Force CLI-only mode (ignores control features)
- `:control` - Force control client (even without features)

### Key Functions

#### `Options.new/1`
```elixir
@spec new(keyword()) :: t()
```
Creates a new Options struct with given attributes.

#### `Options.to_args/1`
```elixir
@spec to_args(t()) :: [String.t()]
```
Converts options to CLI arguments.

#### `Options.validate_agents/1`
```elixir
@spec validate_agents(t()) :: :ok | {:error, term()}
```
Validates agent configuration.

---

## Query System

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/query.ex`

The Query module orchestrates query execution, automatically selecting the appropriate backend.

### Transport Selection Logic

```elixir
# Automatic routing based on options:
# - SDK MCP servers present -> Client GenServer (bidirectional)
# - Hooks configured -> Client GenServer
# - Permission callbacks -> Client GenServer
# - Otherwise -> Process.stream (simple unidirectional)
```

### Functions

#### `Query.run/2`
```elixir
@spec run(String.t(), Options.t()) :: Enumerable.t(Message.t())
```

Runs a new query with automatic transport selection.

#### `Query.continue/2`
```elixir
@spec continue(String.t() | nil, Options.t()) :: Enumerable.t(Message.t())
```

Continues the most recent conversation.

#### `Query.resume/3`
```elixir
@spec resume(String.t(), String.t() | nil, Options.t()) :: Enumerable.t(Message.t())
```

Resumes a specific conversation by session ID.

---

## Streaming Mechanisms

The SDK provides two streaming approaches:

### 1. Simple Streaming (Process Module)

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/process.ex`

Uses `erlexec` for subprocess management with synchronous output collection.

```elixir
# Simple query streaming
ClaudeAgentSDK.query("Hello")
|> Enum.each(&IO.inspect/1)
```

**Features:**
- Lower latency for simple queries
- No control protocol overhead
- Memory-efficient via lazy streams
- Timeout handling (default 75 minutes)
- Authentication challenge detection

### 2. Bidirectional Streaming (Streaming Module)

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/streaming.ex`

Persistent sessions with real-time character-by-character updates.

```elixir
# Start session
{:ok, session} = ClaudeAgentSDK.Streaming.start_session()

# Send message and stream response
ClaudeAgentSDK.Streaming.send_message(session, "Hello")
|> Stream.each(fn
  %{type: :text_delta, text: text} -> IO.write(text)
  %{type: :message_stop} -> IO.puts("")
end)
|> Stream.run()

# Close when done
ClaudeAgentSDK.Streaming.close_session(session)
```

### Stream Event Types

```elixir
# Text Streaming
%{type: :text_delta, text: "...", accumulated: "..."}
%{type: :message_stop, final_text: "..."}

# Message Lifecycle
%{type: :message_start, model: "...", role: "...", usage: %{}}
%{type: :content_block_start}
%{type: :content_block_stop, final_text: "..."}

# Tools & Thinking
%{type: :tool_use_start, name: "...", id: "..."}
%{type: :tool_input_delta, json: "..."}
%{type: :thinking_start}
%{type: :thinking_delta, thinking: "..."}

# Metadata & Errors
%{type: :message_delta, stop_reason: "...", stop_sequence: "..."}
%{type: :error, error: ...}
```

### Streaming Session GenServer

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/streaming/session.ex`

Manages persistent Claude CLI subprocess for multi-turn conversations.

```elixir
# API
Session.start_link(options)
Session.send_message(session, message)
Session.close(session)
Session.get_session_id(session)
```

---

## Transport Layer

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/transport.ex`

Behaviour defining the transport interface for CLI communication.

### Transport Behaviour

```elixir
@callback start_link(opts()) :: {:ok, t()} | {:error, term()}
@callback send(t(), message()) :: :ok | {:error, term()}
@callback subscribe(t(), pid()) :: :ok
@callback close(t()) :: :ok
@callback status(t()) :: :connected | :disconnected | :error
```

### Streaming Router

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/transport/streaming_router.ex`

Automatically selects appropriate transport based on options:

```elixir
# Transport selection
StreamingRouter.select_transport(options)
# => :streaming_session (fast CLI-only)
# => :control_client (full features with streaming)

# Feature detection
StreamingRouter.requires_control_protocol?(options)
# => true if hooks, MCP servers, or permissions configured
```

---

## MCP (Model Context Protocol) Support

The SDK supports two types of MCP servers:

### 1. SDK MCP Servers (In-Process)

Run directly within your application without subprocess overhead.

```elixir
# Define tools
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add two numbers", %{
    type: "object",
    properties: %{a: %{type: "number"}, b: %{type: "number"}},
    required: ["a", "b"]
  } do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end
end

# Create server
server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "math",
  version: "1.0.0",
  tools: [MyTools.Add]
)

# Use in options
options = %Options{
  mcp_servers: %{"math" => server},
  allowed_tools: ["mcp__math__add"]
}
```

### 2. External MCP Servers (Subprocess)

Traditional MCP servers running as separate processes.

```elixir
external_server = %{
  type: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/files"]
}

options = %Options{
  mcp_servers: %{"filesystem" => external_server}
}
```

### MCP Server Types

```elixir
@type sdk_mcp_server :: %{
  type: :sdk,
  name: String.t(),
  version: String.t(),
  registry_pid: pid()
}

@type external_mcp_server :: %{
  type: :stdio | :sse | :http,
  command: String.t(),
  args: [String.t()]
}
```

---

## Tool Handling

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/tool.ex`

Macro-based tool definition system for creating in-process MCP tools.

### Tool Definition Macro

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :calculator, "Performs calculations", %{
    type: "object",
    properties: %{expression: %{type: "string"}},
    required: ["expression"]
  } do
    def execute(%{"expression" => expr}) do
      # Evaluate expression...
      {:ok, %{"content" => [%{"type" => "text", "text" => "Result: #{result}"}]}}
    end
  end
end
```

### Tool Return Values

```elixir
# Success
{:ok, %{"content" => [%{"type" => "text", "text" => "..."}]}}

# Error
{:error, "Reason string"}

# Error with flag
{:ok, %{"content" => [...], "isError" => true}}
```

### Tool Registry

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/tool/registry.ex`

GenServer managing tool registration and lookup.

```elixir
# Start registry
{:ok, registry} = Tool.Registry.start_link([])

# Register tool
Tool.Registry.register_tool(registry, tool_metadata)

# Lookup tool
Tool.Registry.get_tool(registry, "tool_name")

# List all tools
Tool.Registry.list_tools(registry)
```

### Tool Functions

```elixir
# List tools in a module
Tool.list_tools(MyTools)

# Validate schema
Tool.valid_schema?(%{type: "object"})
```

---

## Hooks System

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/hooks/hooks.ex`

Lifecycle hooks for intercepting and controlling agent execution.

### Hook Events

| Event | Description |
|-------|-------------|
| `:session_start` | At session start |
| `:session_end` | At session end |
| `:notification` | For CLI notifications |
| `:pre_tool_use` | Before tool executes |
| `:post_tool_use` | After tool executes |
| `:user_prompt_submit` | When user submits prompt |
| `:stop` | When agent finishes |
| `:subagent_stop` | When subagent finishes |
| `:pre_compact` | Before context compaction |

### Hook Configuration

```elixir
hooks = %{
  pre_tool_use: [
    %Matcher{matcher: "Bash", hooks: [&check_bash/3]},
    %Matcher{matcher: "Write|Edit", hooks: [&check_files/3]}
  ],
  post_tool_use: [
    %Matcher{matcher: "*", hooks: [&log_usage/3]}
  ]
}

options = %Options{hooks: hooks}
```

### Hook Callback Signature

```elixir
@type hook_callback :: (hook_input(), String.t() | nil, hook_context() -> Output.t())

# Example
def check_bash(input, _tool_use_id, _context) do
  case input do
    %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
      if String.contains?(cmd, "rm -rf") do
        Output.deny("Dangerous command blocked")
      else
        Output.allow()
      end
    _ ->
      %{}
  end
end
```

### Hook Output Types

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/hooks/output.ex`

```elixir
# Allow execution
Output.allow()
Output.allow(updated_input: %{...})  # Modify input

# Deny execution
Output.deny("Reason")

# Custom output
%{
  "decision" => "allow" | "deny" | "block",
  "reason" => "...",
  "updatedInput" => %{...}
}
```

### Hook Matcher

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/hooks/matcher.ex`

```elixir
# Match specific tool
%Matcher{matcher: "Bash", hooks: [&callback/3]}

# Match multiple tools (regex)
%Matcher{matcher: "Write|Edit", hooks: [&callback/3]}

# Match all tools
%Matcher{matcher: "*", hooks: [&callback/3]}
```

---

## Permission System

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/permission.ex`

Fine-grained control over tool execution through callbacks.

### Permission Context

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/permission/context.ex`

```elixir
%Context{
  tool_name: "Write",
  tool_input: %{"file_path" => "/etc/hosts", "content" => "..."},
  session_id: "...",
  cwd: "/project"
}
```

### Permission Result

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/permission/result.ex`

```elixir
# Allow
Result.allow()
Result.allow(updated_input: %{...})

# Deny
Result.deny("Reason")
```

### Permission Callback Example

```elixir
callback = fn context ->
  case context.tool_name do
    "Bash" ->
      if String.contains?(context.tool_input["command"], "rm -rf") do
        Result.deny("Dangerous command")
      else
        Result.allow()
      end

    "Write" ->
      # Redirect system file writes
      if String.starts_with?(context.tool_input["file_path"], "/etc/") do
        safe_path = "/tmp/safe/" <> Path.basename(context.tool_input["file_path"])
        Result.allow(updated_input: %{context.tool_input | "file_path" => safe_path})
      else
        Result.allow()
      end

    _ ->
      Result.allow()
  end
end

options = %Options{
  can_use_tool: callback,
  permission_mode: :default
}
```

---

## Session Management

### Session Utilities

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/session.ex`

Helper functions for working with session data.

```elixir
# Extract session ID
Session.extract_session_id(messages)

# Calculate cost
Session.calculate_cost(messages)

# Count turns
Session.count_turns(messages)

# Extract model
Session.extract_model(messages)

# Get summary
Session.get_summary(messages)
```

### Session Store

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/session_store.ex`

GenServer for persistent session storage.

```elixir
# Start store
{:ok, store} = SessionStore.start_link([])

# Save session
SessionStore.save_session(store, session_id, messages)

# Load session
SessionStore.load_session(store, session_id)

# List sessions
SessionStore.list_sessions(store)

# Delete session
SessionStore.delete_session(store, session_id)
```

---

## Message Types

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/message.ex`

### Message Structure

```elixir
%Message{
  type: :assistant | :user | :result | :system | :stream_event,
  subtype: :success | :error_max_turns | :error_during_execution | :init | nil,
  data: %{...},
  raw: %{...}  # Original JSON
}
```

### Message Types

| Type | Description | Data Fields |
|------|-------------|-------------|
| `:system` | Session initialization | `session_id`, `model`, `cwd`, `tools` |
| `:user` | User input | `message`, `session_id` |
| `:assistant` | Claude response | `message`, `session_id`, `error` |
| `:result` | Final result | `total_cost_usd`, `duration_ms`, `num_turns` |
| `:stream_event` | Streaming event | `uuid`, `event`, `session_id` |

### Result Subtypes

- `:success` - Successful completion
- `:error_max_turns` - Max turns limit reached
- `:error_during_execution` - Error during execution

### Message Functions

```elixir
# Parse JSON
Message.from_json(json_string)

# Get content blocks
Message.content_blocks(message)

# Check if final
Message.final?(message)

# Check if error
Message.error?(message)

# Get session ID
Message.session_id(message)

# Get user UUID (for checkpointing)
Message.user_uuid(message)
```

### Content Block Types

```elixir
%{type: :text, text: "..."}
%{type: :thinking, thinking: "...", signature: "..."}
%{type: :tool_use, id: "...", name: "...", input: %{}}
%{type: :tool_result, tool_use_id: "...", content: "...", is_error: boolean()}
```

---

## Error Handling

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/errors.ex`

### Error Types

```elixir
# CLI Connection Error
%CLIConnectionError{
  message: String.t(),
  cwd: String.t() | nil,
  reason: term()
}

# CLI Not Found Error
%CLINotFoundError{
  message: String.t(),
  cli_path: String.t() | nil
}

# Process Error
%ProcessError{
  message: String.t(),
  exit_code: integer() | nil,
  stderr: String.t() | nil
}

# JSON Decode Error
%CLIJSONDecodeError{
  message: String.t(),
  line: String.t(),
  original_error: term()
}

# Message Parse Error
%MessageParseError{
  message: String.t(),
  data: map() | nil
}
```

### Assistant Errors

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/assistant_error.ex`

```elixir
# Error codes embedded in assistant messages
:rate_limit
:authentication_failed
:network_error
:timeout
# ... etc
```

### Error Handling Pattern

```elixir
ClaudeAgentSDK.query("Hello")
|> Enum.each(fn msg ->
  case msg do
    %Message{type: :result, subtype: :error_during_execution, data: data} ->
      IO.puts("Error: #{data.error}")

    %Message{type: :assistant, data: %{error: error}} when not is_nil(error) ->
      IO.puts("Assistant error: #{inspect(error)}")

    %Message{type: :assistant, data: data} ->
      IO.puts(data.message["content"])

    _ -> :ok
  end
end)
```

---

## Authentication

### Auth Manager

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/auth_manager.ex`

GenServer for token management with automatic refresh.

```elixir
# Start manager
{:ok, _pid} = AuthManager.start_link([])

# Ensure authenticated
:ok = AuthManager.ensure_authenticated()

# Setup token (interactive)
{:ok, token} = AuthManager.setup_token()

# Get current token
{:ok, token} = AuthManager.get_token()

# Refresh token
{:ok, token} = AuthManager.refresh_token()

# Clear auth
:ok = AuthManager.clear_auth()

# Get status
status = AuthManager.status()
```

### Auth Checker

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/auth_checker.ex`

Authentication validation utilities.

```elixir
# Quick check
AuthChecker.authenticated?()

# Full diagnosis
diagnosis = AuthChecker.diagnose()
# => %{
#   cli_installed: true,
#   cli_version: "2.0.75",
#   authenticated: true,
#   auth_method: "Anthropic API",
#   status: :ready,
#   recommendations: [...]
# }

# Ensure ready (raises on failure)
AuthChecker.ensure_ready!()

# Check specific auth method
AuthChecker.auth_method_available?(:bedrock)
```

### Environment Variables

```bash
# Primary authentication
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_AGENT_OAUTH_TOKEN=...

# Provider selection
CLAUDE_AGENT_USE_BEDROCK=1  # AWS Bedrock
CLAUDE_AGENT_USE_VERTEX=1   # GCP Vertex AI

# AWS credentials
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_PROFILE=...

# GCP credentials
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
GOOGLE_CLOUD_PROJECT=...
```

---

## CLI Integration

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/cli.ex`

### CLI Functions

```elixir
# Find executable
CLI.find_executable()
# => {:ok, "/usr/local/bin/claude"}

# Find executable (raises on failure)
CLI.find_executable!()

# Get version
CLI.version()
# => {:ok, "2.0.75"}

# Check outdated
CLI.warn_if_outdated()
```

### Environment Variables for Process

```elixir
# Automatically passed to CLI
CLAUDE_AGENT_OAUTH_TOKEN
ANTHROPIC_API_KEY
PATH
HOME
CLAUDE_CODE_ENTRYPOINT=sdk-elixir
CLAUDE_AGENT_SDK_VERSION=0.6.10
```

---

## Helper Modules

### Option Builder

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/option_builder.ex`

Pre-configured option presets for common use cases.

#### Environment Presets

```elixir
# Development - permissive, verbose
OptionBuilder.build_development_options()

# Staging - moderate restrictions
OptionBuilder.build_staging_options()

# Production - restrictive, safe
OptionBuilder.build_production_options()

# Auto-select based on Mix.env()
OptionBuilder.for_environment()
```

#### Use Case Presets

```elixir
# Code analysis (read-only)
OptionBuilder.build_analysis_options()

# Documentation generation
OptionBuilder.build_documentation_options()

# Testing/test generation
OptionBuilder.build_testing_options()

# Simple chat (no tools)
OptionBuilder.build_chat_options()

# Quick one-off queries
OptionBuilder.quick()

# Sandboxed execution
OptionBuilder.sandboxed("/tmp/sandbox")
```

#### Model Presets

```elixir
# Maximum capability
OptionBuilder.with_opus()

# Balanced performance
OptionBuilder.with_sonnet()

# Fast responses (default)
OptionBuilder.with_haiku()
```

#### Builder Utilities

```elixir
# Merge with preset
options = OptionBuilder.merge(:development, %{max_turns: 15})

# Add working directory
options = OptionBuilder.with_working_directory(options, "/project")

# Add system prompt
options = OptionBuilder.with_system_prompt(options, "You are an expert")

# Add tools
options = OptionBuilder.with_additional_tools(options, ["Grep"])

# Set turn limit
options = OptionBuilder.with_turn_limit(options, 10)

# Validate options
{:ok, options} = OptionBuilder.validate(options)
{:warning, options, warnings} = OptionBuilder.validate(risky_options)
```

### Content Extractor

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/content_extractor.ex`

Extract text content from messages.

```elixir
ContentExtractor.extract_text(message)
```

### JSON Module

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/json.ex`

JSON encoding/decoding wrapper using OTP `:json`.

```elixir
JSON.decode(string)
JSON.encode(term)
```

### Agent Module

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/agent.ex`

Custom agent definitions.

```elixir
%Agent{
  description: "Security reviewer",
  prompt: "Review code for vulnerabilities",
  model: "opus"
}

Agent.new(description: "...", prompt: "...")
Agent.validate(agent)
Agent.to_cli_map(agent)
```

### Abort Signal

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/abort_signal.ex`

Cooperative cancellation mechanism.

```elixir
signal = AbortSignal.new()
AbortSignal.abort(signal)
AbortSignal.aborted?(signal)
```

### Debug Mode

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/debug_mode.ex`

Debug logging utilities.

### Model Module

**File**: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/model.ex`

Model name utilities and validation.

---

## Usage Examples

### Basic Query

```elixir
ClaudeAgentSDK.query("Write a hello world function in Elixir")
|> Enum.each(fn msg ->
  case msg.type do
    :assistant -> IO.puts(msg.data.message["content"])
    :result -> IO.puts("Cost: $#{msg.data.total_cost_usd}")
    _ -> :ok
  end
end)
```

### With Options

```elixir
options = %ClaudeAgentSDK.Options{
  max_turns: 5,
  system_prompt: "You are an Elixir expert",
  output_format: :stream_json,
  permission_mode: :accept_edits,
  allowed_tools: ["Read", "Edit", "Bash"]
}

ClaudeAgentSDK.query("Refactor this code for better performance", options)
|> Enum.to_list()
```

### Streaming Chat

```elixir
{:ok, session} = ClaudeAgentSDK.Streaming.start_session()

# First message
ClaudeAgentSDK.Streaming.send_message(session, "My name is Alice")
|> Stream.each(fn
  %{type: :text_delta, text: text} -> IO.write(text)
  %{type: :message_stop} -> IO.puts("")
end)
|> Stream.run()

# Follow-up (context preserved)
ClaudeAgentSDK.Streaming.send_message(session, "What's my name?")
|> Enum.to_list()

ClaudeAgentSDK.Streaming.close_session(session)
```

### With SDK MCP Tools

```elixir
defmodule Calculator do
  use ClaudeAgentSDK.Tool

  deftool :add, "Add numbers", %{
    type: "object",
    properties: %{a: %{type: "number"}, b: %{type: "number"}},
    required: ["a", "b"]
  } do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
    end
  end
end

server = ClaudeAgentSDK.create_sdk_mcp_server(
  name: "calc",
  version: "1.0.0",
  tools: [Calculator.Add]
)

options = %ClaudeAgentSDK.Options{
  mcp_servers: %{"calc" => server}
}

ClaudeAgentSDK.query("What is 15 + 27?", options)
```

### With Hooks

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

check_bash = fn input, _id, _ctx ->
  if String.contains?(input["tool_input"]["command"] || "", "rm -rf") do
    Output.deny("Dangerous command blocked")
  else
    Output.allow()
  end
end

options = %ClaudeAgentSDK.Options{
  hooks: %{
    pre_tool_use: [%Matcher{matcher: "Bash", hooks: [check_bash]}]
  }
}
```

---

## Version History

| Version | Key Features |
|---------|--------------|
| v0.6.x | Streaming + Tools, Control client, Partial messages |
| v0.5.x | SDK MCP servers, External MCP support |
| v0.4.x | Permission system, Permission callbacks |
| v0.3.x | Hooks system, Lifecycle events |
| v0.2.x | Session management, Fork session |
| v0.1.x | Model selection, Agents, Option builder |

---

## Files Reference

| File | Purpose |
|------|---------|
| `lib/claude_agent_sdk.ex` | Main module with public API |
| `lib/claude_agent_sdk/options.ex` | Configuration struct |
| `lib/claude_agent_sdk/query.ex` | Query orchestration |
| `lib/claude_agent_sdk/process.ex` | CLI subprocess management |
| `lib/claude_agent_sdk/streaming.ex` | Bidirectional streaming |
| `lib/claude_agent_sdk/streaming/session.ex` | Streaming session GenServer |
| `lib/claude_agent_sdk/streaming/event_parser.ex` | Stream event parsing |
| `lib/claude_agent_sdk/client.ex` | Control protocol client |
| `lib/claude_agent_sdk/transport.ex` | Transport behaviour |
| `lib/claude_agent_sdk/transport/streaming_router.ex` | Transport selection |
| `lib/claude_agent_sdk/tool.ex` | Tool definition macro |
| `lib/claude_agent_sdk/tool/registry.ex` | Tool registry GenServer |
| `lib/claude_agent_sdk/hooks/hooks.ex` | Hooks type definitions |
| `lib/claude_agent_sdk/hooks/matcher.ex` | Hook pattern matching |
| `lib/claude_agent_sdk/hooks/output.ex` | Hook output builders |
| `lib/claude_agent_sdk/hooks/registry.ex` | Hook registry |
| `lib/claude_agent_sdk/permission.ex` | Permission system |
| `lib/claude_agent_sdk/permission/context.ex` | Permission context |
| `lib/claude_agent_sdk/permission/result.ex` | Permission result |
| `lib/claude_agent_sdk/message.ex` | Message parsing |
| `lib/claude_agent_sdk/session.ex` | Session utilities |
| `lib/claude_agent_sdk/session_store.ex` | Session persistence |
| `lib/claude_agent_sdk/cli.ex` | CLI discovery |
| `lib/claude_agent_sdk/auth_manager.ex` | Token management |
| `lib/claude_agent_sdk/auth_checker.ex` | Auth validation |
| `lib/claude_agent_sdk/option_builder.ex` | Option presets |
| `lib/claude_agent_sdk/agent.ex` | Agent definitions |
| `lib/claude_agent_sdk/errors.ex` | Error types |
| `lib/claude_agent_sdk/json.ex` | JSON utilities |
| `lib/claude_agent_sdk/content_extractor.ex` | Content extraction |
| `lib/claude_agent_sdk/abort_signal.ex` | Cancellation |
| `lib/claude_agent_sdk/model.ex` | Model utilities |
| `lib/claude_agent_sdk/debug_mode.ex` | Debug logging |
| `lib/claude_agent_sdk/assistant_error.ex` | Assistant error codes |
