# Hooks Guide

Hooks are callback functions that allow you to intercept and control Claude Agent SDK execution at specific lifecycle events. They provide a powerful mechanism for implementing security policies, audit logging, context injection, and custom execution logic.

## Table of Contents

1. [What Are Hooks and Why Use Them](#what-are-hooks-and-why-use-them)
2. [Hook Events](#hook-events)
3. [Matcher Configuration](#matcher-configuration)
4. [Hook Callback Signature and Parameters](#hook-callback-signature-and-parameters)
5. [Output Module](#output-module)
6. [Security Hook Examples](#security-hook-examples)
7. [Audit Logging Examples](#audit-logging-examples)
8. [Context Injection Examples](#context-injection-examples)
9. [Combining Hooks with Streaming](#combining-hooks-with-streaming)
10. [Best Practices](#best-practices)

---

## What Are Hooks and Why Use Them

Hooks are functions invoked by the Claude Code CLI at specific moments during agent execution. They enable you to:

- **Intercept tool calls** before and after execution
- **Implement security policies** to block dangerous operations
- **Add contextual information** automatically to conversations
- **Create audit trails** of all agent activity
- **Control execution flow** based on runtime conditions
- **Monitor and observe** agent behavior

### Basic Hook Configuration

```elixir
alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Define a hook callback
def my_hook(input, tool_use_id, context) do
  IO.puts("Tool #{input["tool_name"]} called")
  Output.allow()
end

# Configure hooks in options
options = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&my_hook/3])
    ]
  },
  model: "haiku",
  max_turns: 5
}

# Start client with hooks
{:ok, client} = Client.start_link(options)
```

When hooks are configured, the SDK automatically uses the control protocol transport which enables bidirectional communication with the CLI for hook callbacks.

---

## Hook Events

The SDK supports six hook event types, each triggered at specific moments:

| Event | Description | Common Use Cases |
|-------|-------------|------------------|
| `:pre_tool_use` | Before a tool executes | Security validation, permission checks |
| `:post_tool_use` | After a tool executes | Audit logging, result processing |
| `:user_prompt_submit` | When user submits a prompt | Context injection, preprocessing |
| `:stop` | When the agent finishes | Finalization, reporting |
| `:subagent_stop` | When a subagent finishes | Subagent result processing |
| `:pre_compact` | Before context compaction | Preserve important context |

Note: `SessionStart`, `SessionEnd`, and `Notification` are not supported by the Python SDK and are rejected during validation.

### Event Configuration Examples

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

hooks = %{
  # Security check before tool execution
  pre_tool_use: [
    Matcher.new("Bash", [&check_bash_command/3]),
    Matcher.new("Write|Edit", [&check_file_access/3])
  ],

  # Audit logging after tool execution
  post_tool_use: [
    Matcher.new("*", [&log_tool_result/3])
  ],

  # Context injection on prompt submit
  user_prompt_submit: [
    Matcher.new(nil, [&add_project_context/3])
  ]
}
```

### Converting Between Event Formats

The SDK provides utilities for converting between Elixir atoms and CLI string formats:

```elixir
alias ClaudeAgentSDK.Hooks

# Atom to string
Hooks.event_to_string(:pre_tool_use)   # => "PreToolUse"
Hooks.event_to_string(:post_tool_use)  # => "PostToolUse"
Hooks.event_to_string(:user_prompt_submit)  # => "UserPromptSubmit"

# String to atom
Hooks.string_to_event("PreToolUse")    # => :pre_tool_use
Hooks.string_to_event("PostToolUse")   # => :post_tool_use

# Get all valid events
Hooks.all_valid_events()
# => [:pre_tool_use, :post_tool_use, :user_prompt_submit, :stop, :subagent_stop, :pre_compact]
```

---

## Matcher Configuration

Matchers determine which hooks run for which tools. The `Matcher` module supports several matching patterns:

### Exact Tool Matching

Match a specific tool by name:

```elixir
alias ClaudeAgentSDK.Hooks.Matcher

# Only matches the Bash tool
Matcher.new("Bash", [&check_bash/3])

# Only matches the Write tool
Matcher.new("Write", [&check_write/3])
```

### Regex Pattern Matching

Match multiple tools using regex patterns:

```elixir
# Match Write OR Edit tools
Matcher.new("Write|Edit", [&check_file_modification/3])

# Match Read OR Glob OR Grep tools (file reading operations)
Matcher.new("Read|Glob|Grep", [&audit_file_access/3])
```

### Wildcard Matching

Match all tools using `"*"` or `nil`:

```elixir
# Match all tools (both syntaxes are equivalent)
Matcher.new("*", [&log_all_tools/3])
Matcher.new(nil, [&log_all_tools/3])
```

### Multiple Callbacks Per Matcher

A single matcher can invoke multiple callbacks in sequence:

```elixir
# Both callbacks run for every Bash command
Matcher.new("Bash", [
  &security_check/3,   # First: security validation
  &audit_log/3         # Second: logging
])
```

### Matcher Timeout Configuration

Set a per-matcher timeout for callback execution:

```elixir
# Timeout after 5 seconds (minimum is 1000ms; sent to CLI as seconds)
Matcher.new("Bash", [&slow_check/3], timeout_ms: 5000)

# Timeout after 30 seconds for expensive operations
Matcher.new("*", [&expensive_analysis/3], timeout_ms: 30_000)
```

The SDK converts `timeout_ms` to seconds in the control initialization payload to match the CLI's expected units.

### Complete Matcher Examples

```elixir
alias ClaudeAgentSDK.Hooks.Matcher

hooks = %{
  pre_tool_use: [
    # High-priority security check on Bash with short timeout
    Matcher.new("Bash", [&block_dangerous_commands/3], timeout_ms: 2000),

    # File operation validation
    Matcher.new("Write|Edit", [&validate_file_path/3, &check_file_size/3]),

    # General logging for all tools
    Matcher.new("*", [&log_tool_invocation/3])
  ],

  post_tool_use: [
    # Audit all tool completions
    Matcher.new("*", [&audit_tool_completion/3])
  ]
}
```

---

## Hook Callback Signature and Parameters

Every hook callback must follow this signature:

```elixir
@spec callback(input :: map(), tool_use_id :: String.t() | nil, context :: map()) :: Output.t()
```

### Parameters

#### `input` - Hook Input Data

The input map varies by event type but always includes:

```elixir
%{
  "hook_event_name" => "PreToolUse",   # String event name
  "session_id" => "abc123",            # Session identifier
  "transcript_path" => "/path/to/...", # Path to conversation transcript
  "cwd" => "/current/working/dir"      # Current working directory
}
```

**Event-specific fields:**

| Event | Additional Fields |
|-------|-------------------|
| `:pre_tool_use` | `tool_name`, `tool_input` |
| `:post_tool_use` | `tool_name`, `tool_input`, `tool_response` |
| `:user_prompt_submit` | `prompt` |
| `:stop`, `:subagent_stop` | `stop_hook_active` |
| `:pre_compact` | `trigger`, `custom_instructions` |

#### `tool_use_id` - Tool Invocation ID

For tool-related hooks (`:pre_tool_use`, `:post_tool_use`), this is a unique identifier for the specific tool invocation. For other events, it may be `nil`.

#### `context` - Execution Context

Contains runtime context information:

```elixir
%{
  signal: %AbortSignal{}  # Optional abort signal for cooperative cancellation
}
```

### Example Callback Implementations

```elixir
defmodule MyHooks do
  alias ClaudeAgentSDK.Hooks.Output

  # PreToolUse: Check tool before execution
  def check_bash(input, tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => command}} ->
        IO.puts("Checking command: #{command}")
        IO.puts("Tool use ID: #{tool_use_id}")

        if String.contains?(command, "rm -rf") do
          Output.deny("Dangerous command blocked")
        else
          Output.allow()
        end

      _ ->
        # Not a Bash command, pass through
        %{}
    end
  end

  # PostToolUse: Log results after execution
  def log_result(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    response = input["tool_response"]
    is_error = get_in(response, ["is_error"]) || false

    status = if is_error, do: "FAILED", else: "SUCCESS"
    IO.puts("[AUDIT] #{tool_name} (#{tool_use_id}): #{status}")

    # Don't modify behavior, just log
    %{}
  end

  # UserPromptSubmit: Add context before processing
  def add_context(_input, _tool_use_id, _context) do
    context = """
    Current time: #{DateTime.utc_now()}
    Environment: #{System.get_env("MIX_ENV", "dev")}
    """

    Output.add_context("UserPromptSubmit", context)
  end
end
```

---

## Output Module

The `ClaudeAgentSDK.Hooks.Output` module provides helper functions for constructing hook responses.

### Permission Decisions (PreToolUse)

#### `Output.allow/0` and `Output.allow/1`

Allow the tool to execute:

```elixir
alias ClaudeAgentSDK.Hooks.Output

# Simple allow
Output.allow()

# Allow with reason
Output.allow("Security check passed")

# Returns:
# %{
#   hookSpecificOutput: %{
#     hookEventName: "PreToolUse",
#     permissionDecision: "allow",
#     permissionDecisionReason: "Security check passed"
#   }
# }
```

#### `Output.deny/1`

Block the tool from executing:

```elixir
Output.deny("Dangerous command detected")

# Returns:
# %{
#   hookSpecificOutput: %{
#     hookEventName: "PreToolUse",
#     permissionDecision: "deny",
#     permissionDecisionReason: "Dangerous command detected"
#   }
# }
```

#### `Output.ask/1`

Prompt the user for confirmation:

```elixir
Output.ask("This will delete 100 files. Continue?")

# Returns:
# %{
#   hookSpecificOutput: %{
#     hookEventName: "PreToolUse",
#     permissionDecision: "ask",
#     permissionDecisionReason: "This will delete 100 files. Continue?"
#   }
# }
```

### Context Injection

#### `Output.add_context/2`

Add contextual information for Claude:

```elixir
# For UserPromptSubmit
Output.add_context("UserPromptSubmit", "Current user: admin")

# For PostToolUse
Output.add_context("PostToolUse", "Command completed in 2.3 seconds")

# For SessionStart
Output.add_context("SessionStart", "Active issues: #123, #456")
```

### Execution Control

#### `Output.stop/1`

Stop agent execution entirely:

```elixir
Output.stop("Critical error: resource limit exceeded")

# Returns:
# %{continue: false, stopReason: "Critical error: resource limit exceeded"}
```

#### `Output.continue/0`

Explicitly continue execution:

```elixir
Output.continue()

# Returns:
# %{continue: true}
```

#### `Output.block/1`

Block with feedback to Claude:

```elixir
Output.block("Tool execution failed validation")

# Returns:
# %{decision: "block", reason: "Tool execution failed validation"}
```

### Output Modifiers

Chain modifiers to add additional information:

#### `Output.with_system_message/2`

Add a user-visible message (not shown to Claude):

```elixir
Output.deny("Command blocked")
|> Output.with_system_message("Security policy violation detected")
```

#### `Output.with_reason/2`

Add a Claude-visible explanation:

```elixir
Output.deny("Path not allowed")
|> Output.with_reason("File path must be within /allowed directory")
```

#### `Output.suppress_output/1`

Hide the output from the transcript:

```elixir
Output.allow()
|> Output.suppress_output()
```

### Complete Output Examples

```elixir
alias ClaudeAgentSDK.Hooks.Output

# Security denial with full context
Output.deny("Dangerous command blocked")
|> Output.with_system_message("Security policy violation")
|> Output.with_reason("Command matches blocked pattern: rm -rf")

# Allow with logging suppression
Output.allow("Approved by policy")
|> Output.suppress_output()

# Context injection with system message
Output.add_context("UserPromptSubmit", "Project: my-app, Branch: main")
|> Output.with_system_message("Context injected")
```

---

## Security Hook Examples

### Blocking Dangerous Bash Commands

```elixir
defmodule SecurityHooks do
  alias ClaudeAgentSDK.Hooks.Output

  @dangerous_patterns [
    "rm -rf",
    "dd if=",
    "mkfs",
    "> /dev/",
    "chmod 777",
    "sudo",
    ":(){:|:&};:"  # Fork bomb
  ]

  def check_bash_command(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => command}} ->
        if dangerous_command?(command) do
          Output.deny("Dangerous command blocked: #{summarize(command)}")
          |> Output.with_system_message("Security policy violation")
          |> Output.with_reason("Command matches blocked pattern")
        else
          Output.allow("Security check passed")
        end

      _ ->
        %{}  # Not a Bash command
    end
  end

  defp dangerous_command?(command) do
    Enum.any?(@dangerous_patterns, &String.contains?(command, &1))
  end

  defp summarize(command) do
    if String.length(command) > 50 do
      String.slice(command, 0, 47) <> "..."
    else
      command
    end
  end
end

# Usage
hooks = %{
  pre_tool_use: [
    Matcher.new("Bash", [&SecurityHooks.check_bash_command/3])
  ]
}
```

### File Access Control

```elixir
defmodule FileSecurityHooks do
  alias ClaudeAgentSDK.Hooks.Output

  @forbidden_files [".env", "secrets.yml", "credentials.json", ".ssh/"]
  @allowed_directories ["/tmp/sandbox", "/home/user/project"]

  def check_file_access(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => tool, "tool_input" => %{"file_path" => path}}
      when tool in ["Write", "Edit", "Read"] ->
        cond do
          forbidden_file?(path) ->
            Output.deny("Cannot access sensitive file: #{Path.basename(path)}")
            |> Output.with_system_message("Access denied: sensitive file")

          not in_allowed_directory?(path) ->
            Output.deny("File path outside allowed directories")
            |> Output.with_reason("Must operate within: #{inspect(@allowed_directories)}")

          true ->
            Output.allow("File access permitted")
        end

      _ ->
        %{}
    end
  end

  defp forbidden_file?(path) do
    Enum.any?(@forbidden_files, fn pattern ->
      String.contains?(path, pattern)
    end)
  end

  defp in_allowed_directory?(path) do
    Enum.any?(@allowed_directories, fn dir ->
      String.starts_with?(Path.expand(path), Path.expand(dir))
    end)
  end
end

# Usage
hooks = %{
  pre_tool_use: [
    Matcher.new("Write|Edit|Read", [&FileSecurityHooks.check_file_access/3])
  ]
}
```

### Rate Limiting

```elixir
defmodule RateLimitHooks do
  alias ClaudeAgentSDK.Hooks.Output

  @max_calls_per_minute 10
  @ets_table :rate_limit_hooks

  def init_table do
    :ets.new(@ets_table, [:named_table, :public, :set])
  end

  def check_rate_limit(input, _tool_use_id, _context) do
    tool_name = input["tool_name"]
    current_minute = div(System.system_time(:second), 60)
    key = {tool_name, current_minute}

    count = case :ets.lookup(@ets_table, key) do
      [{^key, n}] -> n
      _ -> 0
    end

    if count >= @max_calls_per_minute do
      Output.deny("Rate limit exceeded for #{tool_name}")
      |> Output.with_system_message("Please wait before using this tool again")
    else
      :ets.insert(@ets_table, {key, count + 1})
      Output.allow()
    end
  end
end

# Usage
RateLimitHooks.init_table()
hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&RateLimitHooks.check_rate_limit/3])
  ]
}
```

---

## Audit Logging Examples

### Comprehensive Tool Audit Trail

```elixir
defmodule AuditHooks do
  alias ClaudeAgentSDK.Hooks.Output

  @log_file "/var/log/claude_audit.log"

  def log_tool_invocation(input, tool_use_id, _context) do
    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: "tool_invocation",
      tool: input["tool_name"],
      tool_use_id: tool_use_id,
      session_id: input["session_id"],
      input: input["tool_input"]
    }

    write_log(entry)

    # Don't modify behavior
    %{}
  end

  def log_tool_completion(input, tool_use_id, _context) do
    response = input["tool_response"]
    is_error = get_in(response, ["is_error"]) || false

    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: "tool_completion",
      tool: input["tool_name"],
      tool_use_id: tool_use_id,
      session_id: input["session_id"],
      status: if(is_error, do: "error", else: "success")
    }

    write_log(entry)

    # Don't modify behavior
    %{}
  end

  defp write_log(entry) do
    json = Jason.encode!(entry)
    File.write!(@log_file, json <> "\n", [:append])
  end
end

# Usage
hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&AuditHooks.log_tool_invocation/3])
  ],
  post_tool_use: [
    Matcher.new("*", [&AuditHooks.log_tool_completion/3])
  ]
}
```

### Conversation Lifecycle Logging

```elixir
defmodule SessionAuditHooks do
  def log_stop(input, _tool_use_id, _context) do
    session_id = input["session_id"]
    IO.puts("[AUDIT] Session #{session_id} ended at #{DateTime.utc_now()}")
    %{}
  end

  def log_prompt_submit(input, _tool_use_id, _context) do
    prompt = input["prompt"] || ""
    truncated = String.slice(prompt, 0, 100)
    IO.puts("[AUDIT] Prompt submitted: #{truncated}...")
    %{}
  end
