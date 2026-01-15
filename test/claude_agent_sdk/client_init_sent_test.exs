defmodule ClaudeAgentSDK.ClientInitSentTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  test "await_init_sent returns request id after initialize request is sent" do
    {:ok, client} =
      Client.start_link(%Options{},
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    assert_receive {:mock_transport_started, transport_pid}, 1_000

    assert {:ok, request_id} = Client.await_init_sent(client, 1_000)
    assert is_binary(request_id)

    [init_json | _] = MockTransport.recorded_messages(transport_pid)
    decoded = Jason.decode!(String.trim(init_json))

    assert decoded["type"] == "control_request"
    assert decoded["request_id"] == request_id

    Client.stop(client)
  end
end
