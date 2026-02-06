defmodule ClaudeAgentSDK.ClientAwaitInitializedTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  test "await_initialized queues waiter and resolves on initialize success" do
    {:ok, client} =
      Client.start_link(%Options{},
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    assert_receive {:mock_transport_started, transport_pid}, 1_000
    assert {:ok, request_id} = Client.await_init_sent(client, 1_000)

    waiter = Task.async(fn -> Client.await_initialized(client, 1_000) end)

    assert_waiter_queued(client)

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => request_id,
        "response" => %{}
      }
    }

    MockTransport.push_message(transport_pid, Jason.encode!(init_response))

    assert :ok = Task.await(waiter, 1_000)

    state = :sys.get_state(client)
    assert state.initialized == true
    assert state.initialized_waiters == []
  end

  test "await_initialized returns timeout when initialize does not complete" do
    {:ok, client} =
      Client.start_link(%Options{},
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    assert_receive {:mock_transport_started, _transport_pid}, 1_000
    assert {:ok, _request_id} = Client.await_init_sent(client, 1_000)

    assert {:error, :timeout} = Client.await_initialized(client, 50)
  end

  defp safe_stop(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Client.stop(pid)
  catch
    :exit, _ -> :ok
  end

  defp assert_waiter_queued(client, attempts \\ 20)

  defp assert_waiter_queued(_client, 0), do: flunk("initialized waiter was not queued")

  defp assert_waiter_queued(client, attempts) do
    state = :sys.get_state(client)

    if length(Map.get(state, :initialized_waiters, [])) == 1 do
      assert true
    else
      Process.sleep(25)
      assert_waiter_queued(client, attempts - 1)
    end
  end
end
