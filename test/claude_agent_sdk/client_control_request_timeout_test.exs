defmodule ClaudeAgentSDK.ClientControlRequestTimeoutTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "control requests time out and are cleaned up" do
    options = %Options{permission_mode: :default}
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, options), control_request_timeout_ms: 50)

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end

      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    assert {:ok, init_request_id} = Client.await_init_sent(client, 1_000)
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => init_request_id,
        "response" => %{}
      }
    }

    FakeCLI.push_message(fake_cli, init_response)

    task = Task.async(fn -> Client.set_permission_mode(client, :plan) end)

    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 2, 1_000)

    assert {:error, :timeout} = Task.await(task, 500)

    state = :sys.get_state(client)
    assert state.pending_requests == %{}
    assert state.pending_permission_change == nil
  end

  test "transport exit fails pending control requests fast" do
    options = %Options{permission_mode: :default}
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, options), control_request_timeout_ms: 5_000)

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end

      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    assert {:ok, init_request_id} = Client.await_init_sent(client, 1_000)
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => init_request_id,
        "response" => %{}
      }
    }

    FakeCLI.push_message(fake_cli, init_response)

    task = Task.async(fn -> Client.set_permission_mode(client, :plan) end)
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 2, 1_000)

    monitor_ref = Process.monitor(client)
    state = :sys.get_state(client)
    Process.exit(state.protocol_session, :test_disconnect)

    assert {:error, {:protocol_session_down, :test_disconnect}} = Task.await(task, 500)
    assert_receive {:DOWN, ^monitor_ref, :process, ^client, :normal}, 500
  end
end
