#!/usr/bin/env elixir

# Simple example of using the Claude Code SDK

# First, ensure you have:
# 1. Installed Claude Code CLI: npm install -g @anthropic-ai/claude-code
# 2. Authenticated the CLI: claude login

IO.puts("Claude Code SDK Example")
IO.puts("=" |> String.duplicate(50))

# Simple query
IO.puts("\n1. Simple query example:")
try do
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

      %{type: :result} ->
        IO.puts("\n❌ Error (#{message.subtype}):")
        if Map.has_key?(message.data, :error) do
          IO.puts(message.data.error)
        else
          IO.puts(inspect(message.data))
        end

      _ ->
        :ok
    end
  end)
rescue
  e ->
    IO.puts("❌ Error in example 1: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end

# Query with options
IO.puts("\n\n2. Query with options:")
try do
  options = ClaudeCodeSDK.Options.new(
    max_turns: 1,
    system_prompt: "You are an Elixir expert. Keep responses concise."
  )

  messages = ClaudeCodeSDK.query("Explain GenServers in 2 sentences", options)
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
  else
    # Show assistant responses
    messages
    |> Enum.filter(& &1.type == :assistant)
    |> Enum.each(fn message ->
      IO.puts(message.data.message["content"])
    end)
  end
rescue
  e ->
    IO.puts("❌ Error in example 2: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end
