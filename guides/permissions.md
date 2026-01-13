# Permissions Guide

The Claude Agent SDK for Elixir provides a comprehensive permission system for controlling tool execution at runtime. This guide covers permission modes, callbacks, input modification, and best practices for securing your Claude agent integrations.

## Table of Contents

1. [Understanding Permission Modes](#understanding-permission-modes)
2. [Permission Callback (`can_use_tool`)](#permission-callback-can_use_tool)
3. [Permission.Context Struct](#permissioncontext-struct)
4. [Permission.Result Module](#permissionresult-module)
5. [Permission.Update Module](#permissionupdate-module)
6. [Input Modification and Redirection](#input-modification-and-redirection)
7. [File Path Sandboxing Example](#file-path-sandboxing-example)
8. [Command Blocking Example](#command-blocking-example)
9. [Combining Permissions with Hooks](#combining-permissions-with-hooks)
10. [Best Practices](#best-practices)

---

## Understanding Permission Modes

The SDK supports six permission modes that control how tool permissions are handled. Set the mode using the `permission_mode` option:

```elixir
options = %ClaudeAgentSDK.Options{
  permission_mode: :default  # or :accept_edits, :plan, :bypass_permissions, :delegate, :dont_ask
}
```

### `:default` Mode

The CLI uses its standard permission flow. For built-in tools, this is the recommended mode when using `can_use_tool`.

```elixir
options = %ClaudeAgentSDK.Options{
  permission_mode: :default,
  can_use_tool: &my_permission_callback/1
}
```

### `:delegate` Mode

Delegates tool execution to the SDK. Use this when you plan to execute tools yourself instead of the Claude CLI.

```elixir
options = %ClaudeAgentSDK.Options{
  permission_mode: :delegate,
  can_use_tool: &my_permission_callback/1
}
```

### `:accept_edits` Mode

Edit operations (Write, Edit, MultiEdit) are automatically allowed without invoking the permission callback. Other tools still go through the callback. Useful when you trust file modifications but want to control other operations.

```elixir
options = %ClaudeAgentSDK.Options{
  permission_mode: :accept_edits,
  can_use_tool: &my_permission_callback/1
}
```

### `:plan` Mode

Claude creates a plan before execution, shows it to the user, then executes after approval. For built-in tool decisions, prefer `:default`.

```elixir
options = %ClaudeAgentSDK.Options{
  permission_mode: :plan,
  can_use_tool: &my_permission_callback/1
}
```

### `:bypass_permissions` Mode

All tools are allowed without invoking the permission callback. Use only in trusted environments (e.g., development, sandboxed containers).

```elixir
options = %ClaudeAgentSDK.Options{
  permission_mode: :bypass_permissions
}
```

### `:dont_ask` Mode

Disables permission prompts so tools proceed without callback involvement. Use with caution in trusted environments.

```elixir
options = %ClaudeAgentSDK.Options{
  permission_mode: :dont_ask
}
```

### Comparison Table

| Mode | Edit Tools | Other Tools | Use Case |
|------|------------|-------------|----------|
| `:default` | CLI flow | CLI flow | Built-in tool permissions |
| `:delegate` | Callback | Callback | External tool execution |
| `:accept_edits` | Auto-allow | Callback | Trusted file operations |
| `:plan` | Plan + approval | Plan + approval | Review-before-execute workflows |
| `:bypass_permissions` | Auto-allow | Auto-allow | Development/sandboxed |
| `:dont_ask` | Auto-allow | Auto-allow | No prompt / headless flows |

---

## Permission Callback (`can_use_tool`)

The `can_use_tool` option accepts a callback function that receives a `Permission.Context` and returns a `Permission.Result`.

Important constraints:
- `can_use_tool` routes `query/2` through the control client (string or streaming prompts).
- `can_use_tool` cannot be combined with `permission_prompt_tool`; the SDK sets `permission_prompt_tool` to `"stdio"` internally.
- For built-in tool permissions, use `permission_mode: :default` or `:plan`.
- `can_use_tool` enables `include_partial_messages` automatically so tool events stream to the SDK.
- Hook-based fallback only applies in non-`:delegate` modes and ignores `updated_permissions`.

### Troubleshooting Missing Callbacks

If your callback never fires, the CLI may not be emitting `can_use_tool` or hook callbacks for tool use. This is a known behavior on some Claude CLI builds. Run `examples/advanced_features/permissions_live.exs` to verify your CLI and confirm the control protocol is emitting callbacks.

### Callback Signature

```elixir
@spec callback(Permission.Context.t()) :: Permission.Result.t()
```

### Basic Example

```elixir
alias ClaudeAgentSDK.Permission.{Context, Result}

callback = fn context ->
  case context.tool_name do
    "Bash" ->
      Result.allow()

    "Write" ->
      Result.allow()

    _ ->
      Result.allow()
  end
end

options = %ClaudeAgentSDK.Options{
  permission_mode: :default,
  can_use_tool: callback
}
```

### Complete Example with Logging

```elixir
alias ClaudeAgentSDK.Permission.{Context, Result}

# Create ETS table for audit logging
audit_log = :ets.new(:permission_audit, [:public, :bag])

callback = fn context ->
  # Log every permission request
  timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
  :ets.insert(audit_log, {timestamp, context.tool_name, context.tool_input})

  case context.tool_name do
    "Bash" ->
      command = context.tool_input["command"] || ""

      if dangerous_command?(command) do
        Result.deny("Dangerous command pattern detected")
      else
        Result.allow()
      end

    "Write" ->
      file_path = context.tool_input["file_path"] || ""

      if allowed_path?(file_path) do
        Result.allow()
      else
        Result.deny("Write operation outside allowed directories")
      end

    _ ->
      Result.allow()
  end
end

defp dangerous_command?(cmd) do
  patterns = ["rm -rf", "sudo", "chmod 777", "dd if=", "mkfs", "> /dev/"]
  Enum.any?(patterns, &String.contains?(cmd, &1))
end

defp allowed_path?(path) do
  allowed_dirs = ["/tmp/", "/home/user/project/", "./"]
  Enum.any?(allowed_dirs, &String.starts_with?(path, &1))
end
```

---

## Permission.Context Struct

The `Permission.Context` struct contains all information about the tool being invoked.

### Structure

```elixir
%ClaudeAgentSDK.Permission.Context{
  tool_name: String.t(),        # Name of the tool (e.g., "Bash", "Write", "Read")
  tool_input: map(),            # Input parameters for the tool
  session_id: String.t(),       # Unique session identifier
  suggestions: [map()],         # Permission suggestions from CLI
  blocked_path: String.t(),     # Path that triggered blocking (if applicable)
  signal: AbortSignal.t()       # Optional abort signal reference
}
```

Note: MCP tool names are always strings of the form `mcp__<server>__<tool>`; avoid atom matching for MCP tool names.

### Accessing Context Fields

```elixir
callback = fn context ->
  IO.puts("Tool: #{context.tool_name}")
  IO.puts("Session: #{context.session_id}")
  IO.inspect(context.tool_input, label: "Input")

  # Access tool-specific input fields
  case context.tool_name do
    "Bash" ->
      command = context.tool_input["command"]
      IO.puts("Command: #{command}")

    "Write" ->
      path = context.tool_input["file_path"]
      content = context.tool_input["content"]
      IO.puts("Writing #{byte_size(content)} bytes to #{path}")

    "Read" ->
      path = context.tool_input["file_path"]
      IO.puts("Reading: #{path}")

    _ ->
      :ok
  end

  Result.allow()
end
```

### Creating Context Manually (for testing)

```elixir
alias ClaudeAgentSDK.Permission.Context

context = Context.new(
  tool_name: "Bash",
  tool_input: %{"command" => "ls -la"},
  session_id: "test-session-123"
)

# Or with suggestions
context = Context.new(
  tool_name: "Write",
  tool_input: %{"file_path" => "/etc/hosts", "content" => "data"},
  session_id: "test-session-123",
  suggestions: [
    %{"type" => "deny", "reason" => "System file modification"}
  ]
)
```

### Using Permission Suggestions

The CLI may provide permission suggestions that hint at appropriate actions:

```elixir
callback = fn context ->
  # Check if CLI suggests denying
  has_deny_suggestion = Enum.any?(context.suggestions, fn suggestion ->
    suggestion["type"] == "deny"
  end)

  if has_deny_suggestion do
    reason = context.suggestions
      |> Enum.find(&(&1["type"] == "deny"))
      |> Map.get("reason", "CLI suggested denial")

    Result.deny(reason)
  else
    Result.allow()
  end
end
```

---

## Permission.Result Module

The `Permission.Result` module provides functions to create permission responses.

### Allow Results

```elixir
alias ClaudeAgentSDK.Permission.Result

# Simple allow
Result.allow()

# Allow with modified input
Result.allow(updated_input: %{"file_path" => "/safe/path.txt"})

# Allow with permission updates
Result.allow(
  updated_permissions: [
    %{"type" => "addRules", "tool_name" => "Bash", "behavior" => "deny"}
  ]
)

# Allow with both
Result.allow(
  updated_input: %{"file_path" => "/safe/path.txt"},
  updated_permissions: [
    %{"type" => "setMode", "mode" => "plan", "destination" => "session"}
  ]
)
```

### Deny Results

```elixir
alias ClaudeAgentSDK.Permission.Result

# Simple deny with reason
Result.deny("Operation not permitted")

# Deny with interrupt (stops entire agent execution)
Result.deny("Critical security violation", interrupt: true)
```

### Result Validation

```elixir
alias ClaudeAgentSDK.Permission.Result

# Validate a result
result = Result.allow()
:ok = Result.validate(result)

result = Result.deny("reason")
:ok = Result.validate(result)

# Invalid results
{:error, reason} = Result.validate(%{})
```

### Converting to JSON (for debugging)

```elixir
alias ClaudeAgentSDK.Permission.Result

result = Result.allow(updated_input: %{"key" => "value"})
json_map = Result.to_json_map(result)
# => %{"behavior" => "allow", "updatedInput" => %{"key" => "value"}}

result = Result.deny("Not allowed", interrupt: true)
json_map = Result.to_json_map(result)
# => %{"behavior" => "deny", "message" => "Not allowed", "interrupt" => true}
```

---

## Permission.Update Module

The `Permission.Update` module provides structs for programmatically updating permission rules through the control protocol. This matches the Python SDK's `PermissionUpdate` type.

### Update Types

| Type | Description |
|------|-------------|
| `:add_rules` | Add new permission rules |
| `:replace_rules` | Replace existing rules |
| `:remove_rules` | Remove specific rules |
| `:set_mode` | Change permission mode |
| `:add_directories` | Add allowed directories |
| `:remove_directories` | Remove allowed directories |

### Destinations

| Destination | Persistence | Scope |
|-------------|-------------|-------|
| `:session` | Temporary | Current session only |
| `:user_settings` | Persistent | User-level |
| `:project_settings` | Persistent | Project-level |
| `:local_settings` | Persistent | Local directory |

### Creating Updates

```elixir
alias ClaudeAgentSDK.Permission.{Update, RuleValue}

# Add a rule to allow Bash commands
update = Update.add_rules(
  rules: [RuleValue.new("Bash", "echo *")],
  behavior: :allow,
  destination: :session
)

# Set permission mode for the session
update = Update.set_mode(:accept_edits, destination: :session)

# Add allowed directories
update = Update.add_directories(["/tmp/workspace"], destination: :session)

# Remove rules
update = Update.remove_rules(
  rules: [RuleValue.new("Bash")],
  destination: :session
)
```

### Using Updates in Permission Results

```elixir
alias ClaudeAgentSDK.Permission.{Result, Update, RuleValue}

callback = fn context ->
  case context.tool_name do
    "Bash" ->
      # Allow this command and add a rule for future similar commands
      Result.allow(
        updated_permissions: [
          Update.add_rules(
            rules: [RuleValue.new("Bash", context.tool_input["command"])],
            behavior: :allow,
            destination: :session
          )
        ]
      )

    _ ->
      Result.allow()
  end
end
```

### RuleValue Struct

The `RuleValue` struct represents a single permission rule:

```elixir
alias ClaudeAgentSDK.Permission.RuleValue

# Simple rule for a tool
rule = RuleValue.new("Bash")

# Rule with content pattern
rule = RuleValue.new("Bash", "ls *")
rule = RuleValue.new("Write", "/tmp/**")
```

### Serialization

Updates are automatically serialized when used in permission results:

```elixir
alias ClaudeAgentSDK.Permission.{Update, RuleValue}

update = Update.add_rules(
  rules: [RuleValue.new("Bash", "echo *")],
  behavior: :allow,
  destination: :session
)

Update.to_map(update)
# => %{
#   "type" => "addRules",
#   "rules" => [%{"toolName" => "Bash", "ruleContent" => "echo *"}],
#   "behavior" => "allow",
#   "destination" => "session"
# }
```

---

## Input Modification and Redirection

One powerful feature of the permission system is the ability to modify tool inputs before execution.

### Redirecting File Writes

```elixir
alias ClaudeAgentSDK.Permission.Result

# Sandbox directory for all writes
sandbox_dir = "/tmp/claude_sandbox"

callback = fn context ->
  case context.tool_name do
    "Write" ->
      original_path = context.tool_input["file_path"]

      # Redirect all writes to sandbox
      safe_path = Path.join(sandbox_dir, Path.basename(original_path))

      # Modify the input
      updated_input = Map.put(context.tool_input, "file_path", safe_path)

      IO.puts("Redirecting: #{original_path} -> #{safe_path}")
      Result.allow(updated_input: updated_input)

    _ ->
      Result.allow()
  end
end
```

### Sanitizing Commands

```elixir
callback = fn context ->
  case context.tool_name do
    "Bash" ->
      command = context.tool_input["command"] || ""

      # Remove sudo from commands
      sanitized = String.replace(command, ~r/\bsudo\s+/, "")

      if sanitized != command do
        IO.puts("Removed sudo from command")
        updated_input = Map.put(context.tool_input, "command", sanitized)
        Result.allow(updated_input: updated_input)
      else
        Result.allow()
      end

    _ ->
      Result.allow()
  end
end
```

### Adding Required Flags

```elixir
callback = fn context ->
  case context.tool_name do
    "Bash" ->
      command = context.tool_input["command"] || ""

      # Add safety flags to rm commands
      modified = if String.contains?(command, "rm ") do
        # Add -i (interactive) flag if not present
        if not String.contains?(command, "-i") do
          String.replace(command, "rm ", "rm -i ")
        else
          command
        end
      else
        command
      end

      if modified != command do
        Result.allow(updated_input: Map.put(context.tool_input, "command", modified))
      else
        Result.allow()
      end

    _ ->
      Result.allow()
  end
end
```

---

## File Path Sandboxing Example

A complete example of implementing file path sandboxing:

```elixir
defmodule MyApp.FileSandbox do
  @moduledoc """
  Permission callback that enforces file path sandboxing.
  """

  alias ClaudeAgentSDK.Permission.Result

  @allowed_directories [
    "/tmp/claude_workspace",
    "/home/app/projects"
  ]

  @forbidden_patterns [
    ~r/\.\.\//, # Path traversal
    ~r/^\/etc\//, # System config
    ~r/^\/usr\//, # System binaries
    ~r/^\/var\//, # System data
    ~r/\.env$/,   # Environment files
    ~r/secrets\./,# Secret files
    ~r/\.pem$/,   # Private keys
    ~r/\.key$/    # Key files
  ]

  def permission_callback(context) do
    case context.tool_name do
      tool when tool in ["Read", "Write", "Edit"] ->
        check_file_access(context)

      "Bash" ->
        check_bash_file_access(context)

      _ ->
        Result.allow()
    end
  end

  defp check_file_access(context) do
    file_path = context.tool_input["file_path"] || ""

    cond do
      forbidden_pattern?(file_path) ->
        Result.deny("Access to this file pattern is not allowed")

      not in_allowed_directory?(file_path) ->
        # Redirect to sandbox
        safe_path = sandbox_path(file_path)
        updated_input = Map.put(context.tool_input, "file_path", safe_path)
        Result.allow(updated_input: updated_input)

      true ->
        Result.allow()
    end
  end

  defp check_bash_file_access(context) do
    command = context.tool_input["command"] || ""

    # Check for file operations in bash commands
    file_patterns = ~r/(cat|head|tail|less|more|vi|vim|nano|rm|mv|cp)\s+([^\s|;&]+)/

    if Regex.match?(file_patterns, command) do
      [_full, _cmd, path] = Regex.run(file_patterns, command)

      if forbidden_pattern?(path) do
        Result.deny("Bash command attempts to access forbidden file: #{path}")
      else
        Result.allow()
      end
    else
      Result.allow()
    end
  end

  defp forbidden_pattern?(path) do
    Enum.any?(@forbidden_patterns, &Regex.match?(&1, path))
  end

  defp in_allowed_directory?(path) do
    Enum.any?(@allowed_directories, &String.starts_with?(path, &1))
  end

  defp sandbox_path(original_path) do
    sandbox_dir = List.first(@allowed_directories)
    filename = Path.basename(original_path)
    Path.join(sandbox_dir, filename)
  end
end

# Usage
options = %ClaudeAgentSDK.Options{
  permission_mode: :default,
  can_use_tool: &MyApp.FileSandbox.permission_callback/1
}
```

---

## Command Blocking Example

A complete example of blocking dangerous bash commands:

```elixir
defmodule MyApp.CommandPolicy do
  @moduledoc """
  Permission callback that blocks dangerous commands.
  """

  alias ClaudeAgentSDK.Permission.Result

  @dangerous_commands [
    "rm -rf",
    "rm -fr",
    "sudo",
    "chmod 777",
    "chown",
    "dd if=",
    "mkfs",
    "> /dev/",
    "wget",
    "curl.*|.*sh",  # Piping curl to shell
    "eval",
    "exec",
    ":(){",         # Fork bomb
    "shutdown",
    "reboot",
    "init 0",
    "init 6"
  ]

  @dangerous_patterns [
    ~r/rm\s+-[rf]*\s+\/(?!tmp)/,      # rm -rf outside /tmp
    ~r/>\s*\/dev\/(sd|hd|nvme)/,      # Overwriting devices
    ~r/curl.*\|\s*(ba)?sh/,           # Piping downloads to shell
    ~r/wget.*\|\s*(ba)?sh/,
    ~r/\\x[0-9a-f]{2}/i,              # Hex-encoded payloads
    ~r/base64\s+-d/                    # Base64 decoding (often used in exploits)
  ]

  def permission_callback(context) do
    case context.tool_name do
      "Bash" ->
        check_command(context)

      _ ->
        Result.allow()
    end
  end

  defp check_command(context) do
    command = context.tool_input["command"] || ""

    cond do
      dangerous_literal?(command) ->
        Result.deny(
          "Command contains dangerous pattern",
          interrupt: false
        )

      dangerous_pattern?(command) ->
        Result.deny(
          "Command matches dangerous pattern",
          interrupt: false
        )

      multiline_suspicious?(command) ->
        Result.deny(
          "Multi-line command with suspicious content",
          interrupt: false
        )

      true ->
        Result.allow()
    end
  end

  defp dangerous_literal?(command) do
    command_lower = String.downcase(command)
    Enum.any?(@dangerous_commands, &String.contains?(command_lower, &1))
  end

  defp dangerous_pattern?(command) do
    Enum.any?(@dangerous_patterns, &Regex.match?(&1, command))
  end

  defp multiline_suspicious?(command) do
    lines = String.split(command, "\n")

    if length(lines) > 10 do
      # Long multiline scripts get extra scrutiny
      has_network = Enum.any?(lines, &String.contains?(&1, ["curl", "wget", "nc"]))
      has_exec = Enum.any?(lines, &String.contains?(&1, ["eval", "exec", "$("]))
      has_network and has_exec
    else
      false
    end
  end
end

# Usage
options = %ClaudeAgentSDK.Options{
  permission_mode: :default,
  can_use_tool: &MyApp.CommandPolicy.permission_callback/1
}

# Run query with protection
messages = ClaudeAgentSDK.query(
  "Delete all files in the root directory",
  options
) |> Enum.to_list()
```

---

## Combining Permissions with Hooks

The permission system works alongside the hooks system. Use both for comprehensive control.

### Architecture Overview

```
User Query
    |
    v
[user_prompt_submit hook] --> Context injection
    |
    v
Claude Processing
    |
    v
Tool Use Request
    |
    v
[Permission Callback] --> Allow/Deny/Modify
    |
    v (if allowed)
[pre_tool_use hook] --> Logging, additional checks
    |
    v
Tool Execution
    |
    v
[post_tool_use hook] --> Audit logging, monitoring
    |
    v
Response to User
```

Note: Hook fallback only applies in non-`:delegate` modes. In `:delegate`, the
permission callback only runs when the CLI emits `can_use_tool`.

### Combined Example

```elixir
alias ClaudeAgentSDK.{Options, Hooks.Matcher, Hooks.Output}
alias ClaudeAgentSDK.Permission.Result

# Permission callback for access control
permission_callback = fn context ->
  case context.tool_name do
    "Bash" ->
      if String.contains?(context.tool_input["command"] || "", "rm -rf") do
        Result.deny("Dangerous command blocked by permission policy")
      else
        Result.allow()
      end

    "Write" ->
      if String.starts_with?(context.tool_input["file_path"] || "", "/etc") do
        Result.deny("System file modification not allowed")
      else
        Result.allow()
      end

    _ ->
      Result.allow()
  end
end

# Hook for logging (pre-tool)
log_hook = fn input, tool_use_id, _context ->
  IO.puts("[AUDIT] Tool: #{input["tool_name"]}, ID: #{tool_use_id}")
  Output.allow()
end

# Hook for post-execution monitoring
monitor_hook = fn input, tool_use_id, _context ->
  is_error = get_in(input, ["tool_response", "is_error"]) || false
  status = if is_error, do: "FAILED", else: "SUCCESS"
  IO.puts("[AUDIT] Tool #{input["tool_name"]} (#{tool_use_id}): #{status}")
  %{}  # Don't modify behavior
end

# Combined options
options = %Options{
  permission_mode: :default,
  can_use_tool: permission_callback,
  hooks: %{
    pre_tool_use: [
      Matcher.new("*", [log_hook])
    ],
    post_tool_use: [
      Matcher.new("*", [monitor_hook])
    ]
  }
}
```

### When to Use Permissions vs Hooks

| Aspect | Permissions | Hooks |
|--------|-------------|-------|
| Purpose | Access control | Lifecycle events |
| Timing | Before execution | Before/after execution |
| Can deny | Yes | Yes (pre-tool only) |
| Can modify input | Yes | Yes (pre-tool only) |
| Can log | Yes | Yes |
| Session events | No | Yes (start/end/stop) |
| Context injection | No | Yes (user_prompt_submit) |

### Recommended Pattern

Use **permissions** for:
- Security policies (allow/deny)
- Input modification/redirection
- Tool-level access control

Use **hooks** for:
- Audit logging
- Monitoring
- Context injection
- Session lifecycle events
- Post-execution actions

---

## Best Practices

### 1. Always Validate Inputs

Never trust tool inputs blindly:

```elixir
callback = fn context ->
  file_path = context.tool_input["file_path"]

  # Validate path exists and is a string
  if is_binary(file_path) and String.length(file_path) > 0 do
    # Normalize path to catch traversal attempts
    normalized = Path.expand(file_path)

    if safe_path?(normalized) do
      Result.allow()
    else
      Result.deny("Path validation failed")
    end
  else
    Result.deny("Invalid file path")
  end
end
```

### 2. Use Deny by Default in Production

For production, start restrictive and allow explicitly:

```elixir
callback = fn context ->
  case context.tool_name do
    "Read" -> Result.allow()
    "Grep" -> Result.allow()
    "Glob" -> Result.allow()

    "Write" ->
      if in_allowed_directory?(context.tool_input["file_path"]) do
        Result.allow()
      else
        Result.deny("Write outside allowed directories")
      end

    "Bash" ->
      if allowed_command?(context.tool_input["command"]) do
        Result.allow()
      else
        Result.deny("Command not in allowlist")
      end

    # Deny unknown tools
    tool ->
      Result.deny("Tool #{tool} is not permitted")
  end
end
```

### 3. Log All Permission Decisions

Maintain an audit trail:

```elixir
defmodule MyApp.AuditedPermissions do
  require Logger
  alias ClaudeAgentSDK.Permission.Result

  def callback(context) do
    result = do_permission_check(context)

    # Log the decision
    Logger.info("Permission check",
      tool: context.tool_name,
      session: context.session_id,
      decision: result.behavior,
      reason: result.message
    )

    result
  end

  defp do_permission_check(context) do
    # Your permission logic here
    Result.allow()
  end
end
```

### 4. Handle Exceptions Gracefully

Permission callbacks should never crash:

```elixir
callback = fn context ->
  try do
    do_permission_check(context)
  rescue
    e ->
      Logger.error("Permission callback error: #{Exception.message(e)}")
      # Fail closed - deny on error
      Result.deny("Permission check failed due to internal error")
  end
end
```

### 5. Use Permission Modes Appropriately

| Environment | Recommended Mode |
|-------------|-----------------|
| Development | `:bypass_permissions` or `:accept_edits` |
| Testing | `:default` with test callback |
| Staging | `:default` or `:plan` |
| Production | `:default` with strict callback |

### 6. Implement Rate Limiting

Prevent abuse with rate limiting:

```elixir
defmodule MyApp.RateLimitedPermissions do
  use GenServer
  alias ClaudeAgentSDK.Permission.Result

  @max_tools_per_minute 60

  def callback(context) do
    session_id = context.session_id

    case check_rate_limit(session_id) do
      :ok ->
        Result.allow()

      :rate_limited ->
        Result.deny("Rate limit exceeded. Please wait before using more tools.")
    end
  end

  defp check_rate_limit(session_id) do
    # Implementation using ETS or GenServer state
    # Track tool usage per session per minute
    :ok
  end
end
```

### 7. Test Permission Callbacks

Write tests for your permission logic:

```elixir
defmodule MyApp.PermissionTest do
  use ExUnit.Case
  alias ClaudeAgentSDK.Permission.{Context, Result}
  alias MyApp.Permissions

  test "allows safe commands" do
    context = Context.new(
      tool_name: "Bash",
      tool_input: %{"command" => "ls -la"},
      session_id: "test"
    )

    result = Permissions.callback(context)
    assert result.behavior == :allow
  end

  test "denies dangerous commands" do
    context = Context.new(
      tool_name: "Bash",
      tool_input: %{"command" => "rm -rf /"},
      session_id: "test"
    )

    result = Permissions.callback(context)
    assert result.behavior == :deny
    assert result.message =~ "dangerous"
  end

  test "redirects file writes to sandbox" do
    context = Context.new(
      tool_name: "Write",
      tool_input: %{"file_path" => "/etc/passwd", "content" => "test"},
      session_id: "test"
    )

    result = Permissions.callback(context)
    assert result.behavior == :allow
    assert result.updated_input["file_path"] =~ "/tmp/sandbox"
  end
end
```

### 8. Document Your Permission Policy

Maintain clear documentation of what's allowed:

```elixir
defmodule MyApp.Permissions do
  @moduledoc """
  Permission policy for Claude agent.

  ## Allowed Operations

  - Read any file in the project directory
  - Write to /tmp and project directories
  - Run safe bash commands (ls, cat, grep, find, etc.)

  ## Denied Operations

  - System file modifications (/etc, /usr, /var)
  - Destructive commands (rm -rf, mkfs, dd)
  - Network operations (curl, wget) without approval
  - Privilege escalation (sudo, su)

  ## Input Modifications

  - File writes outside allowed dirs are redirected to sandbox
  - Sudo is stripped from commands
  """

  # Implementation...
end
```

---

## Summary

The Claude Agent SDK permission system provides:

1. **Permission Modes** - Six modes for different security postures
2. **Permission Callbacks** - Full control over tool execution
3. **Context Information** - Complete visibility into tool requests
4. **Result Types** - Allow, deny, or modify tool inputs
5. **Integration with Hooks** - Combine with hooks for comprehensive control

Key takeaways:

- Use `:default` mode with a permission callback in production
- Always validate and sanitize tool inputs
- Log all permission decisions for auditing
- Handle exceptions gracefully (fail closed)
- Test your permission logic thoroughly
- Combine permissions with hooks for complete control

For more examples, see:
- `examples/advanced_features/permissions_live.exs`
- `examples/hooks/file_policy_enforcement.exs`
- `examples/hooks/basic_bash_blocking.exs`
