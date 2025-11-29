# Claude Code Hooks Guide

**Version:** 0.3.0
**Status:** ✅ Implemented

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Hook Events](#hook-events)
4. [Hook Output](#hook-output)
5. [Examples](#examples)
6. [Best Practices](#best-practices)
7. [API Reference](#api-reference)

---

## Overview

Claude Code Hooks are callback functions that execute at specific lifecycle events during Claude's agent loop. Unlike tools (which Claude invokes), hooks are invoked by the Claude Code CLI itself, enabling:

- **Security & Validation**: Block dangerous operations before they execute
- **Context Injection**: Automatically add relevant information
- **Audit & Logging**: Track all tool usage comprehensively
- **Policy Enforcement**: Implement organizational rules
- **Monitoring**: Observe agent behavior in real-time

### Key Characteristics

- **Synchronous execution**: Hooks block the agent loop until complete
- **Bidirectional control**: Can approve, deny, or modify behavior
- **Pattern-based matching**: Target specific tools or all tools
- **Not visible to Claude**: Infrastructure-level callbacks
- **Timeouts**: 60-second default per matcher (`timeout_ms`, minimum 1s)

---

## Quick Start

### Installation

Hooks are included in `claude_agent_sdk` v0.3.0+:

```elixir
def deps do
  [
    {:claude_agent_sdk, "~> 0.3.0"}
  ]
end
```

### Basic Example

```elixir
alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Define a hook callback
def check_bash_command(input, _tool_use_id, _context) do
  case input do
    %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
      if String.contains?(cmd, "rm -rf") do
        Output.deny("Dangerous command blocked")
      else
        Output.allow()
      end
    _ -> %{}
  end
end

# Configure hooks
options = %Options{
  allowed_tools: ["Bash"],
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&check_bash_command/3])
    ]
  }
}

# Start client with hooks
{:ok, client} = Client.start_link(options)

# Send message
Client.send_message(client, "Run: rm -rf /tmp/data")

# Receive messages (hook will block the dangerous command!)
Client.stream_messages(client)
|> Enum.each(&IO.inspect/1)

# Stop client
Client.stop(client)
```

Each matcher can set `timeout_ms` when you need a different execution window; the default is 60_000 ms with a 1-second floor and is shared with the CLI during initialization.

---

## Hook Events

### PreToolUse

**When**: Before a tool executes
**Use Cases**: Security validation, input transformation, auto-approval
**Special Output**: Permission decisions (`allow`, `deny`, `ask`)

```elixir
def pre_tool_use_hook(input, tool_use_id, context) do
  tool_name = input["tool_name"]
  tool_input = input["tool_input"]

  # Validate and return decision
  Output.allow("Validation passed")
  # or
  Output.deny("Validation failed")
  # or
  Output.ask("User confirmation needed")
end
```

**Input Fields**:
- `tool_name` - Tool being invoked (e.g., "Bash", "Write")
- `tool_input` - Tool parameters
- `session_id` - Current session ID
- `transcript_path` - Path to conversation log
- `cwd` - Current working directory

### PostToolUse

**When**: After a tool completes successfully
**Use Cases**: Result validation, context injection, monitoring
**Special Output**: Additional context for Claude

```elixir
def post_tool_use_hook(input, tool_use_id, context) do
  tool_name = input["tool_name"]
  tool_response = input["tool_response"]

  # Add context about execution
  Output.add_context("PostToolUse", "Execution took 2.3s")
end
```

**Input Fields**:
- `tool_name` - Tool that executed
- `tool_input` - Original tool parameters
- `tool_response` - Tool execution result
- (plus common fields)

### UserPromptSubmit

**When**: When user submits a prompt
**Use Cases**: Context injection, prompt validation
**Special Output**: Additional context, prompt blocking

```elixir
def user_prompt_submit_hook(input, _tool_use_id, context) do
  prompt = input["prompt"]

  # Add current project context
  context_text = """
  Current time: #{DateTime.utc_now()}
  Git branch: #{get_current_branch()}
  """

  Output.add_context("UserPromptSubmit", context_text)
end
```

**Input Fields**:
- `prompt` - User's submitted prompt text
- (plus common fields)

### Stop

**When**: When the agent finishes responding
**Use Cases**: Session summary, force continuation
**Special Output**: Block stop, continue execution

```elixir
def stop_hook(input, _tool_use_id, context) do
  stop_hook_active = input["stop_hook_active"]

  # Force continuation for multi-step workflow
  if should_continue?(input) and not stop_hook_active do
    Output.block("Continue to next step")
  else
    %{}
  end
end
```

**Input Fields**:
- `stop_hook_active` - Whether stop hook already triggered (prevent infinite loops)
- (plus common fields)

### SubagentStop

**When**: When a subagent (Task tool) finishes
**Use Cases**: Subagent result validation, chaining
**Special Output**: Block stop, continue execution

Similar to Stop hook but for subagents.

### PreCompact

**When**: Before context compaction (auto or manual)
**Use Cases**: Save state, log compaction events
**Special Output**: None (informational only)

```elixir
def pre_compact_hook(input, _tool_use_id, context) do
  trigger = input["trigger"]  # "auto" or "manual"
  custom_instructions = input["custom_instructions"]

  # Log compaction event
  Logger.info("Compaction triggered: #{trigger}")

  %{}
end
```

**Input Fields**:
- `trigger` - "auto" or "manual"
- `custom_instructions` - User-provided instructions (for manual compact)
- (plus common fields)

---

## Hook Output

Hooks return maps with control fields. Use the `Output` module helpers for type-safe construction.

### Permission Decisions (PreToolUse)

```elixir
# Allow with reason
Output.allow("Security check passed")

# Deny with reason
Output.deny("Command blocked by policy")

# Ask user for confirmation
Output.ask("Confirm deletion of 100 files")
```

Generated output:
```elixir
%{
  hookSpecificOutput: %{
    hookEventName: "PreToolUse",
    permissionDecision: "allow",  # or "deny", "ask"
    permissionDecisionReason: "Security check passed"
  }
}
```

### Add Context (PostToolUse, UserPromptSubmit)

```elixir
Output.add_context("PostToolUse", "Command took 2.3 seconds")
```

Generated output:
```elixir
%{
  hookSpecificOutput: %{
    hookEventName: "PostToolUse",
    additionalContext: "Command took 2.3 seconds"
  }
}
```

### Stop Execution

```elixir
Output.stop("Critical error detected")
```

Generated output:
```elixir
%{
  continue: false,
  stopReason: "Critical error detected"
}
```

### Block with Feedback (Stop, SubagentStop, PostToolUse)

```elixir
Output.block("Must complete verification step")
```

Generated output:
```elixir
%{
  decision: "block",
  reason: "Must complete verification step"
}
```

### Helper Combinators

```elixir
# Combine multiple fields
Output.deny("Invalid path")
|> Output.with_system_message("🔒 Access denied")
|> Output.with_reason("Path outside allowed directory")
|> Output.suppress_output()
```

Generated output:
```elixir
%{
  hookSpecificOutput: %{
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Invalid path"
  },
  systemMessage: "🔒 Access denied",
  reason: "Path outside allowed directory",
  suppressOutput: true
}
```

### Output Fields Reference

| Field | Type | Description | Visible To |
|-------|------|-------------|------------|
| `continue` | boolean | Whether to continue execution | CLI |
| `stopReason` | string | Message when stopping | User |
| `systemMessage` | string | User-visible message | User |
| `reason` | string | Claude-visible feedback | Claude |
| `suppressOutput` | boolean | Hide from transcript | CLI |
| `decision` | "block" | Block with feedback | Claude |
| `hookSpecificOutput` | map | Event-specific control | CLI + Claude |

---

## Examples

### Example 1: Security - Block Dangerous Commands

```elixir
defmodule SecurityHooks do
  def check_bash_command(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
        dangerous = ["rm -rf", "dd if=", "mkfs", "> /dev/"]

        if Enum.any?(dangerous, &String.contains?(cmd, &1)) do
          Output.deny("Dangerous command blocked: #{cmd}")
          |> Output.with_system_message("🔒 Security policy violation")
        else
          Output.allow()
        end
      _ -> %{}
    end
  end
end

# Use
hooks = %{
  pre_tool_use: [
    Matcher.new("Bash", [&SecurityHooks.check_bash_command/3])
  ]
}
```

### Example 2: File Access Policy

```elixir
defmodule FilePolicyHooks do
  @allowed_dir "/tmp/sandbox"
  @forbidden_files [".env", "secrets.yml"]

  def enforce_file_policy(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => tool, "tool_input" => %{"file_path" => path}}
      when tool in ["Write", "Edit"] ->
        cond do
          Enum.any?(@forbidden_files, &String.ends_with?(path, &1)) ->
            Output.deny("Cannot modify #{Path.basename(path)}")

          not String.starts_with?(path, @allowed_dir) ->
            Output.deny("Can only modify files in #{@allowed_dir}")

          true ->
            Output.allow()
        end
      _ -> %{}
    end
  end
end
```

### Example 3: Automatic Context Injection

```elixir
defmodule ContextHooks do
  def add_project_context(_input, _tool_use_id, _context) do
    context_text = """
    Current branch: #{get_git_branch()}
    Recent issues: #{get_recent_issues()}
    Last deploy: #{get_last_deploy()}
    """

    Output.add_context("UserPromptSubmit", context_text)
  end

  defp get_git_branch do
    {result, 0} = System.cmd("git", ["branch", "--show-current"])
    String.trim(result)
  end
end
```

### Example 4: Comprehensive Audit Logging

```elixir
defmodule AuditHooks do
  require Logger

  def log_tool_invocation(input, tool_use_id, _context) do
    Logger.info("Tool invoked",
      tool: input["tool_name"],
      tool_use_id: tool_use_id,
      session: input["session_id"]
    )

    write_audit_log(%{
      event: "tool_invocation",
      tool_name: input["tool_name"],
      tool_use_id: tool_use_id,
      timestamp: DateTime.utc_now()
    })

    %{}  # Don't modify behavior
  end

  def log_tool_result(input, tool_use_id, _context) do
    success = not get_in(input, ["tool_response", "is_error"])

    Logger.info("Tool completed",
      tool: input["tool_name"],
      tool_use_id: tool_use_id,
      success: success
    )

    %{}
  end
end

# Use
hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&AuditHooks.log_tool_invocation/3])
  ],
  post_tool_use: [
    Matcher.new("*", [&AuditHooks.log_tool_result/3])
  ]
}
```

---

## Best Practices

### 1. Idempotent Hooks

Hooks may be called multiple times. Design them to be idempotent:

```elixir
# ❌ Bad - accumulates on retry
def bad_hook(input, _tool_use_id, _context) do
  :ets.insert(:counters, {:calls, get_count() + 1})
  Output.allow()
end

# ✅ Good - idempotent
def good_hook(input, _tool_use_id, _context) do
  if valid?(input) do
    Output.allow()
  else
    Output.deny("Invalid input")
  end
end
```

### 2. Fast Execution

Hooks block the agent loop. Keep them fast (< 100ms ideal):

```elixir
# ❌ Bad - slow external call
def slow_hook(input, _tool_use_id, _context) do
  # This blocks for seconds
  result = HTTPoison.get!("https://api.example.com/validate")
  if result.status_code == 200, do: Output.allow(), else: Output.deny("Failed")
end

# ✅ Good - quick check
def fast_hook(input, _tool_use_id, _context) do
  # Fast local validation
  if valid_format?(input["tool_input"]) do
    Output.allow()
  else
    Output.deny("Invalid format")
  end
end

# ✅ Acceptable - async background logging
def async_logging_hook(input, tool_use_id, _context) do
  # Fire and forget
  Task.start(fn -> log_to_system(input, tool_use_id) end)
  %{}  # Return immediately
end
```

### 3. Error Handling

Handle errors gracefully to avoid breaking the agent loop:

```elixir
# ✅ Good - handles errors
def safe_hook(input, tool_use_id, _context) do
  try do
    # Hook logic
    validate_and_decide(input)
  rescue
    e ->
      Logger.error("Hook error: #{Exception.message(e)}")
      # Fail-open or fail-closed based on policy
      Output.allow("Hook error - defaulting to allow")
  end
end
```

### 4. Clear Feedback

Provide helpful messages for both users and Claude:

```elixir
# ❌ Bad - vague
Output.deny("No")

# ✅ Good - specific and actionable
Output.deny("Cannot delete production database")
|> Output.with_system_message("🚫 Production safety check failed")
|> Output.with_reason("""
  You attempted to delete the production database. This is blocked by policy.
  If you need to delete data, please use the staging environment instead.
""")
```

### 5. Matcher Patterns

Use specific matchers for better performance:

```elixir
# ❌ Inefficient - checks every tool
hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&check_only_bash/3])
  ]
}

# ✅ Efficient - targeted matcher
hooks = %{
  pre_tool_use: [
    Matcher.new("Bash", [&check_bash/3])
  ]
}

# ✅ Multiple tools
hooks = %{
  pre_tool_use: [
    Matcher.new("Write|Edit|MultiEdit", [&check_file_ops/3])
  ]
}
```

### 6. Prevent Infinite Loops

Check `stop_hook_active` in Stop/SubagentStop hooks:

```elixir
def stop_hook(input, _tool_use_id, _context) do
  # ✅ Good - prevents infinite continuation
  if input["stop_hook_active"] do
    %{}  # Already continuing, allow stop
  else
    if needs_more_work?(input) do
      Output.block("Continue to complete workflow")
    else
      %{}
    end
  end
end
```

---

## API Reference

### ClaudeAgentSDK.Hooks

Type definitions and utilities.

**Functions**:
- `event_to_string/1` - Convert atom to CLI string
- `string_to_event/1` - Convert CLI string to atom
- `all_valid_events/0` - List all valid events
- `validate_config/1` - Validate hook configuration

**Types**:
- `hook_event()` - Event atom (`:pre_tool_use`, etc.)
- `hook_input()` - Input map passed to callbacks
- `hook_context()` - Context map with abort signal
- `hook_callback()` - Callback function type
- `hook_config()` - Configuration map type

### ClaudeAgentSDK.Hooks.Matcher

Hook matcher for pattern-based filtering.

**Functions**:
- `new/3` - Create new matcher (`timeout_ms` opt, default 60s, min 1s)
- `to_cli_format/2` - Convert to CLI JSON format

**Fields**:
- `matcher` - Tool pattern (nil, "*", "Tool", "Tool1|Tool2")
- `hooks` - List of callback functions
- `timeout_ms` - Optional timeout (ms) sent during initialize

### ClaudeAgentSDK.Hooks.Output

Hook output helpers.

**Permission Decisions**:
- `allow/1` - Allow PreToolUse
- `deny/1` - Deny PreToolUse
- `ask/1` - Ask user for confirmation

**Context Injection**:
- `add_context/2` - Add context for Claude

**Execution Control**:
- `stop/1` - Stop execution with reason
- `block/1` - Block with feedback
- `continue/0` - Continue execution

**Combinators**:
- `with_system_message/2` - Add user message
- `with_reason/2` - Add Claude feedback
- `suppress_output/1` - Hide from transcript

**Utilities**:
- `validate/1` - Validate output structure
- `to_json_map/1` - Convert to JSON-compatible map

### ClaudeAgentSDK.Hooks.Registry

Internal registry for callback management.

**Functions**:
- `new/0` - Create empty registry
- `register/2` - Register callback, get ID
- `get_callback/2` - Look up callback by ID
- `get_id/2` - Look up ID by callback
- `all_callbacks/1` - Get all registered callbacks
- `count/1` - Count registered callbacks

---

## Limitations

### Not Supported in SDK Mode

The following hooks are **not available** when using the SDK (limitation of Claude CLI):

- `SessionStart` - Use initialization logic in your application instead
- `SessionEnd` - Use cleanup logic in your application instead
- `Notification` - Not applicable in SDK mode

These hooks only work in interactive CLI mode.

### Timeout

Hooks default to a 60-second timeout (minimum 1 second). Override it per matcher with `timeout_ms`—the value is shared with the CLI during initialization. If your hook still takes too long:

1. Optimize the hook logic
2. Move slow operations to background tasks
3. Return immediately and process asynchronously

---

## Debugging

### Enable Debug Logging

```elixir
# In config/dev.exs
config :logger, level: :debug

# In your hook
def debug_hook(input, tool_use_id, context) do
  require Logger
  Logger.debug("Hook called",
    input: input,
    tool_use_id: tool_use_id
  )

  result = your_logic(input)
  Logger.debug("Hook result", result: result)

  result
end
```

### Test Hooks Independently

```elixir
# Test hook without Client
defmodule HookTest do
  use ExUnit.Case

  test "check_bash_command blocks dangerous commands" do
    input = %{
      "hook_event_name" => "PreToolUse",
      "tool_name" => "Bash",
      "tool_input" => %{"command" => "rm -rf /"}
    }

    result = MyHooks.check_bash_command(input, "test_id", %{})

    assert result.hookSpecificOutput.permissionDecision == "deny"
  end
end
```

---

## Migration from Claude CLI Hooks

If you're using shell script hooks in `settings.json`, you can migrate to SDK hooks:

### Before (settings.json)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/check-bash.sh"
          }
        ]
      }
    ]
  }
}
```

### After (Elixir SDK)

```elixir
defmodule MyHooks do
  def check_bash(input, _tool_use_id, _context) do
    # Same logic as check-bash.sh but in Elixir
    # ...
  end
end

options = %Options{
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&MyHooks.check_bash/3])
    ]
  }
}
```

**Benefits of SDK Hooks**:
- No subprocess overhead
- Type safety
- Easier debugging
- Access to full Elixir ecosystem
- Better error handling

---

## Further Reading

- [Claude Code Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks)
- Design Document: `docs/design/hooks_implementation.md` (available in source repository)
- Examples: See `examples/hooks/` directory in the source repository
- Test Suite: See `test/claude_agent_sdk/hooks/` directory in the source repository

---

**Questions or Issues?**

- GitHub Issues: https://github.com/nshkrdotcom/claude_agent_sdk/issues
- Documentation: https://hexdocs.pm/claude_agent_sdk
