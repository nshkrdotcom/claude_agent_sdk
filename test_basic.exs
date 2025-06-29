#!/usr/bin/env elixir

# Basic test to ensure the SDK works
# Run with: elixir test_basic.exs

IO.puts("Testing Claude Code SDK...")

# Test 1: Check if claude CLI is available
case System.find_executable("claude") do
  nil ->
    IO.puts("❌ Claude CLI not found. Please install with: npm install -g @anthropic-ai/claude-code")
    System.halt(1)
  path ->
    IO.puts("✅ Claude CLI found at: #{path}")
end

# Test 2: Note about authentication
IO.puts("ℹ️  Using authenticated Claude CLI session")

# Test 3: Simple query
IO.puts("\nTesting simple query...")
try do
  messages = 
    ClaudeCodeSDK.query("Say 'Hello from Elixir SDK!' and nothing else")
    |> Enum.to_list()
  
  IO.puts("✅ Received #{length(messages)} messages")
  
  # Check message types
  types = Enum.map(messages, & &1.type) |> Enum.uniq()
  IO.puts("   Message types: #{inspect(types)}")
  
  # Find assistant message
  assistant_msg = Enum.find(messages, & &1.type == :assistant)
  if assistant_msg do
    content = assistant_msg.data.message["content"]
    IO.puts("   Claude said: #{String.trim(content)}")
  end
  
  # Find result message
  result_msg = Enum.find(messages, & &1.type == :result)
  if result_msg do
    IO.puts("   Session ID: #{result_msg.data.session_id}")
    IO.puts("   Success: #{result_msg.subtype == :success}")
  end
  
rescue
  e ->
    IO.puts("❌ Error: #{inspect(e)}")
    System.halt(1)
catch
  :exit, {:port_terminated, _} ->
    IO.puts("❌ Claude CLI terminated unexpectedly")
    IO.puts("   This usually means you need to authenticate first")
    IO.puts("   Run: claude login")
    System.halt(1)
end

IO.puts("\n✅ All tests passed!")