#!/usr/bin/env elixir

# Quick test script for Claude Code SDK
# Run with: ./run_quick_test.sh

IO.puts("🚀 Claude Code SDK Quick Test")
IO.puts("=" |> String.duplicate(40))

# Test 1: Simple query
IO.puts("\n📝 Test 1: Simple greeting")
ClaudeCodeSDK.query("Say 'Hello from Elixir SDK!' in a friendly way")
|> Enum.each(fn msg ->
  case msg.type do
    :assistant ->
      IO.puts("Claude: #{msg.data.message["content"]}")
    :result ->
      if msg.subtype == :error_during_execution do
        IO.puts("\n❌ Error: Not authenticated. Run 'claude login' first!")
        System.halt(1)
      end
    _ ->
      :ok
  end
end)

# Test 2: Code generation
IO.puts("\n\n📝 Test 2: Generate Elixir code")
ClaudeCodeSDK.query("Write a simple Elixir function that reverses a string")
|> Stream.filter(& &1.type == :assistant)
|> Enum.each(fn msg ->
  IO.puts("\nClaude's response:")
  IO.puts(msg.data.message["content"])
end)

# Test 3: With options
IO.puts("\n\n📝 Test 3: Query with options")
opts = ClaudeCodeSDK.Options.new(
  max_turns: 1,
  verbose: false
)

ClaudeCodeSDK.query("What is 2 + 2? Just give the number.", opts)
|> Stream.filter(& &1.type == :assistant)
|> Stream.map(& &1.data.message["content"])
|> Enum.each(&IO.puts("Answer: #{&1}"))

IO.puts("\n✅ All tests completed!")