end

# Usage
hooks = %{
  user_prompt_submit: [
    Matcher.new(nil, [&SessionAuditHooks.log_prompt_submit/3])
  ],
  stop: [
    Matcher.new(nil, [&SessionAuditHooks.log_stop/3])
  ]
}
```

### ETS-Based Metrics Collection

```elixir
defmodule MetricsHooks do
  @table :claude_metrics

  def init do
    :ets.new(@table, [:named_table, :public, :set])
  end

  def track_tool_use(input, _tool_use_id, _context) do
    tool = input["tool_name"]
    :ets.update_counter(@table, {:tool_count, tool}, {2, 1}, {{:tool_count, tool}, 0})
    :ets.update_counter(@table, :total_tools, {2, 1}, {:total_tools, 0})
    %{}
  end

  def track_tool_error(input, _tool_use_id, _context) do
    response = input["tool_response"]
    is_error = get_in(response, ["is_error"]) || false

    if is_error do
      tool = input["tool_name"]
      :ets.update_counter(@table, {:error_count, tool}, {2, 1}, {{:error_count, tool}, 0})
    end

    %{}
  end

  def get_metrics do
    %{
      total_tools: get_counter(:total_tools),
      tool_counts: get_all_tool_counts(),
      error_counts: get_all_error_counts()
    }
  end

  defp get_counter(key) do
    case :ets.lookup(@table, key) do
      [{^key, n}] -> n
      _ -> 0
    end
  end

  defp get_all_tool_counts do
    :ets.match(@table, {{:tool_count, :"$1"}, :"$2"})
    |> Enum.map(fn [tool, count] -> {tool, count} end)
    |> Map.new()
  end

  defp get_all_error_counts do
    :ets.match(@table, {{:error_count, :"$1"}, :"$2"})
    |> Enum.map(fn [tool, count] -> {tool, count} end)
    |> Map.new()
  end
