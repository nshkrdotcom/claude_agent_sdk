#!/usr/bin/env elixir

# Simple test using Mix to properly load dependencies

IO.puts("🚀 Testing with Mix environment")

# Test 1: Check if erlexec is available in compiled environment
try do
  # Start erlexec
  Application.ensure_all_started(:erlexec)
  IO.puts("✅ Erlexec started successfully")

  # Test basic exec functionality
  case :exec.run("echo Hello from erlexec", [:sync, :stdout]) do
    {:ok, result} ->
      IO.puts("✅ Exec test successful: #{inspect(result)}")
    {:error, reason} ->
      IO.puts("❌ Exec test failed: #{inspect(reason)}")
  end

  # Test the full SDK
  IO.puts("\n📝 Testing Claude Code SDK...")
  try do
    result = ClaudeCodeSDK.query("Say hello")
    |> Enum.to_list()

    IO.puts("✅ Got #{length(result)} messages")

    # Show result messages with errors
    Enum.each(result, fn msg ->
      case msg.type do
        :result ->
          if msg.subtype == :success do
            IO.puts("✅ SDK Success! Cost: $#{msg.data.total_cost_usd}")
          else
            IO.puts("❌ SDK Error (#{msg.subtype}):")
            if Map.has_key?(msg.data, :error) do
              IO.puts(msg.data.error)
            else
              IO.puts(inspect(msg.data))
            end
          end
        _ -> :ok
      end
    end)
  rescue
    e ->
      IO.puts("❌ SDK Error: #{inspect(e)}")
  end

rescue
  e ->
    IO.puts("❌ Error: #{inspect(e)}")
end
