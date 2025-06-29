#!/usr/bin/env elixir

# Debug test with proper content handling and timeout
IO.puts("🚀 Debug Test with Timeout")
IO.puts("=" |> String.duplicate(30))

# Helper function to extract content safely
extract_content = fn msg ->
  case msg.data.message do
    %{"content" => text} when is_binary(text) -> 
      text
    %{"content" => [%{"text" => text}]} -> 
      text
    %{"content" => content_list} when is_list(content_list) ->
      content_list
      |> Enum.map(fn
        %{"text" => text} -> text
        item -> inspect(item)
      end)
      |> Enum.join(" ")
    other -> 
      inspect(other)
  end
end

# Test with timeout
IO.puts("Starting SDK test with 15 second timeout...")

task = Task.async(fn ->
  try do
    ClaudeCodeSDK.query("Say exactly: Hello Debug Test!")
    |> Enum.to_list()
  rescue
    e -> {:error, e}
  end
end)

case Task.yield(task, 15_000) do
  {:ok, {:error, error}} ->
    IO.puts("❌ SDK error: #{inspect(error)}")
    
  {:ok, messages} ->
    IO.puts("✅ Got #{length(messages)} messages")
    
    Enum.each(messages, fn msg ->
      case msg.type do
        :system ->
          IO.puts("📋 Session: #{msg.data.session_id}")
          
        :assistant ->
          content = extract_content.(msg)
          IO.puts("🤖 Claude: #{content}")
          
        :result ->
          if msg.subtype == :success do
            IO.puts("✅ Success! Cost: $#{msg.data.total_cost_usd}")
          else
            IO.puts("❌ Error: #{msg.subtype}")
          end
          
        _ ->
          IO.puts("ℹ️  #{msg.type}")
      end
    end)
    
  nil ->
    IO.puts("❌ TIMEOUT after 15 seconds - killing task")
    Task.shutdown(task, :brutal_kill)
end

IO.puts("\n🏁 Debug test completed!")