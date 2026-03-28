defmodule ClaudeAgentSDK.SubscriberLifecycleTest do
  use ClaudeAgentSDK.SupertesterCase

  import ClaudeAgentSDK.SupertesterCase, only: [eventually: 2]

  alias ClaudeAgentSDK.{Client, Message, Options}
  alias ClaudeAgentSDK.Streaming.Session
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "client prunes dead subscribers and allows queue progression" do
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, %Options{include_partial_messages: true}))

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end

      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

    subscriber1 =
      spawn(fn ->
        client
        |> Client.stream_messages()
        |> Enum.take(5)
      end)

    eventually(
      fn ->
        state = :sys.get_state(client)
        map_size(state.subscribers) == 1 and is_reference(state.active_subscriber)
      end,
      timeout: 1_000
    )

    Process.exit(subscriber1, :kill)

    eventually(
      fn ->
        state = :sys.get_state(client)
        map_size(state.subscribers) == 0 and state.active_subscriber == nil
      end,
      timeout: 1_000
    )

    task2 =
      Task.async(fn ->
        client
        |> Client.stream_messages()
        |> Enum.take(1)
      end)

    eventually(
      fn ->
        state = :sys.get_state(client)
        map_size(state.subscribers) == 1 and is_reference(state.active_subscriber)
      end,
      timeout: 1_000
    )

    assistant = %{
      "type" => "assistant",
      "message" => %{"role" => "assistant", "content" => "hello"},
      "session_id" => "subscriber-lifecycle"
    }

    FakeCLI.push_message(fake_cli, assistant)

    assert [%Message{type: :assistant}] = Task.await(task2, 1_000)
  end

  test "streaming session prunes dead active subscribers and promotes queued work" do
    {:ok, session} = Session.start_link(%Options{}, mock_stream: true)

    on_exit(fn -> Session.close(session) end)

    subscriber1 =
      spawn(fn ->
        receive do
        end
      end)

    subscriber2 =
      spawn(fn ->
        receive do
        end
      end)

    ref1 = make_ref()
    ref2 = make_ref()

    assert :ok = GenServer.call(session, {:subscribe, ref1, subscriber1})
    assert :ok = GenServer.call(session, {:subscribe, ref2, subscriber2})

    GenServer.cast(session, {:send_message, "first", ref1})
    GenServer.cast(session, {:send_message, "second", ref2})

    eventually(
      fn ->
        state = :sys.get_state(session)

        state.active_subscriber == ref1 and
          Enum.any?(state.subscriber_queue, &match?({^ref2, _}, &1))
      end,
      timeout: 1_000
    )

    Process.exit(subscriber1, :kill)

    eventually(
      fn ->
        state = :sys.get_state(session)

        state.active_subscriber == ref2 and
          map_size(state.subscribers) == 1 and
          state.subscriber_queue == []
      end,
      timeout: 1_000
    )

    Process.exit(subscriber2, :kill)
  end
end
