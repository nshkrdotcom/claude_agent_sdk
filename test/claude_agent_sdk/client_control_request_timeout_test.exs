defmodule ClaudeAgentSDK.ClientControlRequestTimeoutTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  test "control requests time out and are cleaned up" do
    options = %Options{permission_mode: :default}

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()],
        control_request_timeout_ms: 50
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

    task = Task.async(fn -> Client.set_permission_mode(client, :plan) end)

    assert_receive {:mock_transport_send, _set_mode_json}, 200

    assert {:error, :timeout} = Task.await(task, 500)

    state = :sys.get_state(client)
    assert state.pending_requests == %{}
    assert state.pending_permission_change == nil

    Client.stop(client)
  end

  test "transport exit fails pending control requests fast" do
    options = %Options{permission_mode: :default}

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()],
        control_request_timeout_ms: 50
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

    task = Task.async(fn -> Client.set_permission_mode(client, :plan) end)
    assert_receive {:mock_transport_send, _set_mode_json}, 200

    send(client, {:transport_exit, :test_disconnect})

    assert {:error, {:transport_exit, :test_disconnect}} = Task.await(task, 500)
  end
end
