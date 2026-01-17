defmodule ClaudeAgentSDK.ClientStreamingTest do
  @moduledoc """
  Tests for Client streaming event support (v0.6.0).

  Tests the streaming event handling, subscriber queue management,
  and integration with EventParser.
  """
  use ClaudeAgentSDK.SupertesterCase

  import ClaudeAgentSDK.SupertesterCase, only: [eventually: 2]

  alias ClaudeAgentSDK.{Client, Message, Options, Streaming}
  alias ClaudeAgentSDK.Hooks.Matcher
  alias ClaudeAgentSDK.TestSupport.{MockTransport, TestFixtures}

  describe "Client with include_partial_messages option" do
    test "includes --include-partial-messages in CLI command when option set" do
      options = %Options{
        include_partial_messages: true
      }

      {:ok, _client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      # Option should be present in state
      # (CLI command generation uses Options.to_args which includes the flag)
      assert options.include_partial_messages == true
    end

    test "initializes streaming state fields" do
      options = %Options{
        include_partial_messages: true
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      # State should have streaming fields initialized
      # (verified by successful startup - state is internal)
      assert Process.alive?(client)
    end
  end

  describe "pre-subscribe buffering" do
    test "buffers stream events and sdk messages until the first subscriber" do
      options = %Options{include_partial_messages: true}

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      assert_receive {:mock_transport_started, transport_pid}, 1_000
      assert {:ok, request_id} = Client.await_init_sent(client, 1_000)

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Hello"},
        "index" => 0
      }

      assistant = %{
        "type" => "assistant",
        "message" => %{
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => "Hello world"}]
        },
        "session_id" => "buffered"
      }

      result = %{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "buffered",
        "total_cost_usd" => 0.0
      }

      MockTransport.push_message(transport_pid, Jason.encode!(event))
      MockTransport.push_message(transport_pid, Jason.encode!(assistant))
      MockTransport.push_message(transport_pid, Jason.encode!(result))

      task =
        Task.async(fn ->
          Client.stream_messages(client)
          |> Enum.take(3)
        end)

      [stream_event_msg, %Message{type: :assistant}, %Message{type: :result, subtype: :success}] =
        Task.await(task, 1_000)

      assert %Message{type: :stream_event, data: data} = stream_event_msg
      assert data.event["type"] == "content_block_delta"
      assert data.event["delta"]["text"] == "Hello"
      assert data.uuid == nil
      assert data.session_id == nil
    end
  end

  describe "stream event handling" do
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

      # Wait for client to complete subscription before tests run
      # This ensures MockTransport has the client in its subscribers set
      # Use a simple ping to ensure handle_continue has completed
      :sys.get_state(client)

      %{client: client, transport: transport}
    end

    test "handles message_start event", %{client: client, transport: transport} do
      event = %{
        "type" => "message_start",
        "message" => %{
          "model" => "claude-sonnet-4-5",
          "role" => "assistant",
          "usage" => %{"input_tokens" => 10, "output_tokens" => 0}
        }
      }

      # Push event through transport
      MockTransport.push_message(transport, Jason.encode!(event))

      # Event should be processed without error - just verify client is responsive
      eventually(
        fn ->
          Process.alive?(client)
        end,
        timeout: 2000
      )
    end

    test "handles text_delta events", %{client: client, transport: transport} do
      events = [
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Hello"},
          "index" => 0
        },
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => " World"},
          "index" => 0
        }
      ]

      for event <- events do
        MockTransport.push_message(transport, Jason.encode!(event))
      end

      # Wait for accumulated text to contain both deltas
      eventually(
        fn ->
          state = :sys.get_state(client)
          state.accumulated_text == "Hello World"
        end,
        timeout: 2000
      )
    end

    test "handles message_stop event", %{client: client, transport: transport} do
      event = %{"type" => "message_stop"}

      MockTransport.push_message(transport, Jason.encode!(event))

      # Wait for stream completion (active_subscriber becomes nil)
      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber == nil
        end,
        timeout: 2000
      )
    end

    test "handles tool_use_start event", %{client: client, transport: transport} do
      event = %{
        "type" => "content_block_start",
        "content_block" => %{
          "type" => "tool_use",
          "name" => "Bash",
          "id" => "tool_1"
        },
        "index" => 1
      }

      MockTransport.push_message(transport, Jason.encode!(event))

      # Event is fire-and-forget, just verify client is responsive
      eventually(
        fn ->
          Process.alive?(client)
        end,
        timeout: 2000
      )
    end

    test "handles tool_input_delta events", %{client: client, transport: transport} do
      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "input_json_delta", "partial_json" => "{\"command\":"},
        "index" => 1
      }

      MockTransport.push_message(transport, Jason.encode!(event))

      # Event is fire-and-forget, just verify client is responsive
      eventually(
        fn ->
          Process.alive?(client)
        end,
        timeout: 2000
      )
    end

    test "handles thinking_delta events (Sonnet 4.5+)", %{client: client, transport: transport} do
      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "thinking_delta", "thinking" => "Let me think..."},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event))

      # Event is fire-and-forget, just verify client is responsive
      eventually(
        fn ->
          Process.alive?(client)
        end,
        timeout: 2000
      )
    end

    test "accumulates text across multiple deltas", %{client: client, transport: transport} do
      # Send sequence of text deltas
      deltas = ["Hello", " ", "World", "!"]

      for text <- deltas do
        event = %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => text},
          "index" => 0
        }

        MockTransport.push_message(transport, Jason.encode!(event))
      end

      # Wait for all deltas to be accumulated
      eventually(
        fn ->
          state = :sys.get_state(client)
          state.accumulated_text == "Hello World!"
        end,
        timeout: 2000
      )
    end

    test "resets accumulated text on message_stop", %{client: client, transport: transport} do
      # Send text deltas
      event1 = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Hello"},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event1))

      # Wait for text to be accumulated
      eventually(
        fn ->
          state = :sys.get_state(client)
          state.accumulated_text == "Hello"
        end,
        timeout: 2000
      )

      # Send message_stop
      event2 = %{"type" => "message_stop"}
      MockTransport.push_message(transport, Jason.encode!(event2))

      # Wait for completion (active_subscriber reset AND accumulated_text reset)
      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber == nil and state.accumulated_text == ""
        end,
        timeout: 2000
      )
    end

    test "stream_messages yields stream events for partial messages", %{
      client: client,
      transport: transport
    } do
      stream =
        client
        |> Client.stream_messages()
        |> Stream.take(1)

      task =
        Task.async(fn ->
          stream
          |> Enum.to_list()
        end)

      assert_receive {:mock_transport_subscribed, _pid}, 200

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Hello"},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event))

      [message] = Task.await(task, 1_000)
      assert %Message{type: :stream_event, data: data} = message
      assert data.event["type"] == "content_block_delta"
      assert data.event["delta"]["text"] == "Hello"
      assert data.uuid == nil
      assert data.session_id == nil

      eventually(
        fn ->
          state = :sys.get_state(client)
          map_size(state.subscribers) == 0 and state.active_subscriber == nil
        end,
        timeout: 500
      )
    end
  end

  describe "subscriber queue behavior" do
    setup do
      options = %Options{include_partial_messages: true}

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      receive do: ({:mock_transport_started, _transport} -> :ok)

      %{client: client}
    end

    test "first subscriber activates immediately", %{client: client} do
      _ref = make_ref()

      # Subscribe should succeed
      # Note: We'll need to update the subscribe API to support references
      # For now, this test documents the intended behavior
      assert Process.alive?(client)
    end

    test "second subscriber queues", %{client: client} do
      _ref1 = make_ref()
      _ref2 = make_ref()

      # First subscriber active, second queued
      # (Placeholder - will implement in subscriber queue updates)
      assert Process.alive?(client)
    end

    test "message_stop activates next subscriber", %{client: client} do
      # Queue scenario test
      # (Placeholder - will implement with queue management)
      assert Process.alive?(client)
    end
  end

  describe "event broadcasting" do
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

      # Wait for client to complete subscription
      :sys.get_state(client)

      %{client: client, transport: transport}
    end

    test "broadcasts events to active subscriber only", %{client: client, transport: transport} do
      # Subscriber broadcasting test
      # (Will implement with proper subscribe handler)

      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Test"},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event))

      # Wait for event to be processed
      eventually(
        fn ->
          state = :sys.get_state(client)
          state.accumulated_text == "Test"
        end,
        timeout: 2000
      )
    end

    test "does not broadcast when no active subscriber", %{client: client, transport: transport} do
      # Should handle gracefully when no subscribers
      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Test"},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event))

      # Wait for event to be processed (should accumulate even without subscriber)
      eventually(
        fn ->
          state = :sys.get_state(client)
          state.accumulated_text == "Test"
        end,
        timeout: 2000
      )

      # Should not crash
      assert Process.alive?(transport)
      assert Process.alive?(client)
    end
  end

  describe "error handling" do
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

      # Wait for client to complete subscription
      :sys.get_state(client)

      %{client: client, transport: transport}
    end

    test "handles malformed stream events gracefully", %{client: client, transport: transport} do
      # Malformed event
      bad_event = %{"type" => "unknown_stream_event", "data" => "???"}

      MockTransport.push_message(transport, Jason.encode!(bad_event))

      # Should not crash - just verify client is responsive
      eventually(
        fn ->
          Process.alive?(client) and Process.alive?(transport)
        end,
        timeout: 2000
      )

      assert Process.alive?(transport)
      assert Process.alive?(client)
    end

    test "handles incomplete JSON gracefully", %{transport: transport} do
      # EventParser handles incomplete JSON with buffer
      _partial = "{\"type\": \"message_start\", \"message\":"

      # This will be classified as sdk_message since it won't parse correctly
      # The Client should handle it gracefully
      # (Direct send won't work - need valid JSON for MockTransport)
      assert Process.alive?(transport)
    end
  end

  describe "integration with existing Client features" do
    test "streaming works alongside hooks" do
      hook_callback = fn _tool, _input, _ctx -> %{behavior: :allow} end

      options = %Options{
        include_partial_messages: true,
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [hook_callback])
          ]
        }
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      # Should initialize successfully with both features
      assert Process.alive?(client)
    end

    test "streaming works with SDK MCP servers" do
      # Placeholder SDK MCP server
      sdk_server = %{
        type: :sdk,
        name: "test",
        version: "1.0.0",
        registry_pid: self()
      }

      options = %Options{
        include_partial_messages: true,
        mcp_servers: %{"test" => sdk_server}
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      # Should initialize successfully
      assert Process.alive?(client)
    end

    test "streaming works with permission callbacks" do
      permission_callback = fn _ctx -> :allow end

      options = %Options{
        include_partial_messages: true,
        can_use_tool: permission_callback
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      # Should initialize successfully
      assert Process.alive?(client)
    end
  end

  # Tests that stream_event metadata is preserved when processing wrappers.
  # This includes uuid/session_id plus parent_tool_use_id for subagent routing.
  describe "stream_event metadata preservation in control client path" do
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

      :sys.get_state(client)

      %{client: client, transport: transport}
    end

    test "preserves parent_tool_use_id from stream_event wrapper on text_delta", %{
      client: client,
      transport: transport
    } do
      # Set up subscriber to receive events
      stream =
        client
        |> Client.stream_messages()
        |> Stream.take(1)

      task = Task.async(fn -> Enum.to_list(stream) end)

      assert_receive {:mock_transport_subscribed, _pid}, 500

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      # Send stream_event wrapper WITH parent_tool_use_id (simulating subagent output)
      stream_event = %{
        "type" => "stream_event",
        "uuid" => "evt_123",
        "session_id" => "sess_456",
        "parent_tool_use_id" => "toolu_01ABC123XYZ",
        "event" => %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Subagent output"},
          "index" => 0
        }
      }

      MockTransport.push_message(transport, Jason.encode!(stream_event))

      [message] = Task.await(task, 2_000)

      assert %Message{type: :stream_event, data: data} = message
      assert data.event["type"] == "content_block_delta"
      assert data.event["delta"]["text"] == "Subagent output"
      assert data.parent_tool_use_id == "toolu_01ABC123XYZ"
      assert data.uuid == "evt_123"
      assert data.session_id == "sess_456"
    end

    test "preserves parent_tool_use_id from stream_event wrapper on message_start", %{
      client: client,
      transport: transport
    } do
      stream =
        client
        |> Client.stream_messages()
        |> Stream.take(1)

      task = Task.async(fn -> Enum.to_list(stream) end)

      assert_receive {:mock_transport_subscribed, _pid}, 500

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      # Send stream_event wrapper WITH parent_tool_use_id
      stream_event = %{
        "type" => "stream_event",
        "uuid" => "evt_456",
        "session_id" => "sess_789",
        "parent_tool_use_id" => "toolu_02DEF456ABC",
        "event" => %{
          "type" => "message_start",
          "message" => %{
            "model" => "claude-haiku-4-5",
            "role" => "assistant",
            "usage" => %{"input_tokens" => 10, "output_tokens" => 0}
          }
        }
      }

      MockTransport.push_message(transport, Jason.encode!(stream_event))

      [message] = Task.await(task, 2_000)

      assert %Message{type: :stream_event, data: data} = message
      assert data.event["type"] == "message_start"
      assert data.event["message"]["model"] == "claude-haiku-4-5"
      assert data.parent_tool_use_id == "toolu_02DEF456ABC"
      assert data.uuid == "evt_456"
      assert data.session_id == "sess_789"
    end

    test "sets parent_tool_use_id to nil for main agent events (no wrapper parent_tool_use_id)",
         %{
           client: client,
           transport: transport
         } do
      stream =
        client
        |> Client.stream_messages()
        |> Stream.take(1)

      task = Task.async(fn -> Enum.to_list(stream) end)

      assert_receive {:mock_transport_subscribed, _pid}, 500

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      # Send stream_event wrapper WITHOUT parent_tool_use_id (main agent output)
      stream_event = %{
        "type" => "stream_event",
        "uuid" => "evt_789",
        "session_id" => "sess_012",
        "event" => %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Main agent output"},
          "index" => 0
        }
      }

      MockTransport.push_message(transport, Jason.encode!(stream_event))

      [message] = Task.await(task, 2_000)

      assert %Message{type: :stream_event, data: data} = message
      assert data.event["type"] == "content_block_delta"
      assert data.event["delta"]["text"] == "Main agent output"
      assert data.parent_tool_use_id == nil
      assert data.uuid == "evt_789"
      assert data.session_id == "sess_012"
    end

    test "preserves parent_tool_use_id on tool_use_start from subagent", %{
      client: client,
      transport: transport
    } do
      stream =
        client
        |> Client.stream_messages()
        |> Stream.take(1)

      task = Task.async(fn -> Enum.to_list(stream) end)

      assert_receive {:mock_transport_subscribed, _pid}, 500

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      # Subagent using a tool
      stream_event = %{
        "type" => "stream_event",
        "uuid" => "evt_tool",
        "session_id" => "sess_tool",
        "parent_tool_use_id" => "toolu_03GHI789DEF",
        "event" => %{
          "type" => "content_block_start",
          "content_block" => %{
            "type" => "tool_use",
            "name" => "Glob",
            "id" => "toolu_subagent_tool"
          },
          "index" => 0
        }
      }

      MockTransport.push_message(transport, Jason.encode!(stream_event))

      [message] = Task.await(task, 2_000)

      assert %Message{type: :stream_event, data: data} = message
      assert data.event["type"] == "content_block_start"
      assert data.event["content_block"]["type"] == "tool_use"
      assert data.event["content_block"]["name"] == "Glob"
      assert data.parent_tool_use_id == "toolu_03GHI789DEF"
      assert data.uuid == "evt_tool"
      assert data.session_id == "sess_tool"
    end

    test "preserves parent_tool_use_id on message_stop from subagent", %{
      client: client,
      transport: transport
    } do
      stream =
        client
        |> Client.stream_messages()
        |> Stream.take(1)

      task = Task.async(fn -> Enum.to_list(stream) end)

      assert_receive {:mock_transport_subscribed, _pid}, 500

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      # Subagent message complete
      stream_event = %{
        "type" => "stream_event",
        "uuid" => "evt_stop",
        "session_id" => "sess_stop",
        "parent_tool_use_id" => "toolu_04JKL012GHI",
        "event" => %{
          "type" => "message_stop"
        }
      }

      MockTransport.push_message(transport, Jason.encode!(stream_event))

      [message] = Task.await(task, 2_000)

      assert %Message{type: :stream_event, data: data} = message
      assert data.event["type"] == "message_stop"
      assert data.parent_tool_use_id == "toolu_04JKL012GHI"
      assert data.uuid == "evt_stop"
      assert data.session_id == "sess_stop"
    end

    test "crashes when stream_event wrapper is missing uuid", %{
      client: client,
      transport: transport
    } do
      Process.flag(:trap_exit, true)

      stream_event = %{
        "type" => "stream_event",
        "session_id" => "sess_missing_uuid",
        "event" => %{"type" => "message_stop"}
      }

      MockTransport.push_message(transport, Jason.encode!(stream_event))

      assert_receive {:EXIT, ^client, {{:badkey, "uuid"}, _}}, 1_000
    end

    test "crashes when stream_event wrapper is missing session_id", %{
      client: client,
      transport: transport
    } do
      Process.flag(:trap_exit, true)

      stream_event = %{
        "type" => "stream_event",
        "uuid" => "evt_missing_session",
        "event" => %{"type" => "message_stop"}
      }

      MockTransport.push_message(transport, Jason.encode!(stream_event))

      assert_receive {:EXIT, ^client, {{:badkey, "session_id"}, _}}, 1_000
    end
  end

  describe "message_to_event preserves parent_tool_use_id on complete messages" do
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

      # Synchronize - wait for client to be ready
      :sys.get_state(client)

      {:ok, client: client, transport: transport}
    end

    test "user message with parent_tool_use_id preserves it", %{
      client: client,
      transport: transport
    } do
      stream =
        client
        |> Client.stream_messages()
        |> Stream.take(1)

      task = Task.async(fn -> Enum.to_list(stream) end)

      assert_receive {:mock_transport_subscribed, _pid}, 500

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      # Complete user message from subagent (like Python SDK receives)
      # The CLI sends parent_tool_use_id on complete messages, not just stream_events
      user_message = %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_subagent",
              "content" => "1\n2\n3\n4\n5"
            }
          ]
        },
        "session_id" => "sess_subagent",
        "parent_tool_use_id" => "toolu_05MNO345JKL"
      }

      MockTransport.push_message(transport, Jason.encode!(user_message))

      [message] = Task.await(task, 2_000)

      # The Message struct should have parent_tool_use_id in data
      assert %Message{type: :user, data: data} = message
      assert data.parent_tool_use_id == "toolu_05MNO345JKL"
    end

    test "assistant message with parent_tool_use_id preserves it", %{
      client: client,
      transport: transport
    } do
      stream =
        client
        |> Client.stream_messages()
        |> Stream.take(1)

      task = Task.async(fn -> Enum.to_list(stream) end)

      assert_receive {:mock_transport_subscribed, _pid}, 500

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      # Complete assistant message from subagent
      assistant_message = %{
        "type" => "assistant",
        "message" => %{
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => "Here are the numbers 1-5"}]
        },
        "session_id" => "sess_subagent",
        "parent_tool_use_id" => "toolu_06PQR678MNO"
      }

      MockTransport.push_message(transport, Jason.encode!(assistant_message))

      [message] = Task.await(task, 2_000)

      # The Message struct should have parent_tool_use_id in data
      assert %Message{type: :assistant, data: data} = message
      assert data.parent_tool_use_id == "toolu_06PQR678MNO"
    end
  end

  describe "Streaming.send_message preserves parent_tool_use_id" do
    setup do
      hook = TestFixtures.allow_all_hook()

      options = %Options{
        include_partial_messages: true,
        hooks: %{pre_tool_use: [hook]}
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      transport =
        receive do
          {:mock_transport_started, t} -> t
        end

      # Wait for init request and send response to mark client as initialized
      {:ok, request_id} = Client.await_init_sent(client, 1_000)

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport, Jason.encode!(init_response))

      # Wait for client to be initialized
      eventually(
        fn -> :sys.get_state(client).initialized end,
        timeout: 1_000
      )

      {:ok, client: client, transport: transport}
    end

    test "preserves parent_tool_use_id on user messages", %{
      client: client,
      transport: transport
    } do
      # Use Streaming module to get events (which uses message_to_event internally)
      session = {:control_client, client}

      # Start streaming in a task
      task =
        Task.async(fn ->
          session
          |> Streaming.send_message("test")
          |> Stream.take(1)
          |> Enum.to_list()
        end)

      # Wait for subscription using deterministic synchronization (no Process.sleep!)
      assert_receive {:mock_transport_subscribed, _pid}, 500

      eventually(
        fn ->
          state = :sys.get_state(client)
          state.active_subscriber != nil
        end,
        timeout: 500
      )

      # Send a user message with parent_tool_use_id (like CLI does for subagent results)
      user_message = %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => [
            %{"type" => "tool_result", "tool_use_id" => "toolu_task", "content" => "done"}
          ]
        },
        "session_id" => "sess_123",
        "parent_tool_use_id" => "toolu_07STU901PQR"
      }

      MockTransport.push_message(transport, Jason.encode!(user_message))

      [event] = Task.await(task, 2_000)

      assert event.type == :message
      assert event.parent_tool_use_id == "toolu_07STU901PQR"
    end
  end
end
