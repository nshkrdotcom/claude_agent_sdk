#!/usr/bin/env elixir

# Example 1: Block Dangerous Bash Commands with LIVE CLI
#
# This example demonstrates using a PreToolUse hook to block dangerous
# bash commands before they execute using the actual Claude CLI.
#
# Run: mix run examples/hooks/basic_bash_blocking.exs

alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

defmodule SecurityHooks do
  @moduledoc """
  Security hooks for blocking dangerous commands.
  """

  @doc """
  PreToolUse hook that blocks dangerous bash commands.

  Checks for patterns like:
  - rm -rf
  - dd if=
  - mkfs
  - > /dev/

  Returns:
  - deny output if dangerous pattern found
  - allow output otherwise
  """
  def check_bash_command(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => command}} ->
        dangerous_patterns = ["rm -rf", "dd if=", "mkfs", "> /dev/"]

        if Enum.any?(dangerous_patterns, &String.contains?(command, &1)) do
          IO.puts("\n🚫 BLOCKED: Dangerous command detected!")
          IO.puts("   Command: #{command}\n")

          Output.deny("Dangerous command blocked: #{command}")
          |> Output.with_system_message("🔒 Security policy violation")
          |> Output.with_reason("This command could cause data loss or system damage")
        else
          IO.puts("\n✅ ALLOWED: Safe command")
          IO.puts("   Command: #{command}\n")

          Output.allow("Security check passed")
        end

      _ ->
        # Not a Bash command, allow
        %{}
    end
  end
end

# Configure hooks for use with live Client
hooks = %{
  pre_tool_use: [
    Matcher.new("Bash", [&SecurityHooks.check_bash_command/3])
  ]
}

options = %Options{
  allowed_tools: ["Bash"],
  hooks: hooks
}

IO.puts("=" <> String.duplicate("=", 79))
IO.puts("🎣 Hooks Example: Basic Bash Command Blocking (LIVE)")
IO.puts("=" <> String.duplicate("=", 79))
IO.puts("\nThis example demonstrates PreToolUse hooks with the actual Claude CLI.")
IO.puts("The hook will be invoked when Claude tries to use the Bash tool.\n")

# Start client with hooks
{:ok, client} = Client.start_link(options)

IO.puts("✅ Client started with PreToolUse hook for Bash commands")

# Start a task to listen for messages
listener =
  Task.async(fn ->
    Client.stream_messages(client)
    # Take first 5 messages
    |> Enum.take(5)
    |> Enum.to_list()
  end)

# Give it a moment to initialize
Process.sleep(1000)

# Test 1: Send a message that will cause Claude to use Bash (safe command)
IO.puts("\n📝 Test 1: Asking Claude to run a safe command")
IO.puts("-" <> String.duplicate("-", 79))

Client.send_message(
  client,
  "Please use the Bash tool to run this exact command: echo 'Hello from hooks!'"
)

IO.puts("\nWaiting for Claude to respond and invoke the Bash tool...")
IO.puts("(The hook will be called when Claude tries to use the tool)\n")

# Wait for responses
messages = Task.await(listener, 30_000)

IO.puts("\n📊 Received #{length(messages)} messages from Claude")

# Clean up
IO.puts("\nStopping client...")
Client.stop(client)

IO.puts("\n\n✨ Example completed!")
IO.puts("\n📚 Key Takeaways:")
IO.puts("   - Hooks are invoked when Claude tries to use tools")
IO.puts("   - PreToolUse hooks can allow or deny tool usage")
IO.puts("   - Hooks run BEFORE the actual tool execution")
IO.puts("   - This provides a security layer for tool usage")
IO.puts("\n⚠️  Note: To see dangerous command blocking, Claude would need to")
IO.puts("   decide to run a dangerous command. For a full demo, try using")
IO.puts("   the complete_workflow.exs example which shows multiple scenarios.")
