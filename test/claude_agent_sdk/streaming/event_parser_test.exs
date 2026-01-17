defmodule ClaudeAgentSDK.Streaming.EventParserTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Streaming.EventParser

  # ===========================================================================
  # parent_tool_use_id tests - Subagent streaming support
  # ===========================================================================
  #
  # When Claude uses the Task tool to spawn a subagent, streaming events from
  # that subagent include a `parent_tool_use_id` field that identifies which
  # tool call the streaming output belongs to.
  #
  # This is CRITICAL for:
  #   1. Routing streaming output to the correct UI component
  #   2. Distinguishing main agent output from subagent output
  #   3. Building hierarchical streaming UIs (nested agent displays)
  #
  # Raw CLI output structure:
  #
  #   Main agent (no parent):
  #     {"type": "stream_event", "event": {...}, "parent_tool_use_id": null}
  #
  #   Subagent (has parent):
  #     {"type": "stream_event", "event": {...}, "parent_tool_use_id": "toolu_01ABC"}
  #
  # ===========================================================================

  describe "parse_buffer/2 parent_tool_use_id preservation" do
    test "preserves parent_tool_use_id from stream_event wrapper on text_delta" do
      # Subagent event with parent_tool_use_id
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_01ABC","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :text_delta
      assert event.text == "Hello"
      assert event.parent_tool_use_id == "toolu_01ABC"
    end

    test "sets parent_tool_use_id to nil for main agent events" do
      # Main agent event (no parent_tool_use_id or explicit null)
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":null,"event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :text_delta
      assert event.parent_tool_use_id == nil
    end

    test "preserves parent_tool_use_id on message_start events" do
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_01XYZ","event":{"type":"message_start","message":{"model":"claude-haiku","role":"assistant"}}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :message_start
      assert event.parent_tool_use_id == "toolu_01XYZ"
    end

    test "preserves parent_tool_use_id on message_stop events" do
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_01ABC","event":{"type":"message_stop"}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :message_stop
      assert event.parent_tool_use_id == "toolu_01ABC"
    end

    test "preserves parent_tool_use_id on tool_use_start events" do
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_parent","event":{"type":"content_block_start","content_block":{"type":"tool_use","name":"Glob","id":"toolu_child"}}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :tool_use_start
      assert event.name == "Glob"
      assert event.id == "toolu_child"
      assert event.parent_tool_use_id == "toolu_parent"
    end

    test "preserves parent_tool_use_id on tool_input_delta events" do
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_01ABC","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\\"pattern\\""}}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :tool_input_delta
      assert event.json == "{\"pattern\""
      assert event.parent_tool_use_id == "toolu_01ABC"
    end

    test "preserves parent_tool_use_id on content_block_stop events" do
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_01ABC","event":{"type":"content_block_stop"}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :content_block_stop
      assert event.parent_tool_use_id == "toolu_01ABC"
    end

    test "preserves parent_tool_use_id on message_delta events" do
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_01ABC","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"}}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :message_delta
      assert event.parent_tool_use_id == "toolu_01ABC"
    end

    test "preserves parent_tool_use_id on thinking_delta events" do
      buffer =
        ~s({"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_01ABC","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Let me think..."}}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :thinking_delta
      assert event.thinking == "Let me think..."
      assert event.parent_tool_use_id == "toolu_01ABC"
    end

    test "handles multiple events with mixed parent_tool_use_id values" do
      # Main agent event followed by subagent event
      buffer = """
      {"type":"stream_event","session_id":"sess_123","parent_tool_use_id":null,"event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Main"}}}
      {"type":"stream_event","session_id":"sess_123","parent_tool_use_id":"toolu_sub","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Sub"}}}
      """

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [main_event, sub_event] = events
      assert main_event.parent_tool_use_id == nil
      assert sub_event.parent_tool_use_id == "toolu_sub"
    end

    test "handles events without stream_event wrapper (non-streaming mode)" do
      # Direct event without wrapper (should still work, parent_tool_use_id nil)
      buffer =
        ~s({"type":"message_start","message":{"model":"claude-haiku","role":"assistant"}}\n)

      {:ok, events, _remaining, _accumulated} = EventParser.parse_buffer(buffer, "")

      assert [event] = events
      assert event.type == :message_start
      assert event.parent_tool_use_id == nil
    end
  end

  describe "parse_event/2 structured outputs" do
    test "includes structured_output on message_stop events" do
      event = %{
        "type" => "message_stop",
        "structured_output" => %{"foo" => "bar"}
      }

      {:ok, [parsed], new_acc} = EventParser.parse_event(event, "final text")

      assert parsed.type == :message_stop
      assert parsed.final_text == "final text"
      assert parsed.structured_output == %{"foo" => "bar"}
      assert new_acc == ""
    end

    test "supports structured_output nested under message payload" do
      event = %{
        "type" => "message_stop",
        "message" => %{
          "structured_output" => %{"status" => "ok"}
        }
      }

      {:ok, [parsed], _} = EventParser.parse_event(event, "")

      assert parsed.structured_output == %{"status" => "ok"}
    end

    test "omits structured_output key when not present" do
      {:ok, [parsed], _} = EventParser.parse_event(%{"type" => "message_stop"}, "")

      refute Map.has_key?(parsed, :structured_output)
    end
  end

  describe "parse_event/2 assistant errors" do
    test "propagates top-level error on message_stop" do
      event = %{"type" => "message_stop", "error" => "billing_error"}

      {:ok, [parsed], new_acc} = EventParser.parse_event(event, "final text")

      assert parsed.type == :message_stop
      assert parsed.error == :billing_error
      assert parsed.final_text == "final text"
      assert new_acc == ""
    end

    test "propagates nested error on message_stop" do
      event = %{
        "type" => "message_stop",
        "message" => %{"error" => "authentication_failed"}
      }

      {:ok, [parsed], _} = EventParser.parse_event(event, "")

      assert parsed.error == :authentication_failed
    end
  end
end
