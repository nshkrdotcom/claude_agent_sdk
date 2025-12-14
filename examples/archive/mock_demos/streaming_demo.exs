#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))
Code.require_file(Path.expand("support/mock_transport.exs", __DIR__))

alias ClaudeAgentSDK.{Client, Message, Options}
alias Examples.Support
alias Examples.Support.MockTransport

Support.ensure_mock!()
Support.header!("Streaming Demo (mock transport, deterministic)")

options = %Options{include_partial_messages: true}

{:ok, client} =
  Client.start_link(options,
    transport: MockTransport,
    transport_opts: [owner: self()]
  )

transport =
  receive do
    {:mock_transport_started, pid} -> pid
  after
    1_000 -> raise "Timed out waiting for mock transport"
  end

:sys.get_state(client)

stream_task =
  Task.async(fn ->
    Client.stream_messages(client)
    |> Enum.take(4)
  end)

MockTransport.push_json(transport, %{
  "type" => "content_block_delta",
  "delta" => %{"type" => "text_delta", "text" => "Hello"},
  "index" => 0
})

MockTransport.push_json(transport, %{
  "type" => "content_block_delta",
  "delta" => %{"type" => "text_delta", "text" => " world"},
  "index" => 0
})

MockTransport.push_json(transport, %{
  "type" => "assistant",
  "message" => %{
    "role" => "assistant",
    "content" => [%{"type" => "text", "text" => "Hello world"}]
  },
  "session_id" => "demo"
})

MockTransport.push_json(transport, %{
  "type" => "result",
  "subtype" => "success",
  "session_id" => "demo",
  "total_cost_usd" => 0.0
})

messages = Task.await(stream_task, 1_000)

IO.puts("Received #{length(messages)} message(s):")

Enum.each(messages, fn
  %Message{type: :stream_event, data: %{event: event}} ->
    IO.puts("  • stream_event: #{event.type}")

  %Message{type: :assistant} = msg ->
    blocks = Message.content_blocks(msg)
    IO.puts("  • assistant blocks: #{inspect(blocks)}")

  %Message{type: :result, subtype: :success} ->
    IO.puts("  • result: success")

  other ->
    IO.puts("  • #{inspect(other)}")
end)

IO.puts("\n✓ Stream events are represented as %ClaudeAgentSDK.Message{type: :stream_event}")

Client.stop(client)
