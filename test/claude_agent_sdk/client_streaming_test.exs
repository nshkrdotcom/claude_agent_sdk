defmodule ClaudeAgentSDK.ClientStreamingTest do
  @moduledoc """
  Tests the control-client streaming path over the real protocol session.
  """

  use ClaudeAgentSDK.SupertesterCase

  import ClaudeAgentSDK.SupertesterCase, only: [eventually: 2]

  alias ClaudeAgentSDK.{Client, Message, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "initializes streaming state when include_partial_messages is enabled" do
    %{client: client} = start_initialized_client(%Options{include_partial_messages: true})

    state = :sys.get_state(client)
    assert state.options.include_partial_messages == true
    assert state.pending_inbound_size == 0
    assert state.pending_inbound_dropped == 0
  end

  test "buffers stream events and sdk messages until the first subscriber" do
    %{client: client, transport: transport} =
      start_initialized_client(%Options{include_partial_messages: true})

    stream_event = %{
      "type" => "content_block_delta",
      "delta" => %{"type" => "text_delta", "text" => "Hello"},
      "index" => 0
    }

    assistant = %{
      "type" => "assistant",
      "message" => %{
        "role" => "assistant",
        "content" => [%{"type" => "text", "text" => "Hello world"}]
      },
      "session_id" => "buffered"
    }

    result = %{
      "type" => "result",
      "subtype" => "success",
      "session_id" => "buffered",
      "total_cost_usd" => 0.0
    }

    FakeCLI.push_message(transport, stream_event)
    FakeCLI.push_message(transport, assistant)
    FakeCLI.push_message(transport, result)

    eventually(
      fn ->
        state = :sys.get_state(client)

        state.pending_inbound_size == 3 and
          state.pending_inbound_dropped == 0 and
          :queue.len(state.pending_inbound) == 3
      end,
      timeout: 2_000
    )

    task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Enum.take(3)
      end)

    [stream_event_msg, %Message{type: :assistant}, %Message{type: :result, subtype: :success}] =
      Task.await(task, 1_000)

    assert %Message{type: :stream_event, data: data} = stream_event_msg
    assert data.event["delta"]["text"] == "Hello"
    assert data.uuid == nil
    assert data.session_id == nil

    eventually(
      fn ->
        state = :sys.get_state(client)
        state.pending_inbound_size == 0 and :queue.is_empty(state.pending_inbound)
      end,
      timeout: 2_000
    )
  end

  test "tracks dropped buffered entries when stream_buffer_limit is exceeded" do
    limit = 5

    %{client: client, transport: transport} =
      start_initialized_client(%Options{
        include_partial_messages: true,
        stream_buffer_limit: limit
      })

    for index <- 1..8 do
      FakeCLI.push_message(transport, %{
        "type" => "assistant",
        "message" => %{
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => "message-#{index}"}]
        },
        "session_id" => "buffered-limit"
      })
    end

    eventually(
      fn ->
        state = :sys.get_state(client)

        state.pending_inbound_size == limit and
          state.pending_inbound_dropped == 3 and
          :queue.len(state.pending_inbound) == limit
      end,
      timeout: 2_000
    )
  end

  test "preserves stream_event metadata on the control-client path" do
    %{client: client, transport: transport} =
      start_initialized_client(%Options{include_partial_messages: true})

    task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Enum.take(1)
      end)

    eventually(
      fn ->
        state = :sys.get_state(client)
        state.active_subscriber != nil
      end,
      timeout: 1_000
    )

    FakeCLI.push_message(transport, %{
      "type" => "stream_event",
      "uuid" => "uuid-1",
      "session_id" => "session-1",
      "parent_tool_use_id" => "toolu-1",
      "event" => %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "metadata"},
        "index" => 0
      }
    })

    [%Message{type: :stream_event, data: data}] = Task.await(task, 1_000)

    assert data.uuid == "uuid-1"
    assert data.session_id == "session-1"
    assert data.parent_tool_use_id == "toolu-1"
    assert data.event["delta"]["text"] == "metadata"
  end

  defp start_initialized_client(options) do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))
    on_exit(fn -> safe_stop(client) end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    _request_id = FakeCLI.respond_initialize_success!(fake_cli)
    assert :ok = Client.await_initialized(client, 1_000)

    %{client: client, transport: fake_cli}
  end

  defp safe_stop(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
