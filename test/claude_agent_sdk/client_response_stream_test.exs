defmodule ClaudeAgentSDK.ClientResponseStreamTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Message, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  setup do
    Process.flag(:trap_exit, true)

    {:ok, client} =
      Client.start_link(%Options{},
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end
    end)

    assert_receive {:mock_transport_started, transport}, 200

    {:ok, client: client, transport: transport}
  end

  test "receive_response_stream yields messages until result", %{
    client: client,
    transport: transport
  } do
    task = Task.async(fn -> Client.receive_response_stream(client) |> Enum.to_list() end)

    SupertesterCase.eventually(
      fn ->
        state = :sys.get_state(client)
        map_size(state.subscribers) > 0
      end,
      timeout: 1_000
    )

    assistant = %{
      "type" => "assistant",
      "message" => %{"role" => "assistant", "content" => "hi"},
      "session_id" => "sess"
    }

    result = %{
      "type" => "result",
      "subtype" => "success",
      "session_id" => "sess",
      "duration_ms" => 10,
      "num_turns" => 1,
      "is_error" => false
    }

    MockTransport.push_message(transport, Jason.encode!(assistant))
    MockTransport.push_message(transport, Jason.encode!(result))

    assert [%Message{type: :assistant}, %Message{type: :result}] = Task.await(task, 1_000)
  end

  test "client sets CLAUDE_CODE_ENTRYPOINT for client transports", %{client: client} do
    state = :sys.get_state(client)
    env = state.options.env || %{}

    assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-elixir-client"
  end
end
