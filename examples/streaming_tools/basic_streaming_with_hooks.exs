# Example: Basic Streaming (v0.8.0)
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
    IO.puts("Basic Streaming Example (v0.8.0)")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("\nThis example demonstrates basic streaming with the control client.")
    IO.puts("For hooks examples, see examples/hooks/ directory.\n")

    # Simple options without hooks
    options = %Options{
      model: "haiku",
      max_turns: 1,
      preferred_transport: :control
    }

    IO.puts("Starting streaming session...\n")

    {:ok, session} = Streaming.start_session(options)

    if not match?({:control_client, _pid}, session) do
      raise "Expected control client session, got: #{inspect(session)}"
    end

    try do
      IO.puts("✓ Session started\n")
      IO.puts("Sending: 'Say hello in exactly five words.'\n")
      IO.puts("-" |> String.duplicate(70))

      result =
        Streaming.send_message(session, "Say hello in exactly five words.")
        |> Enum.reduce_while(%{completed: false}, fn event, acc ->
          case event do
            %{type: :text_delta, text: text} ->
              IO.write(text)
              {:cont, acc}

            %{type: :message_stop} ->
              IO.puts("\n" <> ("-" |> String.duplicate(70)))
              IO.puts("\n✓ Message complete")
              {:halt, %{acc | completed: true}}

            %{type: :error, error: reason} ->
              raise "Streaming error: #{inspect(reason)}"

            _ ->
              {:cont, acc}
          end
        end)

      if not result.completed do
        raise "Expected message_stop event, but stream ended early."
      end
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
