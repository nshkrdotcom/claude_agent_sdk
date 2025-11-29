#!/usr/bin/env elixir

# Example 5: Complete Workflow - All Hooks Together with LIVE CLI
#
# This example demonstrates multiple hooks working together to create
# a secure, monitored, and intelligent agent system with the actual Claude CLI.
#
# Run: mix run examples/hooks/complete_workflow.exs

alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

defmodule CompleteWorkflow do
  @moduledoc """
  Complete hooks workflow demonstrating security, logging, context, and
  per-matcher hook timeouts.
  """

  require Logger

  # Security policy
  @forbidden_patterns ["rm -rf", "dd if=", "mkfs"]
  @allowed_sandbox "/tmp/sandbox"
  @pre_tool_timeout_ms 1_200
  @context_timeout_ms 3_000
  def pre_tool_timeout_ms, do: @pre_tool_timeout_ms
  def context_timeout_ms, do: @context_timeout_ms

  @doc """
  Security validation hook (PreToolUse).
  Validates bash commands and file operations.
  """
  def security_validation(input, tool_use_id, _context) do
    Logger.info("Security check", tool_use_id: tool_use_id, tool: input["tool_name"])

    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
        if Enum.any?(@forbidden_patterns, &String.contains?(cmd, &1)) do
          IO.puts("\n🚫 SECURITY: Blocked dangerous command: #{cmd}")

          Output.deny("Dangerous command blocked")
          |> Output.with_system_message("🔒 Security policy violation")
        else
          IO.puts("\n✅ SECURITY: Approved bash command")
          %{}
        end

      %{"tool_name" => tool, "tool_input" => %{"file_path" => path}}
      when tool in ["Write", "Edit"] ->
        if not String.starts_with?(path, @allowed_sandbox) do
          IO.puts("\n🚫 SECURITY: File access outside sandbox: #{path}")

          Output.deny("Must operate within #{@allowed_sandbox}")
          |> Output.with_system_message("🔒 Sandbox restriction")
        else
          IO.puts("\n✅ SECURITY: Approved file operation: #{path}")
          %{}
        end

      _ ->
        %{}
    end
  end

  @doc """
  Audit logging hook (PreToolUse).
  Logs all tool invocations.
  """
  def audit_log(input, tool_use_id, _context) do
    # Simulate modest work to show timebox still succeeds under timeout
    Process.sleep(200)
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    tool_name = input["tool_name"]

    IO.puts("\n📝 [AUDIT] #{timestamp} - #{tool_name} (#{tool_use_id})")
    Logger.info("Tool invoked", timestamp: timestamp, tool: tool_name, id: tool_use_id)

    %{}
  end

  @doc """
  Context injection hook (UserPromptSubmit).
  Adds security and environment context to prompts.
  """
  def add_context(_input, _tool_use_id, _context) do
    # Simulate a slower context collection to demonstrate custom timeout budget
    Process.sleep(500)

    context_text = """
    ## 🔒 Security Context
    - Bash commands restricted: No rm -rf, dd, mkfs
    - File operations sandboxed to: #{@allowed_sandbox}
    - All operations are logged
    - Environment: #{System.get_env("MIX_ENV", "dev")}
    """

    IO.puts("\n📎 Injecting security context...")

    Output.add_context("UserPromptSubmit", context_text)
  end

  @doc """
  Execution monitoring hook (PostToolUse).
  Tracks tool execution and adds metadata.
  """
  def monitor_execution(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_response = input["tool_response"]

    is_error = get_in(tool_response, ["is_error"]) || false
    status = if is_error, do: "❌ FAILED", else: "✅ SUCCESS"

    IO.puts("\n📊 MONITOR: #{tool_name} - #{status} (#{tool_use_id})")
    Logger.info("Tool completed", tool: tool_name, success: not is_error, id: tool_use_id)

    %{}
  end
end

# Configure complete workflow with all hooks
hooks = %{
  # Security validation and audit logging (both run on PreToolUse)
  pre_tool_use: [
    Matcher.new("*", [&CompleteWorkflow.audit_log/3, &CompleteWorkflow.security_validation/3],
      timeout_ms: CompleteWorkflow.pre_tool_timeout_ms()
    )
  ],
  # Context injection on prompts
  user_prompt_submit: [
    Matcher.new(nil, [&CompleteWorkflow.add_context/3],
      timeout_ms: CompleteWorkflow.context_timeout_ms()
    )
  ],
  # Execution monitoring
  post_tool_use: [
    Matcher.new("*", [&CompleteWorkflow.monitor_execution/3])
  ]
}

options = %Options{
  allowed_tools: ["Bash", "Read", "Write"],
  hooks: hooks
}

IO.puts("=" <> String.duplicate("=", 79))
IO.puts("🎣 Hooks Example: Complete Workflow (LIVE)")
IO.puts("=" <> String.duplicate("=", 79))
IO.puts("\nStarting Claude CLI with complete hooks workflow...")
IO.puts("  - Security validation (PreToolUse)")
IO.puts("  - Audit logging (PreToolUse)")
IO.puts("    • Per-matcher timeout: #{CompleteWorkflow.pre_tool_timeout_ms()} ms")
IO.puts("  - Context injection (UserPromptSubmit)")
IO.puts("    • Per-matcher timeout: #{CompleteWorkflow.context_timeout_ms()} ms")
IO.puts("  - Execution monitoring (PostToolUse)\n")

# Start client with hooks
{:ok, client} = Client.start_link(options)

IO.puts("✅ Client started with complete workflow\n")

# Test 1: Safe operation
IO.puts("\n📝 Test 1: Safe bash command")
IO.puts("-" <> String.duplicate("-", 79))

Client.send_message(client, "Echo 'Hello from complete workflow'")
Process.sleep(2000)

# Test 2: File operation in sandbox
IO.puts("\n\n📝 Test 2: File operation (sandboxed)")
IO.puts("-" <> String.duplicate("-", 79))

Client.send_message(client, "Write 'test data' to /tmp/sandbox/file.txt")
Process.sleep(2000)

# Test 3: Dangerous command (will be blocked)
IO.puts("\n\n📝 Test 3: Dangerous command (will be blocked)")
IO.puts("-" <> String.duplicate("-", 79))

Client.send_message(client, "Run: rm -rf /tmp/data")
Process.sleep(2000)

# Clean up
IO.puts("\n\nStopping client...")
Client.stop(client)

IO.puts("\n\n✨ Complete Workflow Demonstration Finished!")
IO.puts("\n📚 Key Takeaways:")
IO.puts("   - Multiple hooks can work together seamlessly")
IO.puts("   - Layered security: validation + logging + context + monitoring")
IO.puts("   - Hooks compose naturally (multiple callbacks per event)")
IO.puts("   - Complete control over Claude's execution environment")
IO.puts("   - Production-ready security and audit capabilities")
