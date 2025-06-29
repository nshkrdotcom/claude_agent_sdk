defmodule ClaudeCodeSDK.MessageTest do
  use ExUnit.Case
  alias ClaudeCodeSDK.Message

  describe "from_json/1" do
    test "parses assistant message" do
      json = ~s({"type": "assistant", "message": {"role": "assistant", "content": "Hello"}, "session_id": "123"})
      
      assert {:ok, message} = Message.from_json(json)
      assert message.type == :assistant
      assert message.data.session_id == "123"
      assert message.data.message["content"] == "Hello"
    end

    test "parses user message" do
      json = ~s({"type": "user", "message": {"role": "user", "content": "Hi"}, "session_id": "123"})
      
      assert {:ok, message} = Message.from_json(json)
      assert message.type == :user
      assert message.data.session_id == "123"
      assert message.data.message["content"] == "Hi"
    end

    test "parses success result message" do
      json = ~s({
        "type": "result",
        "subtype": "success",
        "result": "Task completed",
        "session_id": "123",
        "total_cost_usd": 0.003,
        "duration_ms": 1500,
        "duration_api_ms": 1000,
        "num_turns": 2,
        "is_error": false
      })
      
      assert {:ok, message} = Message.from_json(json)
      assert message.type == :result
      assert message.subtype == :success
      assert message.data.result == "Task completed"
      assert message.data.session_id == "123"
      assert message.data.total_cost_usd == 0.003
      assert message.data.duration_ms == 1500
      assert message.data.duration_api_ms == 1000
      assert message.data.num_turns == 2
      assert message.data.is_error == false
    end

    test "parses error result message" do
      json = ~s({
        "type": "result",
        "subtype": "error_max_turns",
        "session_id": "123",
        "total_cost_usd": 0.005,
        "duration_ms": 5000,
        "duration_api_ms": 4000,
        "num_turns": 10,
        "is_error": true
      })
      
      assert {:ok, message} = Message.from_json(json)
      assert message.type == :result
      assert message.subtype == :error_max_turns
      assert message.data.session_id == "123"
      assert message.data.is_error == true
    end

    test "parses system init message" do
      json = ~s({
        "type": "system",
        "subtype": "init",
        "apiKeySource": "env",
        "cwd": "/home/user",
        "session_id": "123",
        "tools": ["Read", "Write"],
        "mcp_servers": [{"name": "test", "status": "ready"}],
        "model": "claude-3",
        "permissionMode": "default"
      })
      
      assert {:ok, message} = Message.from_json(json)
      assert message.type == :system
      assert message.subtype == :init
      assert message.data.api_key_source == "env"
      assert message.data.cwd == "/home/user"
      assert message.data.session_id == "123"
      assert message.data.tools == ["Read", "Write"]
      assert length(message.data.mcp_servers) == 1
      assert message.data.model == "claude-3"
      assert message.data.permission_mode == "default"
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = Message.from_json("invalid json")
    end
  end

  describe "final?/1" do
    test "returns true for result messages" do
      message = %Message{type: :result}
      assert Message.final?(message)
    end

    test "returns false for non-result messages" do
      assert not Message.final?(%Message{type: :assistant})
      assert not Message.final?(%Message{type: :user})
      assert not Message.final?(%Message{type: :system})
    end
  end

  describe "error?/1" do
    test "returns true for error result messages" do
      assert Message.error?(%Message{type: :result, subtype: :error_max_turns})
      assert Message.error?(%Message{type: :result, subtype: :error_during_execution})
    end

    test "returns false for success result messages" do
      assert not Message.error?(%Message{type: :result, subtype: :success})
    end

    test "returns false for non-result messages" do
      assert not Message.error?(%Message{type: :assistant})
      assert not Message.error?(%Message{type: :user})
    end
  end

  describe "session_id/1" do
    test "returns session ID when present" do
      message = %Message{data: %{session_id: "test-123"}}
      assert Message.session_id(message) == "test-123"
    end

    test "returns nil when not present" do
      assert is_nil(Message.session_id(%Message{data: %{}}))
      assert is_nil(Message.session_id(%Message{}))
    end
  end
end