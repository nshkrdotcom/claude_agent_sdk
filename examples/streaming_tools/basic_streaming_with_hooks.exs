# Example: Basic Streaming (v0.6.0)
#
# Demonstrates basic streaming with the control client transport.
# For hooks examples, see examples/hooks/ which use Client.start_link directly.
#
# Run with: mix run examples/streaming_tools/basic_streaming_with_hooks.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Streaming, Options}
alias Examples.Support

defmodule BasicStreamingExample do
  def run do
    Support.ensure_live!()

    IO.puts("=" |> String.duplicate(70))
    IO.puts("Basic Streaming Example (v0.6.0)")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("\nThis example demonstrates basic streaming with the control client.")
    IO.puts("For hooks examples, see examples/hooks/ directory.\n")

    # Simple options without hooks
    options = %Options{
      model: "haiku",
      max_turns: 1
    }

    IO.puts("Starting streaming session...\n")

    {:ok, session} = Streaming.start_session(options)

    try do
      IO.puts("✓ Session started\n")
      IO.puts("Sending: 'Say hello in exactly five words.'\n")
      IO.puts("-" |> String.duplicate(70))

      Streaming.send_message(session, "Say hello in exactly five words.")
      |> Enum.reduce_while(:ok, fn event, _acc ->
        case event do
          %{type: :text_delta, text: text} ->
            IO.write(text)
            {:cont, :ok}

          %{type: :message_stop} ->
            IO.puts("\n" <> ("-" |> String.duplicate(70)))
            IO.puts("\n✓ Message complete")
            {:halt, :ok}

          %{type: :error, error: reason} ->
            IO.puts("\n⚠️  Error: #{inspect(reason)}")
            {:halt, :error}

          _ ->
            {:cont, :ok}
        end
      end)
    after
      Streaming.close_session(session)
      IO.puts("\n✓ Session closed")
      IO.puts("=" |> String.duplicate(70))
    end
  end
end

# Auto-run when executed with mix run
BasicStreamingExample.run()
Support.halt_if_runner!()
