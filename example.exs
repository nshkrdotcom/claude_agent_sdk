#!/usr/bin/env elixir

# Simple example of using the Claude Code SDK
# Uses current application environment (mock by default, live in production)

alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

# Start mock if needed
if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

IO.puts("Claude Code SDK Example")
IO.puts("=" |> String.duplicate(50))

# Simple query
IO.puts("\n1. Simple query example:")
try do
  ClaudeCodeSDK.query("Write a hello world function in Elixir")
  |> Enum.each(fn message ->
    case message do
      %{type: :system, subtype: :init} ->
        session_id = message.data[:session_id] || message.data["session_id"] || "unknown"
        IO.puts("Session started: #{session_id}")

      %{type: :user} ->
        user_content = ContentExtractor.extract_text(message) || "[no content]"
        IO.puts("\nUser: #{user_content}")

      %{type: :assistant} ->
        claude_content = ContentExtractor.extract_text(message) || "[no content]"
        IO.puts("\nClaude: #{claude_content}")

      %{type: :result, subtype: :success} ->
        IO.puts("\n---")
        cost = message.data[:total_cost_usd] || message.data["total_cost_usd"] || 0
        duration = message.data[:duration_ms] || message.data["duration_ms"] || 0
        turns = message.data[:num_turns] || message.data["num_turns"] || 0
        IO.puts("Cost: $#{cost}")
        IO.puts("Duration: #{duration}ms")
        IO.puts("Turns: #{turns}")

      %{type: :result} ->
        IO.puts("\n❌ Error (#{message.subtype}):")
        error = message.data[:error] || message.data["error"]
        if error do
          IO.puts(error)
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
  # Use smart preset configuration
  options = OptionBuilder.build_chat_options()

  messages = ClaudeCodeSDK.query("Explain GenServers in 2 sentences", options)
  |> Enum.to_list()

  # Check for errors first
  error_msg = Enum.find(messages, & &1.type == :result and &1.subtype != :success)
  if error_msg do
    IO.puts("❌ Error (#{error_msg.subtype}):")
    error = error_msg.data[:error] || error_msg.data["error"]
    if error do
      IO.puts(error)
    else
      IO.puts(inspect(error_msg.data))
    end
  else
    # Show assistant responses using ContentExtractor
    messages
    |> Enum.filter(& &1.type == :assistant)
    |> Enum.each(fn message ->
      content = ContentExtractor.extract_text(message) || "[no content]"
      IO.puts(content)
    end)
  end
rescue
  e ->
    IO.puts("❌ Error in example 2: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end
