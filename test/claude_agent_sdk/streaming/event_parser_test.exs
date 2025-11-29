defmodule ClaudeAgentSDK.Streaming.EventParserTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Streaming.EventParser

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
end
