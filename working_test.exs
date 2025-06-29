#!/usr/bin/env elixir

IO.puts("Loading SDK modules...")
Code.require_file("lib/claude_code_sdk/options.ex")
Code.require_file("lib/claude_code_sdk/message.ex")
Code.require_file("lib/claude_code_sdk/process.ex")
Code.require_file("lib/claude_code_sdk/query.ex")
Code.require_file("lib/claude_code_sdk.ex")

IO.puts("\n🚀 Testing Claude Code SDK\n")

try do
  ClaudeCodeSDK.query("Say 'Hello from Elixir!' and nothing else")
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
          IO.puts("   Time: #{msg.data.duration_ms}ms")
        else
          IO.puts("\n❌ Error: #{inspect(msg.data)}")
        end
        
      _ ->
        :ok
    end
  end)
rescue
  e ->
    IO.puts("\n❌ Error: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end