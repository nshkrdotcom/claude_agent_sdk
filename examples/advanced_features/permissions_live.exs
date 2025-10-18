#!/usr/bin/env elixir
# Permissions Live Example
# Demonstrates permission system with REAL Claude CLI usage
#
# Usage:
#   MIX_ENV=test mix run.live examples/advanced_features/permissions_live.exs
#
# Prerequisites:
#   - Claude CLI installed and authenticated (claude login)

alias ClaudeAgentSDK.{Options, ContentExtractor}
alias ClaudeAgentSDK.Permission.{Context, Result}

# Check if we're in mock mode - these are LIVE examples only
if Application.get_env(:claude_agent_sdk, :use_mock, false) do
  IO.puts("\n🎭 This is a LIVE example - it requires real API calls")
  IO.puts("   For permission configuration demo (mock mode), see:")
  IO.puts("   mix run examples/advanced_features/permission_control.exs\n")
  IO.puts("💡 To run this live example:")
  IO.puts("   MIX_ENV=test mix run.live examples/advanced_features/permissions_live.exs\n")
  System.halt(0)
end

IO.puts("🔴 Running in LIVE mode (real API calls)")
IO.puts("⚠️  Warning: This will make actual API calls and may incur costs!\n")

IO.puts("\n=== Permissions Live Example ===\n")

# Define permission callback with logging
permission_log = :ets.new(:perm_log, [:public, :bag])

permission_callback = fn context ->
  timestamp = DateTime.utc_now() |> DateTime.to_string()
  :ets.insert(permission_log, {timestamp, context.tool_name, context.tool_input})

  case {context.tool_name, context.tool_input} do
    {"Bash", %{"command" => cmd}} ->
      # Block dangerous commands
      if String.contains?(cmd, ["rm -rf", "dd if=", "mkfs", "> /dev/"]) do
        IO.puts("🚫 BLOCKED dangerous bash: #{String.slice(cmd, 0..50)}")
        Result.deny("Dangerous command not allowed for safety", interrupt: true)
      else
        IO.puts("✅ ALLOWED bash: #{String.slice(cmd, 0..50)}")
        Result.allow()
      end

    {"Write", %{"file_path" => path}} ->
      # Log all writes
      IO.puts("📝 LOGGED write to: #{path}")
      Result.allow()

    {"Read", %{"file_path" => path}} ->
      IO.puts("📖 LOGGED read from: #{path}")
      Result.allow()

    {tool, _input} ->
      IO.puts("✅ ALLOWED: #{tool}")
      Result.allow()
  end
end

IO.puts("✅ Permission callback configured\n")

# Create options with permissions
options =
  Options.new(
    permission_mode: :default,
    can_use_tool: permission_callback,
    max_turns: 5
  )

# Task: Ask Claude to list files
prompt = """
Please list the files in the current directory using bash.
Just run 'ls -la' and show me the output briefly.
"""

IO.puts("📤 Asking Claude to list files...\n")
IO.puts("Prompt: #{prompt}\n")

# Execute query
messages =
  ClaudeAgentSDK.query(prompt, options)
  |> Enum.to_list()

# Extract and display response
text = ContentExtractor.extract_content_text(messages)

if text != "" do
  IO.puts("💬 Claude's Response:")
  IO.puts("─" |> String.duplicate(60))
  IO.puts(String.slice(text, 0..300))
  if String.length(text) > 300, do: IO.puts("... (truncated)")
  IO.puts("─" |> String.duplicate(60))
end

IO.puts("\n✅ Task complete\n")

# Show permission log
IO.puts("📊 Permission Log:")
logs = :ets.tab2list(permission_log) |> Enum.reverse()
IO.puts("Total permission checks: #{length(logs)}\n")

for {timestamp, tool, input} <- logs do
  input_str =
    case input do
      %{"command" => cmd} -> "command: #{String.slice(cmd, 0..40)}"
      %{"file_path" => path} -> "file: #{path}"
      other -> inspect(other) |> String.slice(0..40)
    end

  time_short = timestamp |> String.slice(11..18)
  IO.puts("  [#{time_short}] #{tool}: #{input_str}")
end

:ets.delete(permission_log)

IO.puts("\n✅ Permissions Live Example complete!")
IO.puts("\nWhat happened:")
IO.puts("  1. Set up permission callback to log all tool usage")
IO.puts("  2. Claude used bash to list files")
IO.puts("  3. Permission callback was invoked for each tool use")
IO.puts("  4. Tool usage was logged for audit trail")
IO.puts("  5. Safe commands were allowed, dangerous would be blocked")
IO.puts("\n💡 Permission callbacks give you:")
IO.puts("  - Complete audit trail of all tool usage")
IO.puts("  - Ability to block dangerous operations")
IO.puts("  - Ability to redirect file paths to safe locations")
IO.puts("  - Runtime control over what Claude can do")
