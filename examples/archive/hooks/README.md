# Hooks Examples

This directory contains working examples demonstrating Claude Code Hooks in the Elixir SDK.

## Running Examples

All examples are self-contained and can be run directly:

```bash
# From project root
elixir examples/hooks/basic_bash_blocking.exs
elixir examples/hooks/context_injection.exs
elixir examples/hooks/file_policy_enforcement.exs
elixir examples/hooks/logging_and_audit.exs
elixir examples/hooks/complete_workflow.exs
```

Note: These examples demonstrate hook callback logic. When the Client GenServer is implemented, they will integrate with real Claude Code sessions.

## Examples Overview

### 1. basic_bash_blocking.exs

**Purpose:** Demonstrate security validation with PreToolUse hooks

**What it shows:**
- Blocking dangerous bash commands
- Pattern matching for security threats
- Permission decisions (allow/deny)
- Feedback to user and Claude

**Key Concepts:**
```elixir
def check_bash_command(input, _tool_use_id, _context) do
  if dangerous?(input["tool_input"]["command"]) do
    Output.deny("Dangerous command blocked")
  else
    Output.allow()
  end
end
```

**Run it:**
```bash
elixir examples/hooks/basic_bash_blocking.exs
```

**Expected Output:**
- 🚫 Dangerous command blocked
- ✅ Safe command allowed
- Hook output structures shown

---

### 2. context_injection.exs

**Purpose:** Demonstrate automatic context injection

**What it shows:**
- UserPromptSubmit hook to add project context
- PostToolUse hook to add execution metadata
- Context enrichment patterns
- Multiple hook events working together

**Key Concepts:**
```elixir
def add_project_context(_input, _tool_use_id, _context) do
  context_text = """
  Current branch: #{get_git_branch()}
  Recent commits: #{get_recent_commits()}
  """

  Output.add_context("UserPromptSubmit", context_text)
end
```

**Run it:**
```bash
elixir examples/hooks/context_injection.exs
```

**Expected Output:**
- Project context injected
- Execution metadata added
- Formatted context display

---

### 3. file_policy_enforcement.exs

**Purpose:** Demonstrate comprehensive file access policies

**What it shows:**
- Protecting sensitive files (.env, secrets.yml)
- Sandbox directory enforcement
- Different rules for Read vs Write operations
- 5 test cases with different scenarios

**Key Concepts:**
```elixir
def enforce_file_policy(input, _tool_use_id, _context) do
  path = input["tool_input"]["file_path"]

  cond do
    forbidden_file?(path) -> Output.deny("Sensitive file")
    outside_sandbox?(path) -> Output.deny("Outside sandbox")
    true -> Output.allow()
  end
end
```

**Run it:**
```bash
elixir examples/hooks/file_policy_enforcement.exs
```

**Expected Output:**
- 5 test cases executed
- 3 blocked (policy violations)
- 2 allowed (compliant operations)
- Policy summary

---

### 4. logging_and_audit.exs

**Purpose:** Demonstrate comprehensive audit logging

**What it shows:**
- PreToolUse logging of invocations
- PostToolUse logging of results
- Stop hook for session summaries
- Audit trail generation
- Multiple operations tracked

**Key Concepts:**
```elixir
def log_tool_invocation(input, tool_use_id, _context) do
  Logger.info("Tool invoked",
    tool: input["tool_name"],
    tool_use_id: tool_use_id
  )

  write_audit_log(input)
  %{}  # Don't modify behavior
end
```

**Run it:**
```bash
elixir examples/hooks/logging_and_audit.exs
```

**Expected Output:**
- Detailed audit logs
- Tool invocation tracking
- Execution results logged
- Session summary generated

---

### 5. complete_workflow.exs

**Purpose:** Demonstrate all hooks working together in a real-world scenario

**What it shows:**
- Multiple hooks for different events
- Security + Context + Monitoring + Session management
- Complete agent lifecycle
- Production-ready patterns
- Per-matcher hook timeouts shared with the CLI during initialize

**Features:**
- Security validation (PreToolUse)
- Context injection (UserPromptSubmit)
- Execution monitoring (PostToolUse)
- Session management (Stop)
- Comprehensive logging
- Live CLI run with explicit `timeout_ms` budgets per matcher

**Run it:**
```bash
elixir examples/hooks/complete_workflow.exs
```

**Expected Output:**
- Full workflow simulation
- All 5 steps executed
- Security blocking demonstrated
- Context injection shown
- Session summary generated

---

## Learning Path

**Recommended order:**

1. **Start here:** `basic_bash_blocking.exs`
   - Understand hook structure
   - Learn permission decisions
   - See allow/deny patterns

2. **Next:** `context_injection.exs`
   - Learn context injection
   - Understand multiple hook events
   - See UserPromptSubmit and PostToolUse

3. **Then:** `file_policy_enforcement.exs`
   - Complex validation logic
   - Multiple policy rules
   - Different tool handling

4. **Advanced:** `logging_and_audit.exs`
   - Observability patterns
   - Audit trail generation
   - Session lifecycle

5. **Complete:** `complete_workflow.exs`
   - All hooks together
   - Production patterns
   - Real-world scenarios

---

## Key Patterns

### Pattern 1: Security Validation

```elixir
def security_hook(input, _tool_use_id, _context) do
  if violates_policy?(input) do
    Output.deny(reason)
    |> Output.with_system_message(user_message)
  else
    Output.allow()
  end
end
```

### Pattern 2: Context Injection

```elixir
def context_hook(_input, _tool_use_id, _context) do
  context = gather_context()
  Output.add_context(event_name, context)
end
```

### Pattern 3: Monitoring

```elixir
def monitor_hook(input, tool_use_id, _context) do
  Logger.info("Hook invoked", tool_use_id: tool_use_id)
  write_metrics(input)
  %{}  # Don't modify behavior
end
```

### Pattern 4: Conditional Control

```elixir
def control_hook(input, _tool_use_id, _context) do
  if should_stop?(input) do
    Output.stop(reason)
  else
    Output.continue()
  end
end
```

---

## Hook Output Helpers

All examples use the `Output` module helpers:

```elixir
# Permission decisions
Output.allow("Reason")
Output.deny("Reason")
Output.ask("Reason")

# Context injection
Output.add_context("PostToolUse", "Context text")

# Execution control
Output.stop("Reason")
Output.block("Reason")
Output.continue()

# Combinators
Output.deny("Blocked")
|> Output.with_system_message("User message")
|> Output.with_reason("Claude feedback")
|> Output.suppress_output()
```

---

## Common Use Cases

### Security

- Block dangerous shell commands
- Enforce file access policies
- Prevent sensitive data exposure
- Rate limiting
- Input validation

### Intelligence

- Inject current time/date
- Add git branch/commit info
- Include recent issues/PRs
- Provide environment context
- Add system guidelines

### Monitoring

- Track all tool usage
- Measure execution times
- Log success/failure rates
- Alert on anomalies
- Generate reports

### Compliance

- Audit trail generation
- Policy enforcement
- Access control logging
- Regulatory compliance
- Security forensics

---

## Next Steps

After reviewing these examples:

1. **Read the full guide:** [Hooks Guide](../../../guides/hooks.md)
2. **Explore tests:** `test/claude_agent_sdk/hooks/`
3. **Build your own:** Create custom hooks for your use case!

---

## Questions?

- **API Reference:** See module docs with `h ClaudeAgentSDK.Hooks.Output`
- **Full Guide:** [Hooks Guide](../../../guides/hooks.md)
- **Issues:** [GitHub Issues](https://github.com/nshkrdotcom/claude_agent_sdk/issues)
