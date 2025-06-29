#!/usr/bin/env elixir

# Simple example of using the Claude Code SDK

# First, ensure you have:
# 1. Installed Claude Code CLI: npm install -g @anthropic-ai/claude-code
# 2. Authenticated the CLI: claude login

IO.puts("Claude Code SDK Example")
IO.puts("=" |> String.duplicate(50))

# Simple query
IO.puts("\n1. Simple query example:")
ClaudeCodeSDK.query("Write a hello world function in Elixir")
|> Enum.each(fn message ->
  case message do
    %{type: :system, subtype: :init} ->
      IO.puts("Session started: #{message.data.session_id}")
      
    %{type: :user} ->
      IO.puts("\nUser: #{message.data.message["content"]}")
      
    %{type: :assistant} ->
      IO.puts("\nClaude: #{message.data.message["content"]}")
      
    %{type: :result, subtype: :success} ->
      IO.puts("\n---")
      IO.puts("Cost: $#{message.data.total_cost_usd}")
      IO.puts("Duration: #{message.data.duration_ms}ms")
      IO.puts("Turns: #{message.data.num_turns}")
      
    _ ->
      :ok
  end
end)

# Query with options
IO.puts("\n\n2. Query with options:")
options = ClaudeCodeSDK.Options.new(
  max_turns: 1,
  system_prompt: "You are an Elixir expert. Keep responses concise."
)

ClaudeCodeSDK.query("Explain GenServers in 2 sentences", options)
|> Stream.filter(& &1.type == :assistant)
|> Enum.each(fn message ->
  IO.puts(message.data.message["content"])
end)