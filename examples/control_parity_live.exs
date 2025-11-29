alias ClaudeAgentSDK.{Client, Message, Options, Query}
alias ClaudeAgentSDK.Hooks.Matcher

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

# Permission callback that echoes decisions (always allow)
perm_cb = fn ctx ->
  IO.puts("[permission] #{ctx.tool_name} -> allow")
  ClaudeAgentSDK.Permission.Result.allow()
end

# Control-aware query: hooks trigger user prompt submit event
query_options = %Options{
  hooks: %{user_prompt_submit: [Matcher.new(nil, [hook])]},
  permission_mode: :plan,
  include_partial_messages: true
}

IO.puts("== Control-aware query with hooks ==")

Query.run("Say hello in one line (no tools).", query_options)
|> Enum.each(fn
  %Message{type: :assistant, data: %{message: message}} ->
    IO.puts("[assistant] #{ControlParity.render_content(message["content"])}")

  %Message{type: :result} = msg ->
    IO.puts("[result] #{inspect(msg.data)}")

  other ->
    IO.puts("[message] #{inspect(other)}")
end)

# Streaming with partial events + runtime permission mode change
stream_options = %Options{
  include_partial_messages: true,
  permission_mode: :default,
  hooks: %{pre_tool_use: [Matcher.new("Bash", [hook])]},
  can_use_tool: perm_cb
}

{:ok, client} = Client.start_link(stream_options)

defmodule LiveStreamer do
  alias ClaudeAgentSDK.{Client, Message}
  alias ControlParity

  def run(client, prompt) do
    stream = Client.stream_messages(client)
    :ok = Client.send_message(client, prompt)

    Enum.reduce_while(stream, :ok, fn
      %{type: :stream_event, event: event}, acc ->
        IO.puts("[stream_event] #{inspect(event)}")
        {:cont, acc}

      %Message{type: :assistant, data: %{message: message}}, acc ->
        IO.puts("[assistant] #{ControlParity.render_content(message["content"])}")
        {:cont, acc}

      %Message{type: :result} = msg, acc ->
        IO.puts("[result] #{inspect(msg.data)}")
        {:halt, acc}

      other, acc ->
        IO.puts("[message] #{inspect(other)}")
        {:cont, acc}
    end)
  end
end

IO.puts("\n== Streaming with partials (default permission mode) ==")
LiveStreamer.run(client, "Stream a single short haiku. Do not run tools.")

IO.puts("\n== Switching permission mode to :accept_edits and streaming again ==")
:ok = Client.set_permission_mode(client, :accept_edits)
LiveStreamer.run(client, "Another one-line response, then stop.")

Client.stop(client)