end

# Usage
MetricsHooks.init()
hooks = %{
  pre_tool_use: [Matcher.new("*", [&MetricsHooks.track_tool_use/3])],
  post_tool_use: [Matcher.new("*", [&MetricsHooks.track_tool_error/3])]
}

# Later: get metrics
MetricsHooks.get_metrics()
# => %{total_tools: 42, tool_counts: %{"Bash" => 15, "Read" => 27}, error_counts: %{"Bash" => 2}}
```

---

## Context Injection Examples

### Project Information Injection

```elixir
defmodule ContextHooks do
  alias ClaudeAgentSDK.Hooks.Output

  def add_project_context(_input, _tool_use_id, _context) do
    git_branch = get_git_branch()
    environment = System.get_env("MIX_ENV", "dev")

    context = """
    ## Project Context (Auto-Injected)

    - **Timestamp:** #{DateTime.utc_now() |> DateTime.to_iso8601()}
    - **Environment:** #{environment}
    - **Git Branch:** #{git_branch}
    - **Working Directory:** #{File.cwd!()}
    """

    Output.add_context("UserPromptSubmit", context)
  end

  defp get_git_branch do
    case System.cmd("git", ["branch", "--show-current"], stderr_to_stdout: true) do
      {branch, 0} -> String.trim(branch)
      _ -> "unknown"
    end
  end
