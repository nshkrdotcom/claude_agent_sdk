#!/usr/bin/env elixir

# Test the new erlexec-based implementation

IO.puts("🚀 Testing Erlexec-based Claude Code SDK")
IO.puts("=" |> String.duplicate(50))

# Load modules
Code.require_file("lib/claude_code_sdk/options.ex")
Code.require_file("lib/claude_code_sdk/message.ex")
Code.require_file("lib/claude_code_sdk/process.ex")
Code.require_file("lib/claude_code_sdk/query.ex")
Code.require_file("lib/claude_code_sdk.ex")

# Test 1: Basic functionality
IO.puts("\n📝 Test 1: Basic Query")
try do
  ClaudeCodeSDK.query("Say 'Hello from erlexec SDK!' in exactly 5 words")
  |> Enum.each(fn msg ->
    case msg.type do
      :system ->
        IO.puts("📋 Session: #{msg.data.session_id}")
        IO.puts("   Model: #{msg.data.model}")
        
      :assistant ->
        content = msg.data.message["content"]
        IO.puts("\n🤖 Claude: #{content}")
        
      :result ->
        if msg.subtype == :success do
          IO.puts("\n✅ Success!")
          IO.puts("   Cost: $#{msg.data.total_cost_usd}")
          IO.puts("   Duration: #{msg.data.duration_ms}ms")
          IO.puts("   Turns: #{msg.data.num_turns}")
        else
          IO.puts("\n❌ Error: #{inspect(msg.data)}")
        end
        
      _ ->
        IO.puts("   Other: #{msg.type}")
    end
  end)
rescue
  e ->
    IO.puts("\n❌ Error in test 1: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end

# Test 2: With options
IO.puts("\n\n📝 Test 2: Query with Options")
try do
  opts = ClaudeCodeSDK.Options.new(
    max_turns: 1,
    system_prompt: "You are a helpful assistant. Be very concise."
  )
  
  ClaudeCodeSDK.query("What is 2+2?", opts)
  |> Stream.filter(& &1.type == :assistant)
  |> Enum.each(fn msg ->
    IO.puts("🤖 Claude: #{msg.data.message["content"]}")
  end)
rescue
  e ->
    IO.puts("❌ Error in test 2: #{inspect(e)}")
end

# Test 3: Error handling
IO.puts("\n\n📝 Test 3: Error Handling")
try do
  # Test with invalid options or authentication issues
  result = ClaudeCodeSDK.query("test")
  |> Enum.find(& &1.type == :result)
  
  if result && ClaudeCodeSDK.Message.error?(result) do
    IO.puts("❌ Expected error handled correctly")
  else
    IO.puts("✅ Query succeeded")
  end
rescue
  e ->
    IO.puts("❌ Error in test 3: #{inspect(e)}")
end

IO.puts("\n\n🏁 All tests completed!")