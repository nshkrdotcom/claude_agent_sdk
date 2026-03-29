#!/usr/bin/env elixir

# Run: mix run examples/assistant_error_live.exs

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias Examples.Support

defmodule AssistantErrorLiveExample do
  @moduledoc """
  Live demo for assistant error field (ADR 0004) and streaming parity.

  Requires a logged-in Claude CLI (`claude login` or `CLAUDE_AGENT_OAUTH_TOKEN`).
  To see non-`nil` errors, provoke one intentionally (e.g., temporarily set an
  invalid token to get `:authentication_failed` or hit a rate limit).
  """

  alias ClaudeAgentSDK.AssistantError
  alias ClaudeAgentSDK.{ContentExtractor, Message, Options}

  @prompt """
  You are a status bot. Reply with a very short update (1-2 sentences).
  If you cannot respond for any reason, describe the issue briefly.
  """

  @options %Options{
             model: "haiku",
             max_turns: 1,
             include_partial_messages: true
           }
           |> Support.with_execution_surface()

  def run do
    IO.puts("\nAssistant error field demo (live CLI)")
    IO.puts("Tip: trigger an auth or rate-limit error to see the enum values.\n")

    messages =
      ClaudeAgentSDK.query(prompt(), @options)
      |> Enum.to_list()

    assert_success!(messages)
    inspect_messages(messages)
  end

  defp inspect_messages(messages) do
    IO.puts("Checking streaming and aggregated assistant-error parity...\n")

    stream_summary =
      Enum.reduce(messages, %{text: "", error: nil, saw_message_stop: false}, fn
        %Message{
          type: :stream_event,
          data: %{
            event: %{
              "type" => "content_block_delta",
              "delta" => %{"type" => "text_delta", "text" => chunk}
            }
          }
        },
        acc ->
          IO.write(chunk)
          %{acc | text: acc.text <> chunk}

        %Message{type: :stream_event, data: %{event: %{"type" => "message_stop"} = event}}, acc ->
          %{acc | error: extract_stream_error(event), saw_message_stop: true}

        _message, acc ->
          acc
      end)

    IO.puts("\n")

    if not stream_summary.saw_message_stop do
      raise "No message_stop stream event observed."
    end

    assistant_error =
      Enum.find_value(messages, fn
        %Message{type: :assistant, data: %{error: err}} -> err
        _ -> nil
      end)

    case assistant_error do
      nil ->
        IO.puts("No assistant error surfaced on this run.")

      err ->
        IO.puts("Assistant message error detected: #{inspect(err)}")
    end

    assistant_text =
      messages
      |> Enum.filter(&(&1.type == :assistant))
      |> ContentExtractor.extract_all_text("")

    if stream_summary.text != assistant_text do
      raise """
      Streamed text and aggregated assistant text diverged.

      Streamed:
      #{stream_summary.text}

      Aggregated:
      #{assistant_text}
      """
    end

    if stream_summary.error != assistant_error do
      raise """
      Streamed assistant error and aggregated assistant error diverged.

      Streamed: #{inspect(stream_summary.error)}
      Aggregated: #{inspect(assistant_error)}
      """
    end

    IO.puts("Parity check passed for text and assistant error.")

    IO.puts("\nAssistant text:")
    IO.puts(assistant_text)
  end

  defp assert_success!(messages) do
    case Enum.find(messages, &(&1.type == :result)) do
      %{subtype: :success} -> :ok
      %{subtype: other} -> raise "Query did not succeed (result subtype: #{inspect(other)})"
      nil -> raise "No result message returned."
    end
  end

  defp extract_stream_error(event) when is_map(event) do
    raw_error = Map.get(event, "error") || get_in(event, ["message", "error"])
    AssistantError.cast(raw_error)
  end

  defp prompt do
    System.get_env("CLAUDE_ASSISTANT_ERROR_PROMPT") ||
      String.trim(@prompt)
  end
end

Support.ensure_live!()
AssistantErrorLiveExample.run()
Support.halt_if_runner!()
