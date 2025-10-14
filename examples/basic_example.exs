#!/usr/bin/env elixir

# Basic Example - Simple Claude SDK usage
# Usage: mix run.live examples/basic_example.exs

alias ClaudeAgentSDK.{ContentExtractor, OptionBuilder}

# Check if we're in live mode
if Application.get_env(:claude_agent_sdk, :use_mock, false) do
  {:ok, _} = ClaudeAgentSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

defmodule BasicExample do
  def run do
    IO.puts("🚀 Basic Claude SDK Example")
    IO.puts("Asking Claude to write a simple function...")

    # Create simple options for basic usage - use development options for more capability
    options = OptionBuilder.merge(:development, %{max_turns: 10})

    # Make a simple query
    response =
      ClaudeAgentSDK.query(
        """
        Write a simple Elixir function that calculates the factorial of a number.
        Include proper documentation and a basic example of how to use it.
        Keep it concise and clear.
        """,
        options
      )
      |> extract_response()

    IO.puts("\n📝 Claude's Response:")
    IO.puts("=" |> String.duplicate(60))
    IO.puts(response)
    IO.puts("=" |> String.duplicate(60))
    IO.puts("✅ Example complete!")
  end

  defp extract_response(stream) do
    messages = Enum.to_list(stream)

    # Check for errors first
    error_msg = Enum.find(messages, &(&1.type == :result and &1.subtype != :success))

    if error_msg do
      IO.puts("\n❌ Error (#{error_msg.subtype}):")

      if Map.has_key?(error_msg.data, :error) do
        IO.puts(error_msg.data.error)
      else
        IO.puts(inspect(error_msg.data))
      end

      System.halt(1)
    end

    # Extract assistant content
    messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.join("\n")
  end
end

# Run the example
BasicExample.run()