end

# Usage
hooks = %{
  user_prompt_submit: [
    Matcher.new(nil, [&ContextHooks.add_project_context/3])
  ]
}
```

### Database Context Injection

```elixir
defmodule DatabaseContextHooks do
  alias ClaudeAgentSDK.Hooks.Output

  def add_database_schema(_input, _tool_use_id, _context) do
    # In a real app, query your database for schema info
    schema_info = """
    ## Database Schema Context

    ### Users Table
    - id: integer (primary key)
    - email: string (unique)
    - name: string
    - created_at: datetime

    ### Posts Table
    - id: integer (primary key)
    - user_id: integer (foreign key -> users.id)
    - title: string
    - content: text
    - published_at: datetime
    """

    Output.add_context("UserPromptSubmit", schema_info)
  end
end
```

### Dynamic Tool Result Enhancement

```elixir
defmodule ResultEnhancementHooks do
  alias ClaudeAgentSDK.Hooks.Output

  def enhance_bash_result(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_response" => response} ->
        duration = calculate_duration()

        context = """
        [Hook Note] Command execution took #{duration}ms.
        Exit code: #{get_exit_code(response)}
        """

        Output.add_context("PostToolUse", context)

      _ ->
        %{}
    end
  end

  defp calculate_duration do
    # In practice, measure actual duration
    :rand.uniform(1000)
  end

  defp get_exit_code(response) do
    get_in(response, ["exit_code"]) || 0
  end
end

# Usage
hooks = %{
  post_tool_use: [
    Matcher.new("Bash", [&ResultEnhancementHooks.enhance_bash_result/3])
  ]
}
```

---

## Combining Hooks with Streaming

When using hooks with the streaming API, the SDK automatically uses the control client transport. Here is a complete example:

```elixir
defmodule StreamingWithHooks do
  alias ClaudeAgentSDK.{Client, ContentExtractor, Message, Options}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output}

  def run do
    # Define hooks
    hooks = %{
      pre_tool_use: [
        Matcher.new("Bash", [&check_bash/3]),
        Matcher.new("*", [&log_tool/3])
      ],
      post_tool_use: [
        Matcher.new("*", [&log_result/3])
      ],
      user_prompt_submit: [
        Matcher.new(nil, [&add_context/3])
      ]
    }

    # Configure options with hooks
    options = %Options{
      tools: ["Bash", "Read"],
      allowed_tools: ["Bash", "Read"],
      hooks: hooks,
      model: "haiku",
      max_turns: 3,
      permission_mode: :default
    }

    # Start client
    {:ok, client} = Client.start_link(options)

    # Stream messages asynchronously
    task = Task.async(fn ->
      Client.stream_messages(client)
      |> Enum.reduce_while([], fn message, acc ->
        case message do
          %Message{type: :assistant} = msg ->
            text = ContentExtractor.extract_text(msg)
            if text && text != "", do: IO.write(text)
            {:cont, [message | acc]}

          %Message{type: :result} ->
            {:halt, Enum.reverse([message | acc])}

          _ ->
            {:cont, [message | acc]}
        end
      end)
    end)

    # Send message and wait for response
    Process.sleep(50)
    :ok = Client.send_message(client, "Run: echo 'Hello from streaming with hooks!'")
    messages = Task.await(task, 120_000)

    # Cleanup
    Client.stop(client)

    messages
  end

  # Hook callbacks
  def check_bash(input, _id, _ctx) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
        if String.contains?(cmd, "rm -rf") do
          Output.deny("Blocked dangerous command")
        else
          Output.allow()
        end
      _ -> %{}
    end
  end

  def log_tool(input, id, _ctx) do
    IO.puts("\n[Hook] Tool invoked: #{input["tool_name"]} (#{id})")
    %{}
  end

  def log_result(input, id, _ctx) do
    IO.puts("[Hook] Tool completed: #{input["tool_name"]} (#{id})")
    %{}
  end

  def add_context(_input, _id, _ctx) do
    Output.add_context("UserPromptSubmit", "Environment: #{Mix.env()}")
  end
