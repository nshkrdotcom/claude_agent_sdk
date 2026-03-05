defmodule ClaudeAgentSDK.Message.StopReasonTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Message

  describe "stop_reason in result messages" do
    test "parses stop_reason from success result" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "s1",
          "result" => "done",
          "stop_reason" => "end_turn",
          "duration_ms" => 100,
          "duration_api_ms" => 80,
          "num_turns" => 1,
          "is_error" => false,
          "total_cost_usd" => 0.001
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.type == :result
      assert msg.subtype == :success
      assert msg.data.stop_reason == "end_turn"
    end

    test "stop_reason defaults to nil when absent" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "s1",
          "result" => "done",
          "duration_ms" => 100,
          "duration_api_ms" => 80,
          "num_turns" => 1,
          "is_error" => false,
          "total_cost_usd" => 0.001
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.data.stop_reason == nil
    end

    test "parses stop_reason from error result" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "subtype" => "error_max_turns",
          "session_id" => "s1",
          "stop_reason" => "max_turns",
          "duration_ms" => 100,
          "duration_api_ms" => 80,
          "num_turns" => 5,
          "is_error" => true
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.data.stop_reason == "max_turns"
    end
  end
end
