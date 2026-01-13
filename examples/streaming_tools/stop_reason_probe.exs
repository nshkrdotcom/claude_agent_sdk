#!/usr/bin/env elixir

# Example: Streaming Stop Reason Probe (live)
#
# Confirms that message_delta events include stop_reason for each message when
# --include-partial-messages is enabled. Forces the control client transport,
# runs an end_turn prompt and a tool_use prompt, then reports stop_reason values.
#
# Run: mix run examples/streaming_tools/stop_reason_probe.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Options, Streaming}
alias Examples.Support

defmodule StopReasonProbeExample do
  def run do
    Support.ensure_live!()
    Support.header!("Streaming Stop Reason Probe (live)")

    IO.puts("\nThis example verifies message_delta.stop_reason emission per message.\n")

    options = %Options{
      model: "haiku",
      max_turns: 4,
      tools: ["Bash"],
      allowed_tools: ["Bash"],
      permission_mode: :bypass_permissions,
      preferred_transport: :control
    }

    {:ok, session} = Streaming.start_session(options)

    if not match?({:control_client, _pid}, session) do
      raise "Expected control client session, got: #{inspect(session)}"
    end

    IO.puts("Transport: control client (preferred_transport: :control)")

    try do
      end_turn_summary =
        run_probe(
          session,
          "Say hi in one short sentence.",
          "End-turn prompt"
        )

      tool_summary =
        run_probe(
          session,
          "Use the Bash tool to run: echo 'tool check'. Then summarize the output.",
          "Tool-use prompt"
        )

      assert_end_turn_prompt!(end_turn_summary)
      assert_tool_use_prompt!(tool_summary)
    after
      Streaming.close_session(session)
    end

    IO.puts("\nDone.")
  end

  defp run_probe(session, prompt, label) do
    IO.puts("\n" <> String.duplicate("-", 70))
    IO.puts(label)
    IO.puts(String.duplicate("-", 70))
    IO.puts("Prompt: #{prompt}\n")

    summary =
      Streaming.send_message(session, prompt)
      |> Enum.reduce(initial_state(), &handle_event/2)
      |> finalize_summary()

    summary = %{summary | results: Enum.reverse(summary.results)}

    assert_stream_integrity!(summary, label)

    IO.puts("Messages observed: #{length(summary.results)}")
    IO.puts("All messages had stop_reason in message_delta.")

    reasons =
      summary.results
      |> Enum.map(& &1.stop_reason)
      |> Enum.filter(&(!is_nil(&1)))

    IO.puts("Stop reasons: " <> Enum.join(reasons, ", "))

    summary
  end

  defp initial_state do
    %{
      index: 0,
      in_message: false,
      current_stop_reason: nil,
      has_stop_reason: false,
      results: [],
      saw_events?: false
    }
  end

  defp handle_event(event, acc) do
    case event do
      %{type: :message_start} ->
        %{
          acc
          | in_message: true,
            index: acc.index + 1,
            current_stop_reason: nil,
            has_stop_reason: false,
            saw_events?: true
        }

      %{type: :message_delta, stop_reason: reason} when not is_nil(reason) ->
        %{acc | current_stop_reason: reason, has_stop_reason: true, saw_events?: true}

      %{type: :message_delta} ->
        %{acc | saw_events?: true}

      %{type: :message_stop} ->
        result = %{
          index: acc.index,
          stop_reason: acc.current_stop_reason,
          has_stop_reason: acc.has_stop_reason,
          complete: true
        }

        %{acc | in_message: false, results: [result | acc.results], saw_events?: true}

      %{type: :error, error: reason} ->
        raise "Streaming error: #{inspect(reason)}"

      _ ->
        %{acc | saw_events?: true}
    end
  end

  defp finalize_summary(%{in_message: true} = acc) do
    result = %{
      index: acc.index,
      stop_reason: acc.current_stop_reason,
      has_stop_reason: acc.has_stop_reason,
      complete: false
    }

    %{acc | in_message: false, results: [result | acc.results]}
  end

  defp finalize_summary(acc), do: acc

  defp assert_stream_integrity!(summary, label) do
    if summary.saw_events? == false do
      raise "No stream events observed for #{label}. Check CLI flags or permissions."
    end

    if summary.results == [] do
      raise "No messages observed for #{label}."
    end

    missing = Enum.count(summary.results, &(!&1.has_stop_reason))

    if missing > 0 do
      raise "Missing stop_reason for #{missing} message(s) in #{label}."
    end

    incomplete = Enum.count(summary.results, &(!&1.complete))

    if incomplete > 0 do
      raise "#{incomplete} message(s) ended without message_stop in #{label}."
    end
  end

  defp assert_end_turn_prompt!(summary) do
    reasons = Enum.map(summary.results, & &1.stop_reason)

    if summary.results == [] do
      raise "End-turn prompt produced no messages."
    end

    if Enum.any?(reasons, &(&1 == "tool_use")) do
      raise "End-turn prompt unexpectedly produced stop_reason \"tool_use\"."
    end

    if not Enum.any?(reasons, &(&1 == "end_turn")) do
      raise "End-turn prompt did not produce stop_reason \"end_turn\"."
    end
  end

  defp assert_tool_use_prompt!(summary) do
    reasons = Enum.map(summary.results, & &1.stop_reason)

    if length(summary.results) < 2 do
      raise "Tool-use prompt produced fewer than 2 messages (expected tool_use + end_turn)."
    end

    if not Enum.any?(reasons, &(&1 == "tool_use")) do
      raise "Tool-use prompt did not produce stop_reason \"tool_use\"."
    end

    if not Enum.any?(reasons, &(&1 == "end_turn")) do
      raise "Tool-use prompt did not produce stop_reason \"end_turn\"."
    end
  end
end

StopReasonProbeExample.run()
Support.halt_if_runner!()
