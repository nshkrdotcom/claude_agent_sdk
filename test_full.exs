#!/usr/bin/env elixir

# Full test of the Claude Code SDK with erlexec

IO.puts("🚀 Testing Claude Code SDK with Erlexec")
IO.puts("=" |> String.duplicate(50))

# Test the actual SDK
IO.puts("\n📝 Testing SDK Query...")

try do
  result = ClaudeCodeSDK.query("Say exactly: 'Hello from Erlexec SDK!'")
  |> Enum.to_list()

  IO.puts("✅ Got #{length(result)} messages")

  # Show each message
  Enum.each(result, fn msg ->
    case msg.type do
      :system ->
        IO.puts("📋 System: Session #{msg.data.session_id}")

      :assistant ->
        content = msg.data.message["content"]
        IO.puts("🤖 Claude: #{content}")

      :result ->
        if msg.subtype == :success do
          IO.puts("✅ Success! Cost: $#{msg.data.total_cost_usd}, Duration: #{msg.data.duration_ms}ms")
        else
          IO.puts("❌ Error (#{msg.subtype}):")
          if Map.has_key?(msg.data, :error) do
            IO.puts(msg.data.error)
          else
            IO.puts(inspect(msg.data))
          end
        end

      _ ->
        IO.puts("ℹ️  #{msg.type}: #{inspect(msg.data, limit: :infinity)}")
    end
  end)

rescue
  e ->
    IO.puts("❌ Error: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end

IO.puts("\n🏁 Test completed!")
