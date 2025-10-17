#!/usr/bin/env elixir

# Example 4: Logging and Audit Trail with LIVE CLI
#
# This example demonstrates using hooks to create comprehensive audit logs
# of all tool usage with the actual Claude CLI.
#
# Run: mix run examples/hooks/logging_and_audit.exs

alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.Matcher

defmodule AuditHooks do
  @moduledoc """
  Hooks for comprehensive logging and audit trails.
  """

  @doc """
  PreToolUse hook that logs tool invocations.
  """
  def log_tool_invocation(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_input = input["tool_input"]

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # Simulated logging (in real app, write to file or database)
    IO.puts("\n📝 [AUDIT LOG] #{timestamp}")
    IO.puts("   Event: Tool Invocation")
    IO.puts("   Tool: #{tool_name}")
    IO.puts("   ID: #{tool_use_id}")
    IO.puts("   Input: #{inspect(tool_input, limit: :infinity)}")

    # Don't modify behavior, just log
    %{}
  end

  @doc """
  PostToolUse hook that logs tool results.
  """
  def log_tool_result(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_response = input["tool_response"]

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # Determine success/failure
    is_error = get_in(tool_response, ["is_error"]) || false
    status = if is_error, do: "FAILED", else: "SUCCESS"
    status_icon = if is_error, do: "❌", else: "✅"

    IO.puts("\n📝 [AUDIT LOG] #{timestamp}")
    IO.puts("   Event: Tool Completion")
    IO.puts("   Tool: #{tool_name}")
    IO.puts("   Status: #{status_icon} #{status}")
    IO.puts("   ID: #{tool_use_id}")

    %{}
  end
end

# Configure hooks for comprehensive logging
hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&AuditHooks.log_tool_invocation/3])
  ],
  post_tool_use: [
    Matcher.new("*", [&AuditHooks.log_tool_result/3])
  ]
}

options = %Options{
  allowed_tools: ["Bash", "Read", "Write"],
  hooks: hooks
}

IO.puts("=" <> String.duplicate("=", 79))
IO.puts("🎣 Hooks Example: Logging and Audit Trail (LIVE)")
IO.puts("=" <> String.duplicate("=", 79))
IO.puts("\nStarting Claude CLI with audit logging hooks enabled...")

# Start client with hooks
{:ok, client} = Client.start_link(options)

IO.puts("✅ Client started with PreToolUse and PostToolUse hooks for all tools\n")

# Execute a few operations to demonstrate logging
IO.puts("\n📝 Executing operations (will be logged)...")
IO.puts("-" <> String.duplicate("-", 79))

Client.send_message(client, "Run: echo 'Hello from audit example'")
Process.sleep(2000)

Client.send_message(client, "Read the file /tmp/test.txt")
Process.sleep(2000)

# Clean up
IO.puts("\n\nStopping client...")
Client.stop(client)

IO.puts("\n\n✨ Example completed!")
IO.puts("\n📚 Key Takeaways:")
IO.puts("   - PreToolUse hooks log before execution")
IO.puts("   - PostToolUse hooks log after execution")
IO.puts("   - Wildcard matcher (*) applies to ALL tools")
IO.puts("   - Hooks enable comprehensive audit trails")
IO.puts("   - Useful for compliance, debugging, and monitoring")
