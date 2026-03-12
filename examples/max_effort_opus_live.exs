#!/usr/bin/env elixir

# Max Effort Opus Example (LIVE)
# Usage: mix run examples/max_effort_opus_live.exs
#
# NOT included in run_all.sh — this example uses Opus at :max effort,
# which is the most expensive configuration. Run it manually when you
# want to verify max-effort behavior.
#
# Demonstrates:
#   1. Opus request/response with :max effort
#   2. Opus streaming with :max effort
#   3. Opus[1m] request/response with :max effort
#   4. Opus[1m] streaming with :max effort
#   5. The emitted CLI args for each case so --effort max is visible

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, Options, Streaming}
alias Examples.Support

Support.ensure_live!()

defmodule MaxEffortOpusLive do
  @prompt "Reply with exactly: OK"

  def run do
    Support.header!("Max Effort Opus Examples (live)")

    run_request_response("1) Opus + :max effort (request/response)", "opus")
    run_streaming("2) Opus + :max effort (streaming)", "opus")
    run_request_response("3) Opus[1m] + :max effort (request/response)", "opus[1m]")
    run_streaming("4) Opus[1m] + :max effort (streaming)", "opus[1m]")

    IO.puts("Done.")
  end

  defp opts(model) do
    Options.new(
      model: model,
      effort: :max,
      max_turns: 1,
      setting_sources: ["user"]
    )
  end

  defp run_request_response(label, model) do
    options = opts(model)

    IO.puts("\n#{label}")
    IO.puts(String.duplicate("-", 60))
    IO.inspect(Options.to_args(options), label: "CLI args")

    response =
      ClaudeAgentSDK.query(@prompt, options)
      |> Enum.to_list()
      |> extract_text()

    IO.puts("Response: #{response}\n")
  end

  defp run_streaming(label, model) do
    options = opts(model)

    IO.puts("#{label}")
    IO.puts(String.duplicate("-", 60))
    IO.inspect(Options.to_args(options), label: "CLI args")
    IO.write("Response: ")

    {:ok, session} = Streaming.start_session(options)

    try do
      Streaming.send_message(session, @prompt)
      |> Enum.each(fn
        %{type: :text_delta, text: chunk} -> IO.write(chunk)
        %{type: :error, error: reason} -> IO.write("[error: #{inspect(reason)}]")
        _ -> :ok
      end)
    after
      Streaming.close_session(session)
    end

    IO.puts("\n")
  end

  defp extract_text(messages) do
    messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end
end

MaxEffortOpusLive.run()
Support.halt_if_runner!()
