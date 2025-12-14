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

  alias ClaudeAgentSDK.{ContentExtractor, Message, Options, Streaming}

  @prompt """
  You are a status bot. Reply with a very short update (1-2 sentences).
  If you cannot respond for any reason, describe the issue briefly.
  """

  @options %Options{
    model: "haiku",
    max_turns: 1,
    include_partial_messages: true
  }

  def run do
    IO.puts("\nAssistant error field demo (live CLI)")
    IO.puts("Tip: trigger an auth or rate-limit error to see the enum values.\n")

    stream_result = stream_once()

    case stream_result do
      {:ok, final_text, nil} ->
        IO.puts("Streamed text:\n#{final_text}\n")

      {:ok, final_text, error} ->
        IO.puts("Stream reported assistant error: #{inspect(error)}")
        IO.puts("Partial/streamed text:\n#{final_text}\n")

      {:error, reason} ->
        IO.puts("Streaming error: #{inspect(reason)}\n")
    end

    inspect_messages()
  end

  defp stream_once do
    {:ok, session} = Streaming.start_session(@options)

    {text, error} =
      Streaming.send_message(session, prompt())
      |> Enum.reduce({"", nil}, fn
        %{type: :text_delta, text: chunk}, {acc_text, err} ->
          IO.write(chunk)
          {acc_text <> chunk, err}

        %{type: :message_stop, error: err_code}, {acc_text, _} ->
          {acc_text, err_code}

        %{type: :message_stop}, acc ->
          acc

        %{type: :error, error: reason}, _ ->
          {"", reason || :unknown}

        _other, acc ->
          acc
      end)

    Streaming.close_session(session)
    IO.puts("")

    {:ok, text, error}
  rescue
    error -> {:error, error}
  end

  defp inspect_messages do
    IO.puts("Checking aggregated messages for assistant error metadata...\n")

    messages =
      ClaudeAgentSDK.query(prompt(), %{@options | include_partial_messages: nil})
      |> Enum.to_list()

    assistant_error =
      Enum.find_value(messages, fn
        %Message{type: :assistant, data: %{error: err}} -> err
        _ -> nil
      end)

    case assistant_error do
      nil ->
        IO.puts("No assistant error surfaced on the aggregated message path.")

      err ->
        IO.puts("Assistant message error detected: #{inspect(err)}")
    end

    assistant_text =
      messages
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    IO.puts("\nAssistant text:")
    IO.puts(assistant_text)
  end

  defp prompt do
    System.get_env("CLAUDE_ASSISTANT_ERROR_PROMPT") ||
      String.trim(@prompt)
  end
end

Support.ensure_live!()
AssistantErrorLiveExample.run()
Support.halt_if_runner!()
