#!/usr/bin/env elixir

# Example 3: File Policy Enforcement with LIVE CLI
#
# This example demonstrates how to write file policy hooks and shows
# them working with test data (simulated tool calls).
#
# Run: mix run examples/hooks/file_policy_enforcement.exs

alias ClaudeAgentSDK.Hooks.Output

defmodule FilePolicyHooks do
  @moduledoc """
  Security policy enforcement for file operations.
  """

  # Define allowed and forbidden paths
  @allowed_directory "/tmp/sandbox"
  @forbidden_files [".env", "secrets.yml", "credentials.json"]

  @doc """
  PreToolUse hook that enforces file access policies.

  Policy rules:
  1. Cannot modify .env, secrets, or credential files
  2. Must operate within /tmp/sandbox directory for writes

  Returns:
  - deny output if policy violated
  - allow output if policy satisfied
  """
  def enforce_file_policy(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => tool_name, "tool_input" => %{"file_path" => path}}
      when tool_name in ["Write", "Edit"] ->
        check_write_policy(tool_name, path)

      _ ->
        # Not a file write operation, allow
        %{}
    end
  end

  defp check_write_policy(tool_name, path) do
    cond do
      # Check forbidden file names
      Enum.any?(@forbidden_files, &String.ends_with?(path, &1)) ->
        filename = Path.basename(path)

        IO.puts("\n🚫 BLOCKED: Cannot modify #{filename}")

        Output.deny("Cannot modify #{filename}")
        |> Output.with_system_message("🔒 Security policy: Sensitive file")
        |> Output.with_reason("Modification of #{filename} is forbidden by policy")

      # Check allowed directory
      not String.starts_with?(path, @allowed_directory) ->
        IO.puts("\n🚫 BLOCKED: Must operate within #{@allowed_directory}")

        Output.deny("Can only modify files in #{@allowed_directory}")
        |> Output.with_system_message("🔒 Security policy: Sandbox restriction")
        |> Output.with_reason("File path #{path} is outside allowed directory")

      # Passes all checks
      true ->
        IO.puts("\n✅ ALLOWED: #{tool_name} #{path}")

        Output.allow("File policy check passed")
    end
  end
end

IO.puts("=" <> String.duplicate("=", 79))
IO.puts("🎣 Hooks Example: File Policy Enforcement")
IO.puts("=" <> String.duplicate("=", 79))
IO.puts("\nThis example demonstrates file access policy enforcement using hooks.")
IO.puts("We'll test the policy logic with simulated tool calls.\n")

IO.puts("📋 Policy Rules:")
IO.puts("  ✓ Allow writes to: #{"/tmp/sandbox"}")
IO.puts("  ✗ Block writes to: .env, secrets.yml, credentials.json")
IO.puts("  ✗ Block writes outside sandbox\n")

# Test the hook with simulated inputs
IO.puts(String.duplicate("=", 80))
IO.puts("🧪 Testing File Policy Hook")
IO.puts(String.duplicate("=", 80))

# Test 1: Allowed write
IO.puts("\n📝 Test 1: Write to allowed location")
IO.puts("-" <> String.duplicate("-", 79))

input1 = %{
  "tool_name" => "Write",
  "tool_input" => %{"file_path" => "/tmp/sandbox/test.txt"}
}

result1 = FilePolicyHooks.enforce_file_policy(input1, "test_001", %{})

IO.puts(
  "\nHook result: #{inspect(get_in(result1, [:hookSpecificOutput, :permissionDecision]) || "allow")}"
)

# Test 2: Blocked - .env file
IO.puts("\n\n📝 Test 2: Try to write .env file (should be blocked)")
IO.puts("-" <> String.duplicate("-", 79))

input2 = %{
  "tool_name" => "Write",
  "tool_input" => %{"file_path" => "/tmp/project/.env"}
}

result2 = FilePolicyHooks.enforce_file_policy(input2, "test_002", %{})

IO.puts(
  "\nHook result: #{inspect(get_in(result2, [:hookSpecificOutput, :permissionDecision]) || "allow")}"
)

# Test 3: Blocked - outside sandbox
IO.puts("\n\n📝 Test 3: Try to write outside sandbox (should be blocked)")
IO.puts("-" <> String.duplicate("-", 79))

input3 = %{
  "tool_name" => "Write",
  "tool_input" => %{"file_path" => "/home/user/file.txt"}
}

result3 = FilePolicyHooks.enforce_file_policy(input3, "test_003", %{})

IO.puts(
  "\nHook result: #{inspect(get_in(result3, [:hookSpecificOutput, :permissionDecision]) || "allow")}"
)

# Test 4: Allowed - another sandbox file
IO.puts("\n\n📝 Test 4: Edit within sandbox (should be allowed)")
IO.puts("-" <> String.duplicate("-", 79))

input4 = %{
  "tool_name" => "Edit",
  "tool_input" => %{"file_path" => "/tmp/sandbox/config.json"}
}

result4 = FilePolicyHooks.enforce_file_policy(input4, "test_004", %{})

IO.puts(
  "\nHook result: #{inspect(get_in(result4, [:hookSpecificOutput, :permissionDecision]) || "allow")}"
)

IO.puts("\n\n" <> String.duplicate("=", 80))
IO.puts("✨ Testing Complete!")
IO.puts(String.duplicate("=", 80))

IO.puts("""

📊 Summary:
  Test 1 (sandbox write):      ✅ ALLOWED
  Test 2 (.env file):          🚫 BLOCKED
  Test 3 (outside sandbox):    🚫 BLOCKED
  Test 4 (sandbox edit):       ✅ ALLOWED

📚 Key Takeaways:
   - Hooks can enforce complex security policies
   - Pattern matching makes policy logic clear
   - Deny responses prevent dangerous operations
   - systemMessage and reason provide context to user and Claude

💡 Integration with Live CLI:
   When connected to Claude CLI with these hooks configured, the policy
   will automatically enforce whenever Claude tries to use Write or Edit tools.

   To see it in action with live Claude, configure the hooks in your Options
   and start a Client - the hooks will fire automatically when Claude attempts
   file operations!
""")
