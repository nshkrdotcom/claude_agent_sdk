#!/usr/bin/env elixir

# Run: mix run examples/runtime_control/control_parity_live.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, Message, Options, Query}
alias ClaudeAgentSDK.Hooks.Matcher
alias Examples.Support

Support.ensure_live!()
Support.header!("Runtime Control + Streaming Parity (live)")

defmodule ControlParity do
  def render_content(content) when is_binary(content), do: content

  def render_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      %{"type" => "thinking", "thinking" => text} -> text
      other -> inspect(other)
    end)
    |> Enum.join("")
  end

  def render_content(other), do: inspect(other)
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
  %Message{type: :assistant, data: %{message: message}} ->
    IO.puts("[assistant] #{ControlParity.render_content(message["content"])}")

  %Message{type: :result} = msg ->
    IO.puts("[result] #{inspect(msg.data)}")

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
        %Message{type: :stream_event, data: %{event: event}}, acc ->
          IO.puts("[stream_event] #{inspect(event)}")
          {:cont, acc}

        %Message{type: :assistant, data: %{message: message}}, acc ->
          IO.puts("[assistant] #{ControlParity.render_content(message["content"])}")
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
