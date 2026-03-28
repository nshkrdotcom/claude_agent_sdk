defmodule ClaudeAgentSDK.ClientInitSentTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "await_init_sent returns request id after initialize request is sent" do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, %Options{}))

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

    assert {:ok, request_id} = Client.await_init_sent(client, 1_000)
    assert is_binary(request_id)

    [init_json | _] = FakeCLI.recorded_messages(fake_cli)
    decoded = Jason.decode!(String.trim(init_json))

    assert decoded["type"] == "control_request"
    assert decoded["request_id"] == request_id

    Client.stop(client)
  end

  test "client runtime state is a Client struct" do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, %Options{}))

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

    state = :sys.get_state(client)
    assert %Client{} = state

    Client.stop(client)
  end
end
