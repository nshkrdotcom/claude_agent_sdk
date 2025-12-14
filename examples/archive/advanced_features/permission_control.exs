#!/usr/bin/env elixir

# Permission Control Example
# Demonstrates fine-grained tool permission control
#
# Usage:
#   mix run examples/advanced_features/permission_control.exs

alias ClaudeAgentSDK.{Options, Client}
alias ClaudeAgentSDK.Permission.{Context, Result}

IO.puts("\n=== Permission Control Example ===\n")

# Define a permission callback
IO.puts("Setting up permission callback for security control...\n")

# Track permission checks for demonstration
permission_log = :ets.new(:permission_log, [:public, :set])

permission_callback = fn context ->
  # Log the permission check
  :ets.insert(
    permission_log,
    {System.system_time(:millisecond), context.tool_name, context.tool_input}
  )

  case {context.tool_name, context.tool_input} do
    # Block dangerous bash commands
    {"Bash", %{"command" => cmd}} ->
      dangerous_patterns = ["rm -rf", "rm -fr", "> /dev/", "dd if=", "mkfs", ":(){ :|:& };:"]

      if Enum.any?(dangerous_patterns, &String.contains?(cmd, &1)) do
        IO.puts("🚫 BLOCKED: Dangerous bash command: #{String.slice(cmd, 0..50)}...")
        Result.deny("Dangerous command detected", interrupt: true)
      else
        IO.puts("✅ ALLOWED: Safe bash command")
        Result.allow()
      end

    # Redirect writes to system directories
    {"Write", %{"file_path" => path}} ->
      restricted_dirs = ["/etc/", "/usr/", "/bin/", "/sbin/", "/boot/"]

      if Enum.any?(restricted_dirs, &String.starts_with?(path, &1)) do
        safe_path = "/tmp/safe_output/" <> Path.basename(path)
        IO.puts("⚠️  REDIRECTED: #{path} → #{safe_path}")

        Result.allow(updated_input: Map.put(context.tool_input, "file_path", safe_path))
      else
        IO.puts("✅ ALLOWED: Write to #{path}")
        Result.allow()
      end

    # Log all Read operations but allow them
    {"Read", %{"file_path" => path}} ->
      IO.puts("📖 LOGGED: Reading #{path}")
      Result.allow()

    # Allow everything else
    _ ->
      IO.puts("✅ ALLOWED: #{context.tool_name}")
      Result.allow()
  end
end

# Test the callback with simulated contexts
IO.puts("Testing permission callback with various scenarios:\n")

test_contexts = [
  Context.new(
    tool_name: "Bash",
    tool_input: %{"command" => "ls -la"},
    session_id: "test-session"
  ),
  Context.new(
    tool_name: "Bash",
    tool_input: %{"command" => "rm -rf /important/data"},
    session_id: "test-session"
  ),
  Context.new(
    tool_name: "Write",
    tool_input: %{"file_path" => "/etc/config.conf", "content" => "test"},
    session_id: "test-session"
  ),
  Context.new(
    tool_name: "Write",
    tool_input: %{"file_path" => "/home/user/output.txt", "content" => "safe"},
    session_id: "test-session"
  ),
  Context.new(
    tool_name: "Read",
    tool_input: %{"file_path" => "/home/user/data.txt"},
    session_id: "test-session"
  )
]

for context <- test_contexts do
  _result = permission_callback.(context)
  IO.puts("")
end

# Demonstrate permission modes
IO.puts("\n--- Permission Modes ---\n")

modes = [:default, :accept_edits, :plan, :bypass_permissions]

for mode <- modes do
  IO.puts("#{mode}:")

  case mode do
    :default ->
      IO.puts("  - All tools go through permission callback")
      IO.puts("  - Full security control")

    :accept_edits ->
      IO.puts("  - Edit operations (Write, Edit) auto-allowed")
      IO.puts("  - Other tools still checked")

    :plan ->
      IO.puts("  - User approval required for tool execution")
      IO.puts("  - Integrated with Claude CLI's plan mode")

    :bypass_permissions ->
      IO.puts("  - All tools allowed without callbacks")
      IO.puts("  - Use with caution!")
  end

  IO.puts("")
end

# Create client with permission callback
IO.puts("Creating client with permission callback in default mode...\n")

options =
  Options.new(
    permission_mode: :default,
    can_use_tool: permission_callback,
    max_turns: 1
  )

{:ok, client} = Client.start_link(options)
IO.puts("✅ Client started with permission controls")

# Demonstrate runtime mode switching
IO.puts("\n🔄 Runtime permission mode switching:\n")

for mode <- [:plan, :accept_edits, :bypass_permissions, :default] do
  :ok = Client.set_permission_mode(client, mode)
  state = :sys.get_state(client)
  IO.puts("Switched to: #{state.options.permission_mode}")
end

Client.stop(client)

# Show permission log
IO.puts("\n📊 Permission Check Log:")
logs = :ets.tab2list(permission_log)
IO.puts("Total checks: #{length(logs)}\n")

for {_timestamp, tool, input} <- Enum.sort(logs) do
  input_preview =
    case input do
      %{"command" => cmd} -> "command: #{String.slice(cmd, 0..30)}..."
      %{"file_path" => path} -> "file: #{path}"
      other -> inspect(other) |> String.slice(0..30)
    end

  IO.puts("  - #{tool}: #{input_preview}")
end

:ets.delete(permission_log)

IO.puts("\n✅ Permission Control example complete!")
IO.puts("\nKey takeaways:")
IO.puts("  - Define can_use_tool callback for fine-grained control")
IO.puts("  - Block dangerous operations before execution")
IO.puts("  - Redirect operations to safe locations")
IO.puts("  - Log all tool usage for audit trails")
IO.puts("  - Switch permission modes at runtime")
IO.puts("  - Callbacks can modify tool inputs")
IO.puts("  - Callbacks can interrupt execution for critical violations")
