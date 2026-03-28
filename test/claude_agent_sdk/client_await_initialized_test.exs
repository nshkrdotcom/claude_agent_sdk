defmodule ClaudeAgentSDK.ClientAwaitInitializedTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "await_initialized queues waiter and resolves on initialize success" do
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, %Options{}))

    on_exit(fn ->
      safe_stop(client)
      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
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

    FakeCLI.push_message(fake_cli, init_response)

    assert :ok = Task.await(waiter, 1_000)

    state = :sys.get_state(client)
    assert state.initialized == true
    assert state.initialized_waiters == []
  end

  test "await_initialized returns timeout when initialize does not complete" do
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, %Options{}))

    on_exit(fn ->
      safe_stop(client)
      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    assert {:ok, _request_id} = Client.await_init_sent(client, 1_000)

    assert {:error, :timeout} = Client.await_initialized(client, 50)
  end

  test "send_message buffers outbound payloads until initialize succeeds" do
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, %Options{}))

    on_exit(fn ->
      safe_stop(client)
      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    assert :ok = Client.send_message(client, "hello before init")
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)

    [initialize_request] = FakeCLI.decoded_messages(fake_cli)

    assert %{
             "type" => "control_request",
             "request" => %{"subtype" => "initialize"}
           } = initialize_request

    state = :sys.get_state(client)
    refute state.initialized
    refute :queue.is_empty(state.pending_outbound)

    _request_id = FakeCLI.respond_initialize_success!(fake_cli)

    assert :ok = Client.await_initialized(client, 1_000)
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 2, 1_000)

    [initialize_request, queued_user_message] = FakeCLI.decoded_messages(fake_cli)

    assert initialize_request["request"]["subtype"] == "initialize"

    assert %{
             "type" => "user",
             "message" => %{"role" => "user", "content" => "hello before init"}
           } = queued_user_message

    state = :sys.get_state(client)
    assert state.initialized
    assert :queue.is_empty(state.pending_outbound)
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
