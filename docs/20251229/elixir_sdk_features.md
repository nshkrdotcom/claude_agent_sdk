# Elixir Claude Agent SDK Features

This document provides a comprehensive reference of all features available in the Elixir Claude Agent SDK (`lib/claude_agent_sdk/`).

## Table of Contents

1. [Options Fields](#options-fields)
2. [Message Types and Content Blocks](#message-types-and-content-blocks)
3. [Tool System](#tool-system)
4. [Control Protocol Features](#control-protocol-features)
5. [Hook System](#hook-system)
6. [Permission System](#permission-system)
7. [AuthManager (Elixir-only)](#authmanager-elixir-only)
8. [SessionStore (Elixir-only)](#sessionstore-elixir-only)
9. [Orchestrator (Elixir-only)](#orchestrator-elixir-only)
10. [Error Handling](#error-handling)

---

## Options Fields

The `ClaudeAgentSDK.Options` struct defines all configuration options for agent sessions.

### Core Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `prompt` | `String.t()` | `nil` | Initial prompt to send |
| `cwd` | `String.t()` | `nil` | Working directory for CLI |
| `model` | `String.t()` | `nil` | Model to use (e.g., `"claude-sonnet-4-20250514"`) |
| `max_turns` | `pos_integer()` | `nil` | Maximum conversation turns |
| `system_prompt` | `String.t()` | `nil` | Custom system prompt |
| `allowed_tools` | `[String.t()]` | `nil` | List of allowed tool names |
| `disallowed_tools` | `[String.t()]` | `nil` | List of disallowed tool names |
| `session_id` | `String.t()` | `nil` | Session ID for resumption |

### Permission Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `permission_mode` | `permission_mode()` | `:default` | Permission handling mode |
| `can_use_tool` | `(Context.t() -> Result.t())` | `nil` | Permission callback |

### MCP Server Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mcp_servers` | `%{String.t() => mcp_config()}` | `nil` | MCP server configurations |

### Hook Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hooks` | `Hooks.config()` | `nil` | Hook configuration |

### Advanced Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cli_path` | `String.t()` | `nil` | Custom path to Claude CLI |
| `resume` | `boolean()` | `false` | Resume previous session |
| `continue_conversation` | `boolean()` | `false` | Continue existing conversation |
| `enable_file_checkpointing` | `boolean()` | `false` | Enable file rewind support |
| `user` | `String.t()` | `nil` | Run CLI as different user |
| `stderr` | `(String.t() -> any())` | `nil` | Stderr handler function |

### Agent Configuration Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `agent` | `atom()` | `nil` | Active agent name |
| `agents` | `%{atom() => Agent.t()}` | `nil` | Available agent configurations |

### Example

```elixir
alias ClaudeAgentSDK.Options

options = %Options{
  prompt: "Write a hello world function",
  model: "claude-sonnet-4-20250514",
  max_turns: 10,
  allowed_tools: ["Bash", "Write", "Read"],
  system_prompt: "You are a helpful coding assistant.",
  cwd: "/path/to/project"
}

ClaudeAgentSDK.query("Hello", options)
|> Enum.each(&IO.inspect/1)
```

---

## Message Types and Content Blocks

### Message Struct

```elixir
defstruct [
  :type,    # :system | :assistant | :user | :result
  :subtype, # :init | :text | :tool_use | :tool_result | :success | etc.
  :data,    # Parsed message data
  :raw      # Original JSON data
]
```

### Message Types

| Type | Description |
|------|-------------|
| `:system` | System/initialization messages |
| `:assistant` | Claude's responses |
| `:user` | User messages |
| `:result` | Query result/completion messages |
| `:stream_event` | Streaming events (v0.6.0+) |

### Message Subtypes

| Subtype | Type | Description |
|---------|------|-------------|
| `:init` | system | Session initialization |
| `:text` | assistant | Text content |
| `:tool_use` | assistant | Tool invocation |
| `:tool_result` | user | Tool execution result |
| `:success` | result | Successful completion |
| `:error` | result | Error during query |
| `:error_max_turns` | result | Max turns exceeded |
| `:error_during_execution` | result | Execution error |
| `:interrupted` | result | Query interrupted |

### Content Block Types

| Block Type | Description |
|------------|-------------|
| `text` | Plain text content |
| `tool_use` | Tool usage with name, input, ID |
| `tool_result` | Result from tool execution |

### Example

```elixir
# Pattern matching on messages
case message do
  %Message{type: :system, subtype: :init, data: %{session_id: id}} ->
    IO.puts("Session started: #{id}")

  %Message{type: :assistant, subtype: :text, data: %{text: text}} ->
    IO.puts("Claude: #{text}")

  %Message{type: :result, subtype: :success, data: %{total_cost_usd: cost}} ->
    IO.puts("Query complete. Cost: $#{cost}")

  %Message{type: :result, subtype: subtype} when subtype in [:error, :error_max_turns] ->
    IO.puts("Error: #{subtype}")
end
```

---

## Tool System

### The deftool Macro

The Elixir SDK provides a `deftool` macro for defining custom tools:

```elixir
defmodule MyTools do
  use ClaudeAgentSDK.Tool

  deftool :calculate_sum, "Calculate the sum of two numbers" do
    param :a, :integer, required: true, description: "First number"
    param :b, :integer, required: true, description: "Second number"
  end

  def calculate_sum(%{"a" => a, "b" => b}) do
    {:ok, a + b}
  end
end
```

### Tool Definition Options

| Option | Type | Description |
|--------|------|-------------|
| `name` | `atom()` | Tool name |
| `description` | `String.t()` | Tool description |
| `param` | macro | Define a parameter |

### Parameter Options

| Option | Type | Description |
|--------|------|-------------|
| `type` | `:string \| :integer \| :boolean \| :object \| :array` | Parameter type |
| `required` | `boolean()` | Whether required |
| `description` | `String.t()` | Parameter description |
| `default` | `any()` | Default value |

### Tool Registry

The Tool Registry manages tool registration and execution:

```elixir
alias ClaudeAgentSDK.Tool.Registry

# Start a registry
{:ok, registry} = Registry.start_link()

# Register a tool module
:ok = Registry.register(registry, MyTools)

# List available tools
{:ok, tools} = Registry.list_tools(registry)

# Execute a tool
{:ok, result} = Registry.execute_tool(registry, :calculate_sum, %{"a" => 1, "b" => 2})
```

### create_sdk_mcp_server

Creates an SDK-hosted MCP server:

```elixir
alias ClaudeAgentSDK.Tool

# Create MCP server with tool modules
{:ok, server_config} = Tool.create_sdk_mcp_server(
  name: "my-tools",
  version: "1.0.0",
  tools: [MyTools]
)

# Use in options
options = %Options{
  prompt: "Use my tool",
  mcp_servers: %{"my-tools" => server_config}
}
```

### Built-in Tools

| Tool Name | Description |
|-----------|-------------|
| `Bash` | Execute shell commands |
| `Read` | Read file contents |
| `Write` | Write to files |
| `Edit` | Edit file contents |
| `MultiEdit` | Multiple file edits |
| `Glob` | File pattern matching |
| `Grep` | Search file contents |
| `WebFetch` | Fetch web content |
| `WebSearch` | Search the web |
| `NotebookEdit` | Edit Jupyter notebooks |
| `TodoWrite` | Manage todo lists |

---

## Control Protocol Features

### Protocol Module

The `ClaudeAgentSDK.ControlProtocol.Protocol` module handles bidirectional communication.

### Message Types

| Direction | Type | Description |
|-----------|------|-------------|
| SDK -> CLI | `:control_request` | Request from SDK |
| CLI -> SDK | `:control_response` | Response to SDK |
| CLI -> SDK | `:control_request` | Request from CLI (hooks) |
| SDK -> CLI | `:control_response` | Response to CLI |
| SDK -> CLI | `:control_cancel_request` | Cancel pending request |
| CLI -> SDK | `:stream_event` | Streaming event |
| Both | `:sdk_message` | Standard SDK message |

### Control Request Subtypes

| Subtype | Description |
|---------|-------------|
| `initialize` | Initialize with hooks config |
| `set_model` | Change model at runtime |
| `set_permission_mode` | Change permission mode |
| `interrupt` | Interrupt current operation |
| `rewind_files` | Rewind file changes |
| `hook_callback` | Hook callback from CLI |
| `can_use_tool` | Permission check |
| `sdk_mcp_request` | SDK MCP server request |
| `mcp_message` | MCP message (Python parity) |

### Client Control Functions

```elixir
alias ClaudeAgentSDK.Client

# Start client
{:ok, client} = Client.start_link(options)

# Runtime model switching
:ok = Client.set_model(client, "claude-sonnet-4-20250514")
{:ok, model} = Client.get_model(client)

# Runtime permission mode switching
:ok = Client.set_permission_mode(client, :plan)

# Interrupt current operation
:ok = Client.interrupt(client)

# Rewind files to checkpoint (requires enable_file_checkpointing: true)
:ok = Client.rewind_files(client, "user_message_id")

# Get server info
{:ok, info} = Client.get_server_info(client)
```

### Protocol Encoding/Decoding

```elixir
alias ClaudeAgentSDK.ControlProtocol.Protocol

# Encode initialize request
{request_id, json} = Protocol.encode_initialize_request(hooks_config, sdk_mcp_servers)

# Encode set_model request
{request_id, json} = Protocol.encode_set_model_request("claude-sonnet-4-20250514")

# Encode hook response
json = Protocol.encode_hook_response(request_id, output_map, :success)

# Decode message
{:ok, {:control_request, data}} = Protocol.decode_message(json_string)
```

---

## Hook System

### Hook Events

| Event | Atom | Description |
|-------|------|-------------|
| PreToolUse | `:pre_tool_use` | Before tool execution |
| PostToolUse | `:post_tool_use` | After tool execution |

### Hook Configuration

```elixir
alias ClaudeAgentSDK.{Options, Hooks}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Define hook callback
def check_bash(input, tool_use_id, context) do
  command = input["command"] || ""

  if String.contains?(command, "rm -rf") do
    Output.deny("Dangerous command blocked")
  else
    Output.allow()
  end
end

# Configure hooks
options = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&check_bash/3], timeout_ms: 30_000)
    ]
  }
}
```

### Matcher Configuration

| Field | Type | Description |
|-------|------|-------------|
| `tool_name` | `String.t() \| [String.t()]` | Tool(s) to match |
| `hooks` | `[callback()]` | Hook callbacks |
| `timeout_ms` | `pos_integer() \| nil` | Callback timeout |

### Hook Callback Signature

```elixir
@spec callback(
  input :: map(),
  tool_use_id :: String.t(),
  context :: %{signal: AbortSignal.t()}
) :: Output.t()
```

### Output Module

```elixir
alias ClaudeAgentSDK.Hooks.Output

# Allow tool execution
Output.allow()

# Deny with message
Output.deny("Operation not permitted")

# Modify input
Output.allow(updated_input: %{"command" => "echo 'safe'"})

# Add hook-specific output
Output.allow(hook_specific_output: %{logged: true})
```

### Hook Registry

The Hook Registry manages callback registration:

```elixir
alias ClaudeAgentSDK.Hooks.Registry

registry = Registry.new()
registry = Registry.register(registry, &my_callback/3)

callback_id = Registry.get_id(registry, &my_callback/3)
{:ok, callback_fn} = Registry.get_callback(registry, callback_id)
```

---

## Permission System

### Permission Modes

| Mode | Atom | Description |
|------|------|-------------|
| Default | `:default` | All tools go through callback |
| Accept Edits | `:accept_edits` | Edit operations auto-allowed |
| Plan | `:plan` | Show plan before execution |
| Bypass | `:bypass_permissions` | All tools allowed |

### Permission Context

```elixir
alias ClaudeAgentSDK.Permission.Context

context = Context.new(
  tool_name: "Write",
  tool_input: %{"file_path" => "/etc/passwd"},
  session_id: "abc123",
  suggestions: [],
  blocked_path: nil,
  signal: abort_signal
)
```

### Permission Result

```elixir
alias ClaudeAgentSDK.Permission.Result

# Allow
Result.allow()

# Deny
Result.deny("Cannot write to system files")

# Allow with modified input
Result.allow(updated_input: %{"file_path" => "/tmp/safe.txt"})
```

### Permission Callback

```elixir
alias ClaudeAgentSDK.Options
alias ClaudeAgentSDK.Permission.{Context, Result}

permission_callback = fn %Context{} = context ->
  case context.tool_name do
    "Write" ->
      if String.starts_with?(context.tool_input["file_path"], "/etc/") do
        Result.deny("Cannot write to /etc")
      else
        Result.allow()
      end

    _ ->
      Result.allow()
  end
end

options = %Options{
  can_use_tool: permission_callback,
  permission_mode: :default
}
```

### Runtime Mode Switching

```elixir
{:ok, client} = Client.start_link(options)

# Switch to plan mode
:ok = Client.set_permission_mode(client, :plan)

# Switch to accept edits
:ok = Client.set_permission_mode(client, :accept_edits)

# Switch back to default
:ok = Client.set_permission_mode(client, :default)
```

---

## AuthManager (Elixir-only)

The AuthManager provides automatic token acquisition and management. This is an Elixir-specific feature not present in the Python SDK.

### Features

- Automatic token setup via `claude setup-token`
- Persistent storage across restarts
- Token expiry detection and refresh
- Multi-provider support (Anthropic, AWS Bedrock, GCP Vertex)
- Fallback to ANTHROPIC_API_KEY environment variable

### Usage

```elixir
alias ClaudeAgentSDK.AuthManager

# Start the auth manager
{:ok, _pid} = AuthManager.start_link()

# Ensure authentication is valid
:ok = AuthManager.ensure_authenticated()

# Setup new token (interactive)
{:ok, token} = AuthManager.setup_token()

# Get current token
{:ok, token} = AuthManager.get_token()

# Refresh token manually
{:ok, token} = AuthManager.refresh_token()

# Clear stored authentication
:ok = AuthManager.clear_auth()

# Get authentication status
status = AuthManager.status()
# %{
#   authenticated: true,
#   provider: :anthropic,
#   token_present: true,
#   expires_at: ~U[2025-11-07 00:00:00Z],
#   time_until_expiry_hours: 720
# }
```

### Configuration

```elixir
# config/config.exs
config :claude_agent_sdk,
  auth_storage: :file,                    # :file | :application_env | :custom
  auth_file_path: "~/.claude_sdk/token.json",
  auto_refresh: true,
  refresh_before_expiry: 86_400_000       # 1 day in ms
```

### Provider Detection

The AuthManager automatically detects providers:

| Environment Variable | Provider |
|---------------------|----------|
| `CLAUDE_AGENT_USE_BEDROCK=1` | `:bedrock` |
| `CLAUDE_AGENT_USE_VERTEX=1` | `:vertex` |
| (default) | `:anthropic` |

---

## SessionStore (Elixir-only)

The SessionStore provides persistent session storage and management. This is an Elixir-specific feature.

### Features

- Save/load complete session message history
- Tag sessions for organization
- Search sessions by tags, date, cost
- Automatic cleanup of old sessions
- Session metadata tracking

### Usage

```elixir
alias ClaudeAgentSDK.SessionStore

# Start the store
{:ok, _pid} = SessionStore.start_link()

# Save a session
:ok = SessionStore.save_session(session_id, messages,
  tags: ["feature-dev", "important"],
  description: "Implemented user authentication"
)

# Load session
{:ok, session_data} = SessionStore.load_session(session_id)
# session_data.messages - List of messages
# session_data.metadata - Session metadata

# List all sessions
sessions = SessionStore.list_sessions()

# Search sessions
sessions = SessionStore.search(
  tags: ["important"],
  after: ~D[2025-10-01],
  min_cost: 0.10
)

# Delete a session
:ok = SessionStore.delete_session(session_id)

# Cleanup old sessions
count = SessionStore.cleanup_old_sessions(max_age_days: 30)
```

### Session Metadata

```elixir
%{
  session_id: "abc123",
  created_at: ~U[2025-10-15 10:00:00Z],
  updated_at: ~U[2025-10-15 11:30:00Z],
  message_count: 42,
  total_cost: 0.0523,
  tags: ["feature-dev"],
  description: "Feature implementation",
  model: "claude-sonnet-4-20250514"
}
```

### Search Criteria

| Criteria | Type | Description |
|----------|------|-------------|
| `:tags` | `[String.t()]` | Match sessions with these tags |
| `:after` | `Date.t() \| DateTime.t()` | Created after date |
| `:before` | `Date.t() \| DateTime.t()` | Created before date |
| `:min_cost` | `float()` | Minimum cost threshold |
| `:max_cost` | `float()` | Maximum cost threshold |

### Configuration

```elixir
# config/config.exs
config :claude_agent_sdk,
  session_storage_dir: "~/.claude_sdk/sessions"
```

---

## Orchestrator (Elixir-only)

The Orchestrator provides concurrent query orchestration with rate limiting and error recovery. This is an Elixir-specific feature.

### Features

- Parallel query execution with concurrency limits
- Sequential pipeline workflows
- Automatic retry with exponential backoff
- Cost tracking and statistics
- Error aggregation

### Parallel Queries

```elixir
alias ClaudeAgentSDK.Orchestrator

queries = [
  {"Analyze file1.ex", %Options{}},
  {"Analyze file2.ex", %Options{}},
  {"Analyze file3.ex", %Options{}}
]

{:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 3)

Enum.each(results, fn result ->
  IO.puts("Prompt: #{result.prompt}")
  IO.puts("Success: #{result.success}")
  IO.puts("Cost: $#{result.cost}")
  IO.puts("Duration: #{result.duration_ms}ms")
end)
```

### Pipeline Execution

```elixir
steps = [
  {"Analyze this code: ...", analysis_opts},
  {"Suggest improvements", refactor_opts},
  {"Generate tests for improved code", test_opts}
]

{:ok, final_messages} = Orchestrator.query_pipeline(steps,
  use_context: true,    # Include previous output in next prompt
  stop_on_error: true   # Stop pipeline on first error
)
```

### Retry with Backoff

```elixir
{:ok, messages} = Orchestrator.query_with_retry(
  "Analyze this code",
  options,
  max_retries: 5,
  backoff_ms: 2000,
  exponential: true     # Exponential backoff
)
```

### Parallel Query Result

```elixir
%{
  prompt: "Analyze file1.ex",
  messages: [%Message{}, ...],
  cost: 0.0123,
  session_id: "abc123",
  success: true,
  errors: [],
  duration_ms: 5234
}
```

### Error Handling

```elixir
case Orchestrator.query_parallel(queries) do
  {:ok, results} ->
    IO.puts("All #{length(results)} queries succeeded")

  {:error, {:parallel_failures, failures}} ->
    IO.puts("#{length(failures)} queries failed")
    Enum.each(failures, fn f -> IO.inspect(f.errors) end)
end

case Orchestrator.query_with_retry(prompt, opts) do
  {:ok, messages} ->
    IO.puts("Success after retries")

  {:error, {:max_retries_exceeded, errors}} ->
    IO.puts("All retries failed: #{inspect(errors)}")
end
```

---

## Error Handling

### Exception Types

| Exception | Description |
|-----------|-------------|
| `CLIConnectionError` | Failed to connect to CLI |
| `CLINotFoundError` | Claude CLI not found |
| `ProcessError` | CLI process error |
| `CLIJSONDecodeError` | Invalid JSON from CLI |
| `MessageParseError` | Message parsing failed |

### Error Structs

```elixir
# CLIConnectionError
%CLIConnectionError{
  message: "Failed to connect",
  cwd: "/path/to/dir",
  reason: :timeout
}

# CLINotFoundError
%CLINotFoundError{
  message: "Claude CLI not found",
  cli_path: nil
}

# ProcessError
%ProcessError{
  message: "Process exited",
  exit_code: 1,
  stderr: "Error output"
}

# CLIJSONDecodeError
%CLIJSONDecodeError{
  message: "Invalid JSON",
  line: "{invalid",
  original_error: %Jason.DecodeError{}
}

# MessageParseError
%MessageParseError{
  message: "Failed to parse message",
  data: %{"type" => "unknown"}
}
```

### Error Handling Example

```elixir
alias ClaudeAgentSDK.Errors.{
  CLIConnectionError,
  CLINotFoundError,
  ProcessError
}

try do
  ClaudeAgentSDK.query("Hello", options)
  |> Enum.each(fn message ->
    case message do
      %Message{type: :result, subtype: :error} ->
        IO.puts("Query error")

      %Message{type: :result, subtype: :success, data: data} ->
        IO.puts("Success! Cost: $#{data.total_cost_usd}")

      _ ->
        :ok
    end
  end)
rescue
  e in CLINotFoundError ->
    IO.puts("Claude CLI not installed")
    IO.puts("Run: npm install -g @anthropic-ai/claude-code")

  e in CLIConnectionError ->
    IO.puts("Connection failed: #{e.message}")
    IO.puts("Working directory: #{e.cwd}")

  e in ProcessError ->
    IO.puts("Process error: #{e.message}")
    IO.puts("Exit code: #{e.exit_code}")
end
```

---

## Summary

The Elixir Claude Agent SDK provides all features of the Python SDK plus additional Elixir-specific features:

### Shared Features (Python Parity)

- **Streaming query interface** via `ClaudeAgentSDK.query/2`
- **Interactive client** via `ClaudeAgentSDK.Client` GenServer
- **Hook system** for pre/post tool use interception
- **Permission system** for fine-grained authorization
- **MCP server support** via `create_sdk_mcp_server/1`
- **Control protocol** for bidirectional communication
- **Comprehensive error handling**

### Elixir-only Features

- **AuthManager** - Automatic token management with refresh
- **SessionStore** - Persistent session storage with search
- **Orchestrator** - Parallel queries, pipelines, and retry logic
- **Agent configuration** - Named agent presets with switching
- **File checkpointing** - Rewind file changes to checkpoints
- **User switching** - Run CLI as different user

For more information, see the [official documentation](https://docs.anthropic.com/en/docs/claude-code/sdk).
