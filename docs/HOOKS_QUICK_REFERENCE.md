# Hooks Quick Reference Card

**Version:** 0.3.0 | **Last Updated:** 2025-10-16

---

## Hook Events

| Event | When | Can Block | Can Add Context | Use Cases |
|-------|------|-----------|-----------------|-----------|
| `pre_tool_use` | Before tool executes | ✅ Yes | ✅ Yes | Security validation, input transformation |
| `post_tool_use` | After tool executes | ❌ No | ✅ Yes | Result validation, monitoring, metrics |
| `user_prompt_submit` | User submits prompt | ✅ Yes | ✅ Yes | Context injection, prompt validation |
| `stop` | Agent finishes | ✅ Yes (force continue) | ❌ No | Session mgmt, force continuation |
| `subagent_stop` | Subagent finishes | ✅ Yes (force continue) | ❌ No | Subagent control, chaining |
| `pre_compact` | Before compaction | ❌ No | ❌ No | Save state, logging |

---

## Callback Signature

```elixir
@spec hook_callback(input :: map(), tool_use_id :: String.t() | nil, context :: map()) :: map()

def my_hook(input, tool_use_id, context) do
  # Your logic here
  Output.allow()  # or deny, ask, add_context, etc.
end
```

---

## Output Helpers

### Permission Decisions (PreToolUse)

```elixir
Output.allow()                    # Allow with default reason
Output.allow("Custom reason")     # Allow with custom reason
Output.deny("Reason")             # Deny and block execution
Output.ask("Confirm?")            # Ask user for permission
```

### Context Injection

```elixir
Output.add_context("PostToolUse", "Context text")
Output.add_context("UserPromptSubmit", "Additional info")
```

### Execution Control

```elixir
Output.stop("Reason")             # Stop execution
Output.block("Reason")            # Block with feedback
Output.continue()                 # Explicitly continue
```

### Combinators

```elixir
Output.deny("Blocked")
|> Output.with_system_message("User sees this")
|> Output.with_reason("Claude sees this")
|> Output.suppress_output()
```

---

## Matchers

### Exact Match

```elixir
Matcher.new("Bash", [&hook/3])
```

### Regex Pattern

```elixir
Matcher.new("Write|Edit|MultiEdit", [&hook/3])
```

### Match All

```elixir
Matcher.new("*", [&hook/3])
Matcher.new(nil, [&hook/3])
```

### Multiple Hooks

```elixir
Matcher.new("Bash", [&security_check/3, &audit_log/3, &monitor/3])
```

---

## Configuration

```elixir
options = %Options{
  allowed_tools: ["Bash", "Write", "Read"],
  hooks: %{
    pre_tool_use: [
      Matcher.new("Bash", [&check_bash/3]),
      Matcher.new("Write|Edit", [&check_files/3])
    ],
    post_tool_use: [
      Matcher.new("*", [&log_usage/3])
    ],
    user_prompt_submit: [
      Matcher.new(nil, [&add_context/3])
    ],
    stop: [
      Matcher.new(nil, [&session_end/3])
    ]
  }
}
```

---

## Common Patterns

### Security Validation

```elixir
def security_check(input, _tool_use_id, _context) do
  if dangerous?(input) do
    Output.deny("Security violation")
    |> Output.with_system_message("🔒 Blocked by policy")
  else
    Output.allow()
  end
end
```

### Context Injection

```elixir
def add_context(_input, _tool_use_id, _context) do
  context = """
  Current time: #{DateTime.utc_now()}
  Branch: #{get_git_branch()}
  """

  Output.add_context("UserPromptSubmit", context)
end
```

### Audit Logging

```elixir
def audit_log(input, tool_use_id, _context) do
  Logger.info("Tool used",
    tool: input["tool_name"],
    tool_use_id: tool_use_id
  )

  %{}  # Don't modify behavior
end
```

### Conditional Control

