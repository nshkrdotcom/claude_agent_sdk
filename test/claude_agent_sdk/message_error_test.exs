defmodule ClaudeAgentSDK.MessageErrorTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Message

  describe "from_json/1 with assistant error" do
    test "parses assistant error enum from nested message.error" do
      json =
        ~s({"type":"assistant","message":{"role":"assistant","content":"oops","error":"rate_limit"},"session_id":"s1"})

      {:ok, message} = Message.from_json(json)

      assert message.type == :assistant
      assert message.data.error == :rate_limit
    end

    test "falls back to root error for backwards compatibility" do
      json =
        ~s({"type":"assistant","message":{"role":"assistant","content":"oops"},"session_id":"s1","error":"rate_limit"})

      {:ok, message} = Message.from_json(json)

      assert message.data.error == :rate_limit
    end

    test "maps unknown assistant error values to :unknown" do
      json =
        ~s({"type":"assistant","message":{"role":"assistant","content":"oops","error":"some_new_error"},"session_id":"s1"})

      {:ok, message} = Message.from_json(json)

      assert message.data.error == :unknown
    end

    test "leaves error nil when field absent" do
      json =
        ~s({"type":"assistant","message":{"role":"assistant","content":"all good"},"session_id":"s1"})

      {:ok, message} = Message.from_json(json)

      assert message.type == :assistant
      assert is_nil(Map.get(message.data, :error))
    end

    test "rejects malformed JSON instead of falling back to partial regex parsing" do
      malformed_json =
        ~s({"type":"assistant","message":{"role":"assistant","content":"oops"},"session_id":"s1")

      assert {:error, {:parse_error, _reason}} = Message.from_json(malformed_json)
    end
  end

  describe "from_json/1 with result errors" do
    test "reclassifies success subtypes with is_error=true as execution errors" do
      json =
        Jason.encode!(%{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "s1",
          "result" =>
            "Your organization does not have access to Claude. Please login again or contact your administrator.",
          "duration_ms" => 12,
          "duration_api_ms" => 10,
          "num_turns" => 1,
          "is_error" => true
        })

      {:ok, message} = Message.from_json(json)

      assert message.type == :result
      assert message.subtype == :error_during_execution
      assert message.data.error =~ "organization does not have access"
      assert Message.error?(message)
    end
  end
end
