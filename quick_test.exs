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
      if msg.subtype != :success do
        IO.puts("\n❌ Error (#{msg.subtype}):")
        if Map.has_key?(msg.data, :error) do
          IO.puts(msg.data.error)
        else
          IO.puts(inspect(msg.data))
        end
        System.halt(1)
      end
    _ ->
      :ok
  end
end)

# Test 2: Code generation
IO.puts("\n\n📝 Test 2: Generate Elixir code")
try do
  messages = ClaudeCodeSDK.query("Write a simple Elixir function that reverses a string")
  |> Enum.to_list()

  # Check for errors first
  error_msg = Enum.find(messages, & &1.type == :result and &1.subtype != :success)
  if error_msg do
    IO.puts("❌ Error (#{error_msg.subtype}):")
    if Map.has_key?(error_msg.data, :error) do
      IO.puts(error_msg.data.error)
    else
      IO.puts(inspect(error_msg.data))
    end
    System.halt(1)
  else
    messages
    |> Enum.filter(& &1.type == :assistant)
    |> Enum.each(fn msg ->
      IO.puts("\nClaude's response:")
      IO.puts(msg.data.message["content"])
    end)
  end
rescue
  e ->
    IO.puts("❌ Error in test 2: #{inspect(e)}")
    System.halt(1)
end

# Test 3: With options
IO.puts("\n\n📝 Test 3: Query with options")
try do
  opts = ClaudeCodeSDK.Options.new(
    max_turns: 1,
    verbose: false
  )

  messages = ClaudeCodeSDK.query("What is 2 + 2? Just give the number.", opts)
  |> Enum.to_list()

  # Check for errors first
  error_msg = Enum.find(messages, & &1.type == :result and &1.subtype != :success)
  if error_msg do
    IO.puts("❌ Error (#{error_msg.subtype}):")
    if Map.has_key?(error_msg.data, :error) do
      IO.puts(error_msg.data.error)
    else
      IO.puts(inspect(error_msg.data))
    end
    System.halt(1)
  else
    messages
    |> Enum.filter(& &1.type == :assistant)
    |> Enum.each(fn msg ->
      IO.puts("Answer: #{msg.data.message["content"]}")
    end)
  end
rescue
  e ->
    IO.puts("❌ Error in test 3: #{inspect(e)}")
    System.halt(1)
end

IO.puts("\n✅ All tests completed!")
