#!/usr/bin/env elixir

# Example: Multi-turn Tool Streaming (live, session path)
#
# Demonstrates the multi-turn tool streaming case where a tool_use stop should be
# followed by a second assistant turn (stop_reason "end_turn").
#
# Run: mix run examples/streaming_tools/multi_turn_tool_streaming_session.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Options, Streaming}
alias Examples.Support

defmodule MultiTurnToolStreamingSessionExample do
  def run do
    Support.ensure_live!()
    Support.header!("Multi-turn Tool Streaming (session path)")

    options = %Options{
      model: "haiku",
      max_turns: 2,
      tools: ["Bash"],
      allowed_tools: ["Bash"],
      permission_mode: :bypass_permissions,
      preferred_transport: :cli
    }

    {:ok, session} = Streaming.start_session(options)

    if not is_pid(session) do
      raise "Expected CLI session (pid), got: #{inspect(session)}"
    end

    try do
      prompt = "Use the Bash tool to run: echo 'tool check'. Then summarize the output."
      IO.puts("Prompt: #{prompt}\n")

      summary =
        Streaming.send_message(session, prompt)
        |> Enum.reduce(%{stops: 0, reasons: [], text: ""}, fn event, acc ->
          case event do
            %{type: :text_delta, text: chunk} ->
              IO.write(chunk)
              %{acc | text: acc.text <> chunk}

            %{type: :message_delta, stop_reason: reason} when not is_nil(reason) ->
              %{acc | reasons: acc.reasons ++ [reason]}

            %{type: :message_stop} ->
              %{acc | stops: acc.stops + 1}

            %{type: :error, error: reason} ->
              raise "Streaming error: #{inspect(reason)}"

            _ ->
              acc
          end
        end)

      IO.puts("\n\nObserved message_stop events: #{summary.stops}")
      IO.puts("Observed stop_reason values: #{Enum.join(summary.reasons, ", ")}")

      if summary.stops < 2 do
        raise """
        Stream ended after tool_use. Expected follow-up assistant message.
        This indicates the session path completed on the first message_stop.
        """
      end

      if not Enum.member?(summary.reasons, "tool_use") do
        raise "Expected stop_reason \"tool_use\" but did not observe it."
      end

      if not Enum.member?(summary.reasons, "end_turn") do
        raise "Expected stop_reason \"end_turn\" but did not observe it."
      end
    after
      Streaming.close_session(session)
    end
  end
end

MultiTurnToolStreamingSessionExample.run()
Support.halt_if_runner!()
