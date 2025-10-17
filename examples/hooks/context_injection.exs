#!/usr/bin/env elixir

# Example 2: Auto-inject Context with LIVE CLI
#
# This example demonstrates using hooks to automatically inject contextual
# information into conversations with the actual Claude CLI.
#
# Run: mix run examples/hooks/context_injection.exs

alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

defmodule ContextHooks do
  @moduledoc """
  Hooks for automatically adding contextual information.
  """

  @doc """
  UserPromptSubmit hook that adds project context.

  Adds information about:
  - Current time
  - Current git branch
  - Working directory
  - Environment
  """
  def add_project_context(_input, _tool_use_id, _context) do
    # Get current time
    current_time = DateTime.utc_now() |> DateTime.to_string()

    # Get environment
    environment = System.get_env("MIX_ENV", "dev")

    context_text = """
    ## 📎 Auto-Injected Project Context

    **Timestamp:** #{current_time}
    **Environment:** #{environment}
    **Working Directory:** #{File.cwd!()}
    """

    IO.puts("\n✅ Context injected into conversation:")
    IO.puts(context_text)

    Output.add_context("UserPromptSubmit", context_text)
  end
end

# Configure hooks
hooks = %{
  user_prompt_submit: [
    Matcher.new(nil, [&ContextHooks.add_project_context/3])
  ]
}

options = %Options{
  allowed_tools: ["Bash", "Read"],
  hooks: hooks
}

IO.puts("=" <> String.duplicate("=", 79))
IO.puts("🎣 Hooks Example: Context Injection (LIVE)")
IO.puts("=" <> String.duplicate("=", 79))
IO.puts("\nThis example shows how UserPromptSubmit hooks can automatically add")
IO.puts("context to every conversation, making Claude more aware of your environment.\n")

# Start client with hooks
{:ok, client} = Client.start_link(options)

IO.puts("✅ Client started with UserPromptSubmit hook")

# Start listening for responses
listener =
  Task.async(fn ->
    Client.stream_messages(client)
    |> Enum.take(3)
    |> Enum.to_list()
  end)

Process.sleep(1000)

# Send a message - context will be auto-injected!
IO.puts("\n📝 Sending message: 'What time is it and where am I?'")
IO.puts("-" <> String.duplicate("-", 79))

Client.send_message(client, "What time is it and where am I?")

IO.puts("\n⏳ Waiting for Claude's response...")
IO.puts("(Watch how Claude uses the injected context in the response!)\n")

# Wait for messages
messages = Task.await(listener, 30_000)

# Show Claude's response
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("📬 Claude's Response:")
IO.puts(String.duplicate("=", 80))

assistant_messages =
  messages
  |> Enum.filter(fn msg -> msg.type == :assistant end)
  |> Enum.map(fn msg ->
    # Extract text from message data
    case get_in(msg.data, [:message, "content"]) do
      [%{"text" => text} | _] -> text
      _ -> ""
    end
  end)
  |> Enum.join("\n")

if assistant_messages != "" do
  IO.puts(assistant_messages)
else
  IO.puts("(Claude's response in progress...)")
  IO.puts("\nReceived #{length(messages)} messages:")

  Enum.each(messages, fn msg ->
    IO.puts("  - Type: #{msg.type}")
  end)
end

IO.puts(String.duplicate("=", 80))

# Clean up
IO.puts("\n\nStopping client...")
Client.stop(client)

IO.puts("\n\n✨ Example completed!")
IO.puts("\n📚 Key Takeaways:")
IO.puts("   - UserPromptSubmit hooks run BEFORE Claude sees your message")
IO.puts("   - Context is added automatically - you don't have to ask!")
IO.puts("   - Claude can use the context to give more relevant answers")
IO.puts("   - Useful for: git status, project info, environment variables, etc.")
IO.puts("\n💡 Notice how Claude answered using the injected timestamp and location!")
