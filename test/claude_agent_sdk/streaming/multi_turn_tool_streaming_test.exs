defmodule ClaudeAgentSDK.Streaming.MultiTurnToolStreamingTest do
  use ClaudeAgentSDK.SupertesterCase, async: true

  import ClaudeAgentSDK.SupertesterCase, only: [eventually: 2]

  alias ClaudeAgentSDK.{Client, Options, Streaming}
  alias ClaudeAgentSDK.Streaming.Session
  alias ClaudeAgentSDK.TestSupport.MockTransport

  describe "control client path" do
    setup do
      options = %Options{include_partial_messages: true}

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      transport =
        receive do
          {:mock_transport_started, t} -> t
        end

      assert_receive {:mock_transport_subscribed, _pid}, 1_000

      init_request =
        receive do
          {:mock_transport_send, json} -> Jason.decode!(String.trim(json))
        after
          1_000 -> flunk("Did not receive initialize request")
        end

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request["request_id"],
          "response" => %{}
        }
      }

      MockTransport.push_message(transport, init_response)

      eventually(
        fn -> :sys.get_state(client).initialized end,
        timeout: 1_000
      )

      %{session: {:control_client, client}, transport: transport, client: client}
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
        MockTransport.push_message(transport, Jason.encode!(event))
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
        MockTransport.push_message(transport, Jason.encode!(event))
        Process.sleep(5)
      end)

      events = Task.await(collector, 2_000)

      text =
        events
        |> Enum.filter(&(&1.type == :text_delta))
        |> Enum.map(& &1.text)
        |> Enum.join()

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
        |> Enum.map(& &1.text)
        |> Enum.join()

      assert text =~ "Running..."
      assert text =~ "Done."
    end
  end
end
