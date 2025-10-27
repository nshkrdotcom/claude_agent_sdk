defmodule ClaudeAgentSDK.Streaming.EventAdapterTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Streaming.EventAdapter
  alias ClaudeAgentSDK.Message

  # ============================================================================
  # Normalization Tests (8 tests)
  # ============================================================================

  describe "to_events/1 - event passthrough" do
    test "passes through text_delta events unchanged" do
      events = [
        %{type: :text_delta, text: "Hello", accumulated: "Hello"},
        %{type: :text_delta, text: " world", accumulated: "Hello world"}
      ]

      result = events |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()
      assert result == events
    end

    test "passes through message lifecycle events unchanged" do
      events = [
        %{type: :message_start, model: "claude-sonnet-4-5"},
        %{type: :message_stop, final_text: "Complete"}
      ]

      result = events |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()
      assert result == events
    end

    test "passes through tool events unchanged" do
      events = [
        %{type: :tool_use_start, name: "bash", id: "toolu_123"},
        %{type: :tool_input_delta, json: "{\"command\":"},
        %{type: :content_block_stop, final_text: ""}
      ]

      result = events |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()
      assert result == events
    end
  end

  describe "to_events/1 - Message struct conversion" do
    test "normalizes Message with type :assistant" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{"content" => "Hello from Claude"},
          session_id: "session-123"
        }
      }

      [event] = [message] |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()

      assert event.type == :assistant
      assert is_map(event.data)
      assert Map.has_key?(event, :timestamp)
    end

    test "normalizes Message with type :result" do
      message = %Message{
        type: :result,
        subtype: :success,
        data: %{
          result: "Task completed",
          total_cost_usd: 0.001
        }
      }

      [event] = [message] |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()

      assert event.type == :result
      assert is_map(event.data)
    end

    test "normalizes Message with type :user" do
      message = %Message{
        type: :user,
        data: %{
          message: %{"content" => "User input"},
          session_id: "session-123"
        }
      }

      [event] = [message] |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()

      assert event.type == :user
      assert is_map(event.data)
    end

    test "normalizes Message with type :system" do
      message = %Message{
        type: :system,
        subtype: :init,
        data: %{
          session_id: "session-123",
          model: "claude-sonnet-4-5"
        }
      }

      [event] = [message] |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()

      assert event.type == :system
      assert event.subtype == :init
    end

    test "handles mixed stream of events and Messages" do
      mixed = [
        %{type: :text_delta, text: "Hello"},
        %Message{type: :assistant, data: %{message: %{}, session_id: "123"}},
        %{type: :message_stop}
      ]

      result = mixed |> Stream.into([]) |> EventAdapter.to_events() |> Enum.to_list()

      assert length(result) == 3
      assert Enum.at(result, 0).type == :text_delta
      assert Enum.at(result, 1).type == :assistant
      assert Enum.at(result, 2).type == :message_stop
    end
  end

  # ============================================================================
  # Filtering Tests (8 tests)
  # ============================================================================

  describe "text_only/1" do
    test "filters to only text_delta events" do
      mixed = [
        %{type: :text_delta, text: "A"},
        %{type: :tool_use_start, name: "bash"},
        %{type: :text_delta, text: "B"},
        %{type: :message_stop}
      ]

      text_events = mixed |> Stream.into([]) |> EventAdapter.text_only() |> Enum.to_list()

      assert length(text_events) == 2
      assert Enum.all?(text_events, &(&1.type == :text_delta))
    end

    test "includes text_block_start events" do
      mixed = [
        %{type: :text_block_start},
        %{type: :text_delta, text: "Hello"},
        %{type: :tool_use_start, name: "bash"}
      ]

      text_events = mixed |> Stream.into([]) |> EventAdapter.text_only() |> Enum.to_list()

      assert length(text_events) == 2
      assert Enum.at(text_events, 0).type == :text_block_start
      assert Enum.at(text_events, 1).type == :text_delta
    end

    test "returns empty stream when no text events present" do
      non_text = [
        %{type: :message_start, model: "sonnet"},
        %{type: :tool_use_start, name: "bash"},
        %{type: :message_stop}
      ]

      result = non_text |> Stream.into([]) |> EventAdapter.text_only() |> Enum.to_list()

      assert result == []
    end

    test "handles empty stream" do
      result = [] |> Stream.into([]) |> EventAdapter.text_only() |> Enum.to_list()

      assert result == []
    end
  end

  describe "tools_only/1" do
    test "filters to only tool events" do
      mixed = [
        %{type: :text_delta, text: "Hello"},
        %{type: :tool_use_start, name: "bash", id: "toolu_1"},
        %{type: :tool_input_delta, json: "{"},
        %{type: :message_stop}
      ]

      tool_events = mixed |> Stream.into([]) |> EventAdapter.tools_only() |> Enum.to_list()

      assert length(tool_events) == 2
      assert Enum.at(tool_events, 0).type == :tool_use_start
      assert Enum.at(tool_events, 1).type == :tool_input_delta
    end

    test "returns empty stream when no tool events present" do
      non_tool = [
        %{type: :text_delta, text: "Hello"},
        %{type: :message_start, model: "sonnet"},
        %{type: :message_stop}
      ]

      result = non_tool |> Stream.into([]) |> EventAdapter.tools_only() |> Enum.to_list()

      assert result == []
    end

    test "handles empty stream" do
      result = [] |> Stream.into([]) |> EventAdapter.tools_only() |> Enum.to_list()

      assert result == []
    end

    test "includes all tool-related event types" do
      tool_events = [
        %{type: :tool_use_start, name: "bash", id: "toolu_1"},
        %{type: :tool_input_delta, json: "{\"cmd\":"},
        %{type: :tool_input_delta, json: "\"ls\"}"}
      ]

      result = tool_events |> Stream.into([]) |> EventAdapter.tools_only() |> Enum.to_list()

      assert length(result) == 3
    end
  end

  # ============================================================================
  # Accumulation Tests (6 tests)
  # ============================================================================

  describe "accumulate_text/1" do
    test "builds complete text from text_delta events" do
      deltas = [
        %{type: :text_delta, text: "Hello"},
        %{type: :text_delta, text: " "},
        %{type: :text_delta, text: "world"}
      ]

      accumulated =
        deltas
        |> Stream.into([])
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()

      assert accumulated == ["Hello", "Hello ", "Hello world"]
      assert List.last(accumulated) == "Hello world"
    end

    test "handles events with accumulated field" do
      events = [
        %{type: :text_delta, text: "H", accumulated: "H"},
        %{type: :text_delta, text: "i", accumulated: "Hi"}
      ]

      accumulated =
        events
        |> Stream.into([])
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()

      assert List.last(accumulated) == "Hi"
    end

    test "ignores non-text events during accumulation" do
      mixed = [
        %{type: :text_delta, text: "Hello"},
        %{type: :tool_use_start, name: "bash"},
        %{type: :text_delta, text: " world"},
        %{type: :message_stop}
      ]

      accumulated =
        mixed
        |> Stream.into([])
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()

      assert List.last(accumulated) == "Hello world"
    end

    test "handles empty stream" do
      result = [] |> Stream.into([]) |> EventAdapter.accumulate_text() |> Enum.to_list()

      assert result == []
    end

    test "handles stream with no text events" do
      non_text = [
        %{type: :message_start, model: "sonnet"},
        %{type: :message_stop}
      ]

      accumulated =
        non_text
        |> Stream.into([])
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()

      # Should maintain empty string through non-text events
      assert accumulated == ["", ""]
    end

    test "resets accumulation correctly across multiple text blocks" do
      # Simulating multiple text blocks in a response
      deltas = [
        %{type: :text_delta, text: "First"},
        %{type: :text_delta, text: " block"},
        %{type: :text_delta, text: " more"}
      ]

      accumulated =
        deltas
        |> Stream.into([])
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()

      assert accumulated == ["First", "First block", "First block more"]
    end
  end

  # ============================================================================
  # Integration Tests (3 tests)
  # ============================================================================

  describe "integration - chaining helpers" do
    test "can chain to_events -> text_only -> accumulate_text" do
      mixed = [
        %{type: :message_start, model: "sonnet"},
        %{type: :text_delta, text: "Hello"},
        %Message{type: :assistant, data: %{message: %{}, session_id: "123"}},
        %{type: :text_delta, text: " world"},
        %{type: :tool_use_start, name: "bash"}
      ]

      final_text =
        mixed
        |> Stream.into([])
        |> EventAdapter.to_events()
        |> EventAdapter.text_only()
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()
        |> List.last()

      assert final_text == "Hello world"
    end

    test "can chain to_events -> tools_only" do
      mixed = [
        %{type: :text_delta, text: "Using tools"},
        %{type: :tool_use_start, name: "bash", id: "toolu_1"},
        %Message{type: :assistant, data: %{message: %{}, session_id: "123"}},
        %{type: :tool_input_delta, json: "{\"cmd\":\"ls\"}"}
      ]

      tool_events =
        mixed
        |> Stream.into([])
        |> EventAdapter.to_events()
        |> EventAdapter.tools_only()
        |> Enum.to_list()

      assert length(tool_events) == 2
      assert Enum.at(tool_events, 0).type == :tool_use_start
      assert Enum.at(tool_events, 1).type == :tool_input_delta
    end

    test "real-world pattern: extract final text from streaming response" do
      # Simulating a real streaming response with mixed events
      stream = [
        %{type: :message_start, model: "claude-sonnet-4-5", role: "assistant", usage: %{}},
        %{type: :text_block_start},
        %{type: :text_delta, text: "I'll", accumulated: "I'll"},
        %{type: :text_delta, text: " help", accumulated: "I'll help"},
        %{type: :text_delta, text: " you", accumulated: "I'll help you"},
        %{type: :content_block_stop, final_text: "I'll help you"},
        %{type: :message_delta, stop_reason: "end_turn", stop_sequence: nil},
        %{type: :message_stop, final_text: "I'll help you"}
      ]

      # Extract just the text
      final_text =
        stream
        |> Stream.into([])
        |> EventAdapter.text_only()
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()
        |> List.last()

      assert final_text == "I'll help you"
    end
  end
end
