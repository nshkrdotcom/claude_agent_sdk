defmodule ClaudeAgentSDK.MessageUuidTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Message

  describe "user message uuid parsing" do
    test "parses uuid from user message into data.uuid" do
      json =
        ~s({"type":"user","uuid":"msg-abc123-def456","message":{"content":[{"type":"text","text":"Hello"}]}})

      assert {:ok, message} = Message.from_json(json)
      assert message.type == :user
      assert message.data.uuid == "msg-abc123-def456"
    end

    test "handles user message without uuid gracefully" do
      json = ~s({"type":"user","message":{"content":[{"type":"text","text":"Hello"}]}})

      assert {:ok, message} = Message.from_json(json)
      assert message.type == :user
      refute Map.has_key?(message.data, :uuid)
    end

    test "handles empty uuid string" do
      json = ~s({"type":"user","uuid":"","message":{"content":[{"type":"text","text":"Hello"}]}})

      assert {:ok, message} = Message.from_json(json)
      assert message.type == :user
      refute Map.has_key?(message.data, :uuid)
    end
  end

  describe "user_uuid/1 helper" do
    test "returns uuid from user message data" do
      message = %Message{type: :user, data: %{uuid: "msg-123"}, raw: %{}}
      assert Message.user_uuid(message) == "msg-123"
    end

    test "falls back to raw when data.uuid missing" do
      message = %Message{type: :user, data: %{}, raw: %{"uuid" => "msg-456"}}
      assert Message.user_uuid(message) == "msg-456"
    end

    test "returns nil for non-user messages" do
      message = %Message{type: :assistant, data: %{}, raw: %{}}
      assert Message.user_uuid(message) == nil
    end

    test "returns nil when no uuid present" do
      message = %Message{type: :user, data: %{}, raw: %{}}
      assert Message.user_uuid(message) == nil
    end
  end
end
