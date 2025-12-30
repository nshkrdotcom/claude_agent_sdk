defmodule ClaudeAgentSDK.MessageParityTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Message

  test "result messages expose usage in data" do
    json =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "s",
        "result" => "ok",
        "total_cost_usd" => 0.0,
        "duration_ms" => 1,
        "duration_api_ms" => 1,
        "num_turns" => 1,
        "is_error" => false,
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      })

    assert {:ok, %Message{type: :result, data: data}} = Message.from_json(json)
    assert data.usage == %{"input_tokens" => 10, "output_tokens" => 5}
  end

  test "user/assistant messages expose parent_tool_use_id in data" do
    user_json =
      Jason.encode!(%{
        "type" => "user",
        "session_id" => "s",
        "parent_tool_use_id" => "toolu_123",
        "message" => %{"role" => "user", "content" => "hi"}
      })

    assert {:ok, %Message{type: :user, data: user_data}} = Message.from_json(user_json)
    assert user_data.parent_tool_use_id == "toolu_123"

    assistant_json =
      Jason.encode!(%{
        "type" => "assistant",
        "session_id" => "s",
        "parent_tool_use_id" => "toolu_123",
        "message" => %{"role" => "assistant", "content" => "hi"}
      })

    assert {:ok, %Message{type: :assistant, data: assistant_data}} =
             Message.from_json(assistant_json)

    assert assistant_data.parent_tool_use_id == "toolu_123"
  end

  test "content_blocks/1 parses structured content blocks" do
    json =
      Jason.encode!(%{
        "type" => "assistant",
        "session_id" => "s",
        "message" => %{
          "role" => "assistant",
          "content" => [
            %{"type" => "text", "text" => "Hello"},
            %{
              "type" => "tool_use",
              "id" => "toolu_1",
              "name" => "Bash",
              "input" => %{"command" => "ls"}
            }
          ]
        }
      })

    assert {:ok, %Message{} = msg} = Message.from_json(json)

    assert [
             %{type: :text, text: "Hello"},
             %{type: :tool_use, id: "toolu_1", name: "Bash", input: %{"command" => "ls"}}
           ] = Message.content_blocks(msg)
  end

  test "unknown message types are preserved as strings" do
    json = Jason.encode!(%{"type" => "new_message_type", "foo" => "bar"})

    assert {:ok, %Message{type: type, data: data}} = Message.from_json(json)
    assert type == "new_message_type"
    assert data["foo"] == "bar"
  end

  test "unknown result subtypes remain strings" do
    json =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "error_future",
        "session_id" => "s",
        "duration_ms" => 1,
        "duration_api_ms" => 1,
        "num_turns" => 1,
        "is_error" => true
      })

    assert {:ok, %Message{type: :result, subtype: subtype}} = Message.from_json(json)
    assert subtype == "error_future"
  end
end
