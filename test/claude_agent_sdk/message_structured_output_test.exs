defmodule ClaudeAgentSDK.MessageStructuredOutputTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Message

  describe "from_json/1 with structured_output" do
    test "parses structured_output on success result" do
      json =
        ~s({"type":"result","subtype":"success","session_id":"s1","result":"ok","structured_output":{"status":"ok","count":2},"total_cost_usd":0.1,"duration_ms":10,"duration_api_ms":8,"num_turns":1,"is_error":false})

      {:ok, message} = Message.from_json(json)

      assert message.type == :result
      assert message.subtype == :success
      assert message.data.result == "ok"
      assert message.data.structured_output == %{"status" => "ok", "count" => 2}
    end

    test "missing structured_output leaves field nil" do
      json =
        ~s({"type":"result","subtype":"success","session_id":"s2","result":"ok","total_cost_usd":0.1,"duration_ms":10,"duration_api_ms":8,"num_turns":1,"is_error":false})

      {:ok, message} = Message.from_json(json)

      assert message.type == :result
      refute Map.get(message.data, :structured_output)
    end
  end
end
