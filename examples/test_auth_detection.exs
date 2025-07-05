#!/usr/bin/env elixir

# Test script to verify challenge URL detection
# This script attempts to trigger authentication to see if we can detect the challenge URL

alias ClaudeCodeSDK.Options

IO.puts("🧪 Testing Challenge URL Detection")
IO.puts("=" |> String.duplicate(60))

# Force a new authentication by using invalid credentials
# This should trigger the CLI to show a challenge URL
System.put_env("ANTHROPIC_API_KEY", "invalid_key_to_trigger_auth")

options = %Options{
  max_turns: 1,
  verbose: true
}

IO.puts("\n🔍 Attempting to query Claude with invalid credentials...")
IO.puts("This should trigger a challenge URL if authentication is needed.\n")

try do
  ClaudeCodeSDK.query("Hello", options)
  |> Enum.each(fn msg ->
    IO.inspect(msg, label: "Message")
    
    # Check if we got an authentication_required message
    if msg.type == :result and msg.subtype == :authentication_required do
      IO.puts("\n✅ Challenge URL detection successful!")
      IO.puts("Challenge URL: #{msg.data.challenge_url}")
    end
  end)
rescue
  e ->
    IO.puts("\n❌ Error occurred:")
    IO.inspect(e)
end

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Test complete.")