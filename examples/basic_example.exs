#!/usr/bin/env elixir

# Basic Example - Simple Claude SDK usage (LIVE)
# Usage: mix run examples/basic_example.exs
#
# Prereqs:
#   - Claude CLI installed (`claude --version`)
#   - Authenticated (`claude login` or `ANTHROPIC_API_KEY`)

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, OptionBuilder}
alias Examples.Support

Support.ensure_live!()

defmodule BasicExample do
  def run do
    IO.puts("Basic Claude SDK Example (live)")
    IO.puts("Asking Claude for a simple response...")

    # Include user settings so `claude login` credentials are available.
    options = %{
      OptionBuilder.with_haiku()
      | setting_sources: ["user"]
    }

    # Make a simple query - just ask for one word back
    response =
      ClaudeAgentSDK.query(
        "Say exactly one word: hello",
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

    # Extract text from all assistant messages
    messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.join("\n")
  end
end

# Run the example
BasicExample.run()
Support.halt_if_runner!()