end

# Run the example
StreamingWithHooks.run()
```

### Using with Streaming.start_session

You can also use hooks with the `Streaming` module:

```elixir
alias ClaudeAgentSDK.{Streaming, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

hooks = %{
  pre_tool_use: [Matcher.new("*", [&my_hook/3])]
}

options = %Options{
  hooks: hooks,
  model: "haiku",
  max_turns: 2
}

# Hooks are automatically active in the session
{:ok, session} = Streaming.start_session(options)

Streaming.send_message(session, "Hello!")
|> Enum.each(fn
  %{type: :text_delta, text: text} -> IO.write(text)
  %{type: :message_stop} -> IO.puts("")
  _ -> :ok
end)

Streaming.close_session(session)
```

---

## Best Practices

### 1. Keep Hooks Fast

Hooks are executed synchronously and can impact response latency. Keep expensive operations to a minimum:

```elixir
# Good: Fast, synchronous check
def fast_check(input, _id, _ctx) do
  if input["tool_name"] == "Bash" and dangerous?(input) do
    Output.deny("Blocked")
  else
    Output.allow()
  end
end

# Bad: Slow HTTP call in hook
def slow_check(input, _id, _ctx) do
  # This blocks the entire agent!
  HTTPoison.post!("https://api.example.com/check", input)
  Output.allow()
end
```

For slow operations, consider:
- Using ETS for fast lookups
- Pre-loading data at startup
- Using async logging (write to queue, process separately)

### 2. Use Appropriate Matcher Specificity

Match only the tools you need to handle:

```elixir
# Good: Only processes Bash commands
Matcher.new("Bash", [&check_bash/3])

# Wasteful: Runs for every tool but only handles Bash
Matcher.new("*", [fn input, _, _ ->
  if input["tool_name"] == "Bash" do
    # ...
  else
    %{}
  end
end])
```

### 3. Handle All Cases Gracefully

Always return a valid output, even for unexpected input:

```elixir
def robust_hook(input, _id, _ctx) do
  case input do
    %{"tool_name" => "Bash", "tool_input" => %{"command" => command}}
    when is_binary(command) ->
      # Handle the expected case
      check_command(command)

    %{"tool_name" => "Bash"} ->
      # Missing or malformed tool_input
      Output.deny("Invalid Bash input")

    _ ->
      # Not our tool, pass through
      %{}
  end
end
```

### 4. Use ETS for Stateful Hooks

When hooks need to maintain state (counters, caches, etc.), use ETS:

```elixir
defmodule StatefulHooks do
  @table :hook_state

  def init do
    :ets.new(@table, [:named_table, :public, :set])
  end

  def counting_hook(input, _id, _ctx) do
    tool = input["tool_name"]
    :ets.update_counter(@table, {:count, tool}, {2, 1}, {{:count, tool}, 0})
    %{}
  end

  def get_counts do
    :ets.match(@table, {{:count, :"$1"}, :"$2"})
    |> Map.new(fn [k, v] -> {k, v} end)
  end
end
```

### 5. Layer Security Hooks

Apply multiple layers of security validation:

```elixir
hooks = %{
  pre_tool_use: [
    # Layer 1: Audit logging (always runs)
    Matcher.new("*", [&audit_log/3]),

    # Layer 2: Rate limiting
    Matcher.new("*", [&check_rate_limit/3]),

    # Layer 3: Tool-specific security
    Matcher.new("Bash", [&check_bash_security/3]),
    Matcher.new("Write|Edit", [&check_file_security/3])
  ]
}
```

### 6. Test Hooks in Isolation

Test hook logic separately from the SDK:

```elixir
defmodule SecurityHooksTest do
  use ExUnit.Case

  alias MyApp.SecurityHooks
  alias ClaudeAgentSDK.Hooks.Output

  test "blocks rm -rf commands" do
    input = %{
      "tool_name" => "Bash",
      "tool_input" => %{"command" => "rm -rf /"}
    }

    result = SecurityHooks.check_bash(input, "test-id", %{})

    assert result.hookSpecificOutput.permissionDecision == "deny"
  end

  test "allows safe commands" do
    input = %{
      "tool_name" => "Bash",
      "tool_input" => %{"command" => "echo hello"}
    }

    result = SecurityHooks.check_bash(input, "test-id", %{})

    assert result.hookSpecificOutput.permissionDecision == "allow"
  end
end
```

### 7. Clean Up Resources

Always clean up ETS tables and other resources:

```elixir
# In your application supervision tree or test setup
def start_hooks do
  :ets.new(:my_hook_table, [:named_table, :public, :set])
end

def stop_hooks do
  if :ets.whereis(:my_hook_table) != :undefined do
    :ets.delete(:my_hook_table)
  end
end
```

### 8. Validate Hook Configuration

Use the SDK's validation before using hooks:

```elixir
alias ClaudeAgentSDK.Hooks

hooks = %{
  pre_tool_use: [Matcher.new("Bash", [&my_hook/3])]
}

case Hooks.validate_config(hooks) do
  :ok ->
    # Configuration is valid
    {:ok, client} = Client.start_link(%Options{hooks: hooks})

  {:error, reason} ->
    IO.puts("Invalid hook configuration: #{reason}")
end
```

### 9. Document Your Hooks

Keep hooks well-documented for maintainability:

```elixir
defmodule MyApp.SecurityHooks do
  @moduledoc """
  Security hooks for Claude Agent SDK.

  ## Hooks

  - `check_bash_command/3` - Blocks dangerous Bash commands
  - `check_file_access/3` - Enforces file access policies

  ## Configuration

  Set `@allowed_directories` to control file access.
  Set `@dangerous_patterns` to add blocked command patterns.
  """

  @doc """
  PreToolUse hook that validates Bash commands.

  Blocks commands matching patterns in `@dangerous_patterns`.

  ## Examples

      iex> check_bash_command(%{"tool_name" => "Bash", "tool_input" => %{"command" => "rm -rf /"}}, nil, %{})
      %{hookSpecificOutput: %{permissionDecision: "deny", ...}}
  """
  def check_bash_command(input, tool_use_id, context) do
    # ...
  end
end
```

---

## Summary

Hooks provide a powerful mechanism for controlling Claude Agent SDK behavior:

| Use Case | Hook Event | Key Functions |
|----------|------------|---------------|
| Security validation | `:pre_tool_use` | `Output.allow/0`, `Output.deny/1` |
| Audit logging | `:pre_tool_use`, `:post_tool_use` | Return `%{}` |
| Context injection | `:user_prompt_submit`, `:pre_compact` | `Output.add_context/2` |
| Rate limiting | `:pre_tool_use` | ETS counters + `Output.deny/1` |
| Execution control | Any | `Output.stop/1`, `Output.continue/0` |

Key modules:
- `ClaudeAgentSDK.Hooks` - Event types and validation
- `ClaudeAgentSDK.Hooks.Matcher` - Tool pattern matching
- `ClaudeAgentSDK.Hooks.Output` - Response builders

For more examples, see the `examples/hooks/` directory in the SDK source.
