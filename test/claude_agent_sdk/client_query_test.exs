defmodule ClaudeAgentSDK.ClientQueryTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  test "query/3 injects session_id and parent_tool_use_id for string prompts" do
    {:ok, client} =
      Client.start_link(%Options{},
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    assert_receive {:mock_transport_started, transport_pid}, 1_000
    assert {:ok, init_request_id} = Client.await_init_sent(client, 1_000)
    assert_receive {:mock_transport_send, _init_json}, 1_000

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => init_request_id,
        "response" => %{}
      }
    }

    MockTransport.push_message(transport_pid, Jason.encode!(init_response))

    assert :ok = Client.query(client, "Hello", "my_session")

    assert_receive {:mock_transport_send, msg_json}, 200
    decoded = Jason.decode!(String.trim(msg_json))

    assert decoded["type"] == "user"
    assert decoded["session_id"] == "my_session"
    assert decoded["parent_tool_use_id"] == nil
    assert decoded["message"]["role"] == "user"
    assert decoded["message"]["content"] == "Hello"

    Client.stop(client)
  end

  test "query/3 injects session_id into message maps when missing" do
    {:ok, client} =
      Client.start_link(%Options{},
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    assert_receive {:mock_transport_started, transport_pid}, 1_000
    assert {:ok, init_request_id} = Client.await_init_sent(client, 1_000)
    assert_receive {:mock_transport_send, _init_json}, 1_000

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => init_request_id,
        "response" => %{}
      }
    }

    MockTransport.push_message(transport_pid, Jason.encode!(init_response))

    msgs = [
      %{
        "type" => "user",
        "message" => %{"role" => "user", "content" => "Hello from map"},
        "parent_tool_use_id" => nil
      }
    ]

    assert :ok = Client.query(client, msgs, "my_session")

    assert_receive {:mock_transport_send, msg_json}, 200
    decoded = Jason.decode!(String.trim(msg_json))

    assert decoded["session_id"] == "my_session"
    assert decoded["message"]["content"] == "Hello from map"

    Client.stop(client)
  end
end
