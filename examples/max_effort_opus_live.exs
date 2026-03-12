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

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, Options, Streaming}
alias Examples.Support

Support.ensure_live!()

defmodule MaxEffortOpusLive do
  @prompt "Reply with exactly one sentence: what effort level are you using?"

  def run do
    Support.header!("Max Effort Opus Examples (live)")

    # 1. Opus request/response
    IO.puts("\n1) Opus + :max effort (request/response)")
    IO.puts(String.duplicate("-", 60))

    response =
      ClaudeAgentSDK.query(@prompt, opts("opus"))
      |> Enum.to_list()
      |> extract_text()

    IO.puts("Response: #{response}\n")

    # 2. Opus streaming
    IO.puts("2) Opus + :max effort (streaming)")
    IO.puts(String.duplicate("-", 60))
    IO.write("Response: ")
    stream_query("opus")
    IO.puts("\n")

    # 3. Opus[1m] request/response
    IO.puts("3) Opus[1m] + :max effort (request/response)")
    IO.puts(String.duplicate("-", 60))

    response =
      ClaudeAgentSDK.query(@prompt, opts("opus[1m]"))
      |> Enum.to_list()
      |> extract_text()

    IO.puts("Response: #{response}\n")

    # 4. Opus[1m] streaming
    IO.puts("4) Opus[1m] + :max effort (streaming)")
    IO.puts(String.duplicate("-", 60))
    IO.write("Response: ")
    stream_query("opus[1m]")
    IO.puts("\n")

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

  defp stream_query(model) do
    {:ok, session} = Streaming.start_session(opts(model))

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