```elixir
def smart_control(input, _tool_use_id, _context) do
  cond do
    should_block?(input) -> Output.deny("Blocked")
    should_ask?(input) -> Output.ask("Confirm this?")
    true -> Output.allow()
  end
end
```

---

## Input Fields by Event

### PreToolUse / PostToolUse

```elixir
%{
  "hook_event_name" => "PreToolUse",
  "session_id" => "...",
  "transcript_path" => "...",
  "cwd" => "...",
  "tool_name" => "Bash",
  "tool_input" => %{"command" => "..."},
  "tool_response" => %{...}  # PostToolUse only
}
```

### UserPromptSubmit

```elixir
%{
  "hook_event_name" => "UserPromptSubmit",
  "session_id" => "...",
  "transcript_path" => "...",
  "cwd" => "...",
  "prompt" => "User's prompt text"
}
```

### Stop / SubagentStop

```elixir
%{
  "hook_event_name" => "Stop",
  "session_id" => "...",
  "transcript_path" => "...",
  "cwd" => "...",
  "stop_hook_active" => false
}
```

### PreCompact

```elixir
%{
  "hook_event_name" => "PreCompact",
  "session_id" => "...",
  "transcript_path" => "...",
  "cwd" => "...",
  "trigger" => "auto",  # or "manual"
  "custom_instructions" => "..."
}
```

---

## Output Fields

| Field | Type | Used By | Description |
|-------|------|---------|-------------|
| `continue` | boolean | All | Continue execution? |
| `stopReason` | string | All | Why stopping |
| `systemMessage` | string | All | User-visible message |
| `reason` | string | All | Claude-visible feedback |
| `suppressOutput` | boolean | All | Hide from transcript |
| `decision` | "block" | Stop, PostToolUse | Block with reason |
| `hookSpecificOutput` | map | All | Event-specific control |

### hookSpecificOutput Schemas

**PreToolUse:**
```elixir
%{
  "hookEventName" => "PreToolUse",
  "permissionDecision" => "allow",  # or "deny", "ask"
  "permissionDecisionReason" => "..."
}
```

**PostToolUse / UserPromptSubmit:**
```elixir
%{
  "hookEventName" => "PostToolUse",
  "additionalContext" => "Context for Claude"
}
```

---

## Best Practices

✅ **DO:**
- Keep hooks fast (< 100ms ideal)
- Handle errors gracefully
- Provide clear, actionable feedback
- Use specific matchers when possible
- Test hooks independently
- Make hooks idempotent
- Check `stop_hook_active` to prevent loops

❌ **DON'T:**
- Block for slow external calls (use async tasks)
- Throw unhandled exceptions
- Use vague error messages
- Modify global state without care
- Forget timeout implications
- Create infinite continuation loops

---

## Testing Hooks

```elixir
defmodule MyHookTest do
  use ExUnit.Case

  test "blocks dangerous commands" do
    input = %{
      "tool_name" => "Bash",
      "tool_input" => %{"command" => "rm -rf /"}
    }

    result = MyHooks.check_bash(input, "test_id", %{})

    assert result.hookSpecificOutput.permissionDecision == "deny"
  end
end
```

---

## Examples

See `examples/hooks/` for:
- `basic_bash_blocking.exs` - Security patterns
- `context_injection.exs` - Context patterns
- `file_policy_enforcement.exs` - Policy patterns
- `logging_and_audit.exs` - Logging patterns
- `complete_workflow.exs` - Combined patterns

---

## Documentation

- **Full Guide:** [HOOKS_GUIDE.md](HOOKS_GUIDE.md)
- **Design Doc:** [design/hooks_implementation.md](design/hooks_implementation.md)
- **Examples:** [../../examples/hooks/](../../examples/hooks/)
- **Tests:** [../../test/claude_agent_sdk/hooks/](../../test/claude_agent_sdk/hooks/)

---

**Need Help?**
```elixir
iex> h ClaudeAgentSDK.Hooks
iex> h ClaudeAgentSDK.Hooks.Output.deny
iex> h ClaudeAgentSDK.Hooks.Matcher.new
```
