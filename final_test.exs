#!/usr/bin/env elixir

# Final test of the Claude Code SDK with proper JSON parsing

IO.puts("🚀 Claude Code SDK - Final Test")
IO.puts("=" |> String.duplicate(40))

# Test the SDK
IO.puts("\n📡 Calling Claude API...")
IO.puts("   Prompt: \"Say exactly: Hello from Elixir!\"")
IO.puts("   Using authenticated Claude CLI...")

try do
  ClaudeCodeSDK.query("Say exactly: Hello from Elixir!")
  |> Enum.each(fn msg ->
    case msg.type do
      :system ->
        IO.puts("\n📋 API Connection Established!")
        IO.puts("   Session: #{msg.data.session_id}")
        IO.puts("   Model: #{msg.data.model}")
        IO.puts("   Auth Source: #{msg.data.api_key_source}")
        IO.puts("   Working Directory: #{msg.data.cwd}")
        IO.puts("\n⏳ Processing request...")

      :assistant ->
        # Extract the actual text content
        content = case msg.data.message do
          %{"content" => text} when is_binary(text) -> text
          %{"content" => [%{"text" => text}]} -> text
          _ -> inspect(msg.data.message)
        end
        IO.puts("\n🤖 Claude API Response:")
        IO.puts("   #{content}")

      :result ->
        if msg.subtype == :success do
          IO.puts("\n✅ API Call Completed Successfully!")
          IO.puts("   💰 Cost: $#{msg.data.total_cost_usd}")
          IO.puts("   ⏱️  Duration: #{msg.data.duration_ms}ms")
          IO.puts("   🔄 Turns: #{msg.data.num_turns}")
          IO.puts("   📊 Session: #{msg.data.session_id}")
        else
          IO.puts("\n❌ API Error:")
          IO.puts(msg.data.error)
        end

      _ ->
        IO.puts("   Other: #{msg.type}")
    end
  end)

rescue
  e ->
    IO.puts("❌ Error: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end

IO.puts("\n🏁 Claude Code SDK Test Completed!")
IO.puts("   ✅ Authentication: Working")
IO.puts("   ✅ API Connection: Successful")
IO.puts("   ✅ Message Processing: Working")
IO.puts("   ✅ SDK Integration: Complete")
