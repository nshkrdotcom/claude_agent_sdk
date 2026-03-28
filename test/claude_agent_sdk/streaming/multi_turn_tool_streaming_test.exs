defmodule ClaudeAgentSDK.Streaming.MultiTurnToolStreamingTest do
  use ClaudeAgentSDK.SupertesterCase, async: true

  import ClaudeAgentSDK.SupertesterCase, only: [eventually: 2]

  alias ClaudeAgentSDK.{Client, Options, Streaming}
  alias ClaudeAgentSDK.Streaming.Session
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  describe "control client path" do
    setup do
      options = %Options{include_partial_messages: true}
      fake_cli = FakeCLI.new!()
      on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

      {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))
      on_exit(fn -> safe_stop(client) end)

      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
      _request_id = FakeCLI.respond_initialize_success!(fake_cli)

      eventually(
        fn -> :sys.get_state(client).initialized end,
        timeout: 1_000
      )

      %{session: {:control_client, client}, transport: fake_cli, client: client}
    end

    test "continues streaming after tool_use message_stop", %{
      session: session,
      transport: transport,
      client: client
    } do
      collector =
        Task.async(fn ->
          Streaming.send_message(session, "Run a tool")
          |> Enum.to_list()
        end)

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 1_000
      )

      events_turn_1 = [
        %{"type" => "message_start", "message" => %{"role" => "assistant"}},
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Running..."},
          "index" => 0
        },
        %{"type" => "message_delta", "delta" => %{"stop_reason" => "tool_use"}},
        %{"type" => "message_stop"}
      ]

      Enum.each(events_turn_1, fn event ->
        FakeCLI.push_message(transport, event)
        Process.sleep(5)
      end)

      events_turn_2 = [
        %{"type" => "message_start", "message" => %{"role" => "assistant"}},
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Here are the files."},
          "index" => 0
        },
        %{"type" => "message_delta", "delta" => %{"stop_reason" => "end_turn"}},
        %{"type" => "message_stop"}
      ]

      Enum.each(events_turn_2, fn event ->
        FakeCLI.push_message(transport, event)
        Process.sleep(5)
      end)

      events = Task.await(collector, 2_000)

      text =
        events
        |> Enum.filter(&(&1.type == :text_delta))
        |> Enum.map_join(& &1.text)

      assert text =~ "Running..."
      assert text =~ "Here are the files."
    end
  end

  describe "session path" do
    setup do
      options = %Options{}
      {:ok, session} = Session.start_link(options, mock_stream: true)

      on_exit(fn -> Session.close(session) end)

      %{session: session}
    end

    test "continues streaming after tool_use message_stop", %{session: session} do
      collector =
        Task.async(fn ->
          Session.send_message(session, "Run a tool")
          |> Enum.to_list()
        end)

      eventually(
        fn ->
          state = :sys.get_state(session)
          state.active_subscriber != nil
        end,
        timeout: 1_000
      )

      events_turn_1 = [
        %{"type" => "message_start", "message" => %{"role" => "assistant"}},
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Running..."},
          "index" => 0
        },
        %{"type" => "message_delta", "delta" => %{"stop_reason" => "tool_use"}},
        %{"type" => "message_stop"}
      ]

      events_turn_2 = [
        %{"type" => "message_start", "message" => %{"role" => "assistant"}},
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Done."},
          "index" => 0
        },
        %{"type" => "message_delta", "delta" => %{"stop_reason" => "end_turn"}},
        %{"type" => "message_stop"}
      ]

      :ok = Session.push_events(session, events_turn_1)
      :ok = Session.push_events(session, events_turn_2)

      events = Task.await(collector, 2_000)

      text =
        events
        |> Enum.filter(&(&1.type == :text_delta))
        |> Enum.map_join(& &1.text)

      assert text =~ "Running..."
      assert text =~ "Done."
    end
  end

  defp safe_stop(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
