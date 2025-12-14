#!/usr/bin/env elixir

# Quick Demo: Streaming (LIVE)
#
# A minimal demo showing `ClaudeAgentSDK.Streaming` working end-to-end against
# the real Claude Code CLI (no tools, no hooks).
#
# Run: mix run examples/streaming_tools/quick_demo.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Options, Streaming}
alias Examples.Support

Support.ensure_live!()
Support.header!("Streaming Quick Demo (live)")

options = %Options{
  model: "haiku",
  max_turns: 1,
  allowed_tools: []
}

{:ok, session} = Streaming.start_session(options)

try do
  prompt = "Say hello in exactly five words."
  IO.puts("Prompt: #{prompt}\n")

  summary =
    Streaming.send_message(session, prompt)
    |> Enum.reduce_while(%{chunks: 0, stopped?: false}, fn
      %{type: :text_delta, text: chunk}, acc ->
        IO.write(chunk)
        {:cont, %{acc | chunks: acc.chunks + 1}}

      %{type: :message_stop}, acc ->
        IO.puts("")
        {:halt, %{acc | stopped?: true}}

      %{type: :error, error: reason}, _acc ->
        raise "Streaming error: #{inspect(reason)}"

      _event, acc ->
        {:cont, acc}
    end)

  if summary.chunks < 1 do
    raise "Expected at least 1 text_delta chunk, but saw #{summary.chunks}."
  end

  if summary.stopped? != true do
    raise "Expected a message_stop event, but did not observe one."
  end
after
  Streaming.close_session(session)
end

IO.puts("\nDone.")
Support.halt_if_runner!()
