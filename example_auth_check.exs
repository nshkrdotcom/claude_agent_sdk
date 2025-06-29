#!/usr/bin/env elixir

# Example showing how to handle authentication gracefully

IO.puts("Claude Code SDK - Authentication Check Example")
IO.puts("=" |> String.duplicate(50))

# Try a simple query
IO.puts("\nAttempting to query Claude...")

result = 
  ClaudeCodeSDK.query("Say hello")
  |> Enum.reduce_while(:ok, fn message, _acc ->
    case message do
      %{type: :result, subtype: :error_during_execution, data: %{error: error}} ->
        IO.puts("\n❌ Error: #{error}")
        {:halt, :error}
        
      %{type: :assistant} ->
        IO.puts("✅ Claude responded: #{message.data.message["content"]}")
        {:cont, :ok}
        
      _ ->
        {:cont, :ok}
    end
  end)

case result do
  :error ->
    IO.puts("\nTo authenticate, run:")
    IO.puts("  claude login")
    IO.puts("\nThen try this example again.")
    
  :ok ->
    IO.puts("\n✅ Successfully connected to Claude!")
end