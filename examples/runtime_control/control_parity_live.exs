#!/usr/bin/env elixir

# Run: mix run examples/runtime_control/control_parity_live.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, Message, Options, Query}
alias ClaudeAgentSDK.Hooks.Matcher
alias Examples.Support

Support.ensure_live!()
Support.header!("Runtime Control + Streaming Parity (live)")

defmodule ControlParity do
  alias ClaudeAgentSDK.{ContentExtractor, Message}

  def render_message(%Message{} = message) do
    ContentExtractor.extract_text(message) || ""
  end

  def render_system_init(%Message{data: %{model: model, permission_mode: mode, tools: tools}}) do
    "[system] init model=#{model} permission_mode=#{inspect(mode)} tools=#{length(tools)}"
  end

  def render_system_init(other), do: "[system] #{inspect(other)}"

  def render_rate_limit_event(%Message{
        data: %{
          rate_limit_info: %{
            status: status,
            rate_limit_type: rate_limit_type,
            resets_at: resets_at,
            overage_status: overage_status
          }
        }
      }) do
    "[rate_limit] status=#{status} type=#{inspect(rate_limit_type)} resets_at=#{inspect(resets_at)} overage_status=#{inspect(overage_status)}"
  end

  def render_stream_event(%{
        "type" => "content_block_start",
        "content_block" => %{"type" => "tool_use", "name" => name, "id" => id}
      }) do
    "[stream_event] tool_use_start name=#{name} id=#{id}"
  end

  def render_stream_event(%{"type" => "message_start", "message" => %{"model" => model}}) do
    "[stream_event] message_start model=#{model}"
  end

  def render_stream_event(%{
        "type" => "content_block_start",
        "content_block" => %{"type" => type}
      }) do
    "[stream_event] content_block_start type=#{type}"
  end

  def render_stream_event(%{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => text}
      }) do
    "[stream_event] text_delta #{inspect(text)}"
  end

  def render_stream_event(%{
        "type" => "content_block_delta",
        "delta" => %{"type" => "thinking_delta"}
      }) do
    "[stream_event] thinking_delta [redacted]"
  end

  def render_stream_event(%{
        "type" => "content_block_delta",
        "delta" => %{"type" => "input_json_delta", "partial_json" => json}
      }) do
    "[stream_event] tool_input_delta #{inspect(json)}"
  end

  def render_stream_event(%{"type" => "message_delta", "delta" => delta}) do
    "[stream_event] message_delta stop_reason=#{inspect(delta["stop_reason"])}"
  end

  def render_stream_event(%{"type" => type}) do
    "[stream_event] #{type}"
  end
end

# Simple hook that just logs invocation and allows continuation
hook = fn input, _tool_use_id, _context ->
  IO.puts("\n[hook] #{inspect(input["hook_event_name"])} fired")
  %{}
end

# Control-aware query: hooks trigger user prompt submit event
query_options = %Options{
  model: "haiku",
  max_turns: 1,
  hooks: %{user_prompt_submit: [Matcher.new(nil, [hook])]},
  permission_mode: :default,
  include_partial_messages: true
}

IO.puts("== Control-aware query with hooks ==")

query_messages =
  Query.run("Say hello in one line (no tools).", query_options)
  |> Enum.to_list()

Enum.each(query_messages, fn
  %Message{type: :system, subtype: :init} = message ->
    IO.puts(ControlParity.render_system_init(message))

  %Message{type: :assistant} = message ->
    text = ControlParity.render_message(message)
    if text != "", do: IO.puts("[assistant] #{text}")

  %Message{type: :result} = msg ->
    IO.puts("[result] #{inspect(msg.data)}")

  %Message{type: :stream_event, data: %{event: event}} ->
    IO.puts(ControlParity.render_stream_event(event))

  %Message{type: :rate_limit_event} = message ->
    IO.puts(ControlParity.render_rate_limit_event(message))

  other ->
    IO.puts("[message] #{inspect(other)}")
end)

case Enum.find(query_messages, &(&1.type == :result)) do
  %Message{subtype: :success} ->
    :ok

  %Message{subtype: other} ->
    raise "Query.run did not succeed (result subtype: #{inspect(other)})"

  nil ->
    raise "Query.run returned no result message."
end

# Streaming with partial events + runtime permission mode change
stream_options = %Options{
  model: "haiku",
  max_turns: 1,
  include_partial_messages: true,
  permission_mode: :default,
  allowed_tools: []
}

{:ok, client} = Client.start_link(stream_options)

defmodule LiveStreamer do
  @moduledoc false

  alias ClaudeAgentSDK.{Client, Message}
  alias ControlParity

  def run(client, prompt) do
    stream = Client.stream_messages(client)
    :ok = Client.send_message(client, prompt)

    result =
      Enum.reduce_while(stream, %{result: nil}, fn
        %Message{type: :system, subtype: :init} = message, acc ->
          IO.puts(ControlParity.render_system_init(message))
          {:cont, acc}

        %Message{type: :stream_event, data: %{event: event}}, acc ->
          IO.puts(ControlParity.render_stream_event(event))
          {:cont, acc}

        %Message{type: :assistant} = message, acc ->
          text = ControlParity.render_message(message)
          if text != "", do: IO.puts("[assistant] #{text}")
          {:cont, acc}

        %Message{type: :rate_limit_event} = message, acc ->
          IO.puts(ControlParity.render_rate_limit_event(message))
          {:cont, acc}

        %Message{type: :result} = msg, acc ->
          IO.puts("[result] #{inspect(msg.data)}")
          {:halt, %{acc | result: msg}}

        other, acc ->
          IO.puts("[message] #{inspect(other)}")
          {:cont, acc}
      end)

    case result.result do
      %Message{subtype: :success} ->
        :ok

      %Message{subtype: other} ->
        raise "Streaming run did not succeed (result subtype: #{inspect(other)})"

      nil ->
        raise "Streaming run returned no result message."
    end
  end
end

IO.puts("\n== Streaming with partials (default permission mode) ==")
LiveStreamer.run(client, "Stream a single short haiku. Do not run tools.")

IO.puts("\n== Switching permission mode to :accept_edits and streaming again ==")
:ok = Client.set_permission_mode(client, :accept_edits)
LiveStreamer.run(client, "Another one-line response, then stop. Do not run tools.")

Client.stop(client)

Support.halt_if_runner!()
