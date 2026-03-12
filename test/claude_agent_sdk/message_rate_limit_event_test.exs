defmodule ClaudeAgentSDK.MessageRateLimitEventTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Message

  describe "from_json/1 with rate_limit_event" do
    test "parses a typed rate_limit_event with structured info" do
      json =
        Jason.encode!(%{
          "type" => "rate_limit_event",
          "rate_limit_info" => %{
            "status" => "allowed_warning",
            "resetsAt" => 1_700_000_000,
            "rateLimitType" => "five_hour",
            "utilization" => 0.85,
            "isUsingOverage" => false
          },
          "uuid" => "550e8400-e29b-41d4-a716-446655440000",
          "session_id" => "test-session-id"
        })

      assert {:ok, %Message{type: :rate_limit_event, data: data}} = Message.from_json(json)

      assert data.uuid == "550e8400-e29b-41d4-a716-446655440000"
      assert data.session_id == "test-session-id"
      assert data.rate_limit_info.status == "allowed_warning"
      assert data.rate_limit_info.resets_at == 1_700_000_000
      assert data.rate_limit_info.rate_limit_type == "five_hour"
      assert data.rate_limit_info.utilization == 0.85
      assert data.rate_limit_info.raw["isUsingOverage"] == false
    end

    test "parses minimal rate_limit_event payloads" do
      json =
        Jason.encode!(%{
          "type" => "rate_limit_event",
          "rate_limit_info" => %{"status" => "allowed"},
          "uuid" => "770e8400-e29b-41d4-a716-446655440002",
          "session_id" => "test-session-id"
        })

      assert {:ok, %Message{type: :rate_limit_event, data: data}} = Message.from_json(json)

      assert data.rate_limit_info.status == "allowed"
      assert data.rate_limit_info.resets_at == nil
      assert data.rate_limit_info.rate_limit_type == nil

      assert Message.session_id(%Message{type: :rate_limit_event, data: data, raw: %{}}) ==
               "test-session-id"
    end
  end
end
