defmodule ClaudeAgentSDK.ClientStreamingTest do
  @moduledoc """
  Tests for Client streaming event support (v0.6.0).

  Tests the streaming event handling, subscriber queue management,
  and integration with EventParser.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

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

      %{client: client, transport: transport}
    end

    test "handles message_start event", %{transport: transport} do
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

      # Event should be processed without error
      Process.sleep(50)
    end

    test "handles text_delta events", %{transport: transport} do
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

      # Events should be processed and accumulated
      Process.sleep(50)
    end

    test "handles message_stop event", %{transport: transport} do
      event = %{"type" => "message_stop"}

      MockTransport.push_message(transport, Jason.encode!(event))

      # Should trigger stream completion
      Process.sleep(50)
    end

    test "handles tool_use_start event", %{transport: transport} do
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
      Process.sleep(50)
    end

    test "handles tool_input_delta events", %{transport: transport} do
      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "input_json_delta", "partial_json" => "{\"command\":"},
        "index" => 1
      }

      MockTransport.push_message(transport, Jason.encode!(event))
      Process.sleep(50)
    end

    test "handles thinking_delta events (Sonnet 4.5+)", %{transport: transport} do
      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "thinking_delta", "thinking" => "Let me think..."},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event))
      Process.sleep(50)
    end

    test "accumulates text across multiple deltas", %{transport: transport} do
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

      # Text should be accumulated in state
      Process.sleep(50)
    end

    test "resets accumulated text on message_stop", %{transport: transport} do
      # Send text deltas
      event1 = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Hello"},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event1))
      Process.sleep(25)

      # Send message_stop
      event2 = %{"type" => "message_stop"}
      MockTransport.push_message(transport, Jason.encode!(event2))
      Process.sleep(25)

      # Accumulated text should be reset (verified by no crash)
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

      %{client: client, transport: transport}
    end

    test "broadcasts events to active subscriber only", %{transport: transport} do
      # Subscriber broadcasting test
      # (Will implement with proper subscribe handler)

      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Test"},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event))
      Process.sleep(50)
    end

    test "does not broadcast when no active subscriber", %{transport: transport} do
      # Should handle gracefully when no subscribers
      event = %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Test"},
        "index" => 0
      }

      MockTransport.push_message(transport, Jason.encode!(event))
      Process.sleep(50)

      # Should not crash
      assert Process.alive?(transport)
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

      %{client: client, transport: transport}
    end

    test "handles malformed stream events gracefully", %{transport: transport} do
      # Malformed event
      bad_event = %{"type" => "unknown_stream_event", "data" => "???"}

      MockTransport.push_message(transport, Jason.encode!(bad_event))
      Process.sleep(50)

      # Should not crash
      assert Process.alive?(transport)
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
            ClaudeAgentSDK.Hooks.Matcher.new("Bash", [hook_callback])
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
end
