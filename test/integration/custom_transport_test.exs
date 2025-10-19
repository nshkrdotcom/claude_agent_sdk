defmodule Integration.CustomTransportTest do
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  test "should work with custom transport" do
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

    assert_receive {:mock_transport_started, transport_pid}, 200
    # consume initialize request
    assert_receive {:mock_transport_send, _init_json}, 200

    task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Enum.take(2)
      end)

    first_message = %{
      "type" => "assistant",
      "message" => %{"content" => "Hello from custom transport", "role" => "assistant"},
      "session_id" => "custom-session"
    }

    second_message = %{
      "type" => "assistant",
      "message" => %{"content" => "Second reply", "role" => "assistant"},
      "session_id" => "custom-session"
    }

    MockTransport.push_message(transport_pid, Jason.encode!(first_message))
    MockTransport.push_message(transport_pid, Jason.encode!(second_message))

    messages = Task.await(task, 1_000)
    assert length(messages) == 2
    assert Enum.all?(messages, fn msg -> msg.type == :assistant end)
    contents = Enum.map(messages, fn msg -> msg.data[:message]["content"] end)
    assert contents == ["Hello from custom transport", "Second reply"]
  end
end
