#!/usr/bin/env elixir

# Simple auth diagnostic
# Tests if Claude CLI can use CLAUDE_AGENT_OAUTH_TOKEN

IO.puts("🔍 Testing Authentication Methods")
IO.puts("")

# Check what env vars are set
oauth_token = System.get_env("CLAUDE_AGENT_OAUTH_TOKEN")
api_key = System.get_env("ANTHROPIC_API_KEY")

IO.puts("Environment variables:")

IO.puts(
  "  CLAUDE_AGENT_OAUTH_TOKEN: #{if oauth_token, do: String.slice(oauth_token, 0, 30) <> "...", else: "NOT SET"}"
)

IO.puts(
  "  ANTHROPIC_API_KEY: #{if api_key, do: String.slice(api_key, 0, 30) <> "...", else: "NOT SET"}"
)

IO.puts("")

# Test with System.cmd directly (bypassing SDK)
IO.puts("Testing CLI directly with System.cmd...")

case System.cmd("claude", ["--print", "test", "--output-format", "json"], stderr_to_stdout: true) do
  {output, 0} ->
    IO.puts("✅ CLI executed successfully")

    # Check if it's an auth error
    if String.contains?(output, "authentication_error") or
         String.contains?(output, "Invalid bearer token") do
      IO.puts("❌ But got authentication error!")
      IO.puts("")
      IO.puts("Error in output:")
      IO.puts(String.slice(output, 0, 500))
      IO.puts("")
      IO.puts("❌ CLAUDE CLI CANNOT SEE THE TOKEN VIA ENV VAR")
      IO.puts("")
      IO.puts("Solution: The CLI likely doesn't use CLAUDE_AGENT_OAUTH_TOKEN automatically.")
      IO.puts("You need to either:")
      IO.puts("  1. Run 'claude login' to create a stored session")
      IO.puts("  2. Find out how to pass OAuth token to CLI")
    else
      IO.puts("✅ Authentication working!")
      IO.puts("Response preview:")
      IO.puts(String.slice(output, 0, 200))
    end

  {error, code} ->
    IO.puts("❌ CLI failed (exit #{code})")
    IO.puts(error)
end

IO.puts("")
IO.puts("Now testing through SDK...")
IO.puts("")

# Disable mocking
Application.put_env(:claude_agent_sdk, :use_mock, false)

# Test through SDK
try do
  result = ClaudeAgentSDK.query("test") |> Enum.to_list()

  assistant_msg = Enum.find(result, &(&1.type == :assistant))

  if assistant_msg do
    response = ClaudeAgentSDK.ContentExtractor.extract_text(assistant_msg)

    if String.contains?(response, "authentication_error") do
      IO.puts("❌ SDK query got auth error")
      IO.puts("Error: #{String.slice(response, 0, 200)}")
    else
      IO.puts("✅ SDK query succeeded!")
      IO.puts("Response: #{String.slice(response, 0, 100)}")
    end
  else
    IO.puts("❌ No assistant message received")
  end
rescue
  e ->
    IO.puts("❌ Exception: #{Exception.message(e)}")
end
