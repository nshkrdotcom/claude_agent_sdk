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

  test "content_blocks/1 preserves server-side tool use and advisor results" do
    json =
      Jason.encode!(%{
        "type" => "assistant",
        "uuid" => "msg-uuid",
        "session_id" => "s",
        "message" => %{
          "id" => "msg_123",
          "role" => "assistant",
          "model" => "claude-sonnet",
          "stop_reason" => "end_turn",
          "usage" => %{"input_tokens" => 10},
          "content" => [
            %{
              "type" => "server_tool_use",
              "id" => "srv_1",
              "name" => "web_search",
              "input" => %{"query" => "latest"}
            },
            %{
              "type" => "advisor_tool_result",
              "tool_use_id" => "srv_1",
              "content" => %{"type" => "web_search_result", "items" => []}
            }
          ]
        }
      })

    assert {:ok, %Message{type: :assistant, data: data} = msg} = Message.from_json(json)

    assert data.uuid == "msg-uuid"
    assert data.message_id == "msg_123"
    assert data.stop_reason == "end_turn"
    assert data.usage == %{"input_tokens" => 10}

    assert [
             %{
               type: :server_tool_use,
               id: "srv_1",
               name: "web_search",
               input: %{"query" => "latest"}
             },
             %{
               type: :advisor_tool_result,
               tool_use_id: "srv_1",
               content: %{"type" => "web_search_result", "items" => []}
             }
           ] = Message.content_blocks(msg)
  end

  test "result messages preserve model usage permission denials errors and uuid" do
    json =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "success",
        "uuid" => "result-uuid",
        "session_id" => "s",
        "result" => "ok",
        "total_cost_usd" => 0.0,
        "duration_ms" => 1,
        "duration_api_ms" => 1,
        "num_turns" => 1,
        "is_error" => false,
        "modelUsage" => %{"claude-sonnet" => %{"input_tokens" => 10}},
        "permission_denials" => [%{"tool_name" => "Bash"}],
        "errors" => ["warning"]
      })

    assert {:ok, %Message{type: :result, data: data}} = Message.from_json(json)
    assert data.uuid == "result-uuid"
    assert data.model_usage == %{"claude-sonnet" => %{"input_tokens" => 10}}
    assert data.permission_denials == [%{"tool_name" => "Bash"}]
    assert data.errors == ["warning"]
  end

  test "mirror_error system messages are surfaced" do
    json =
      Jason.encode!(%{
        "type" => "system",
        "subtype" => "mirror_error",
        "session_id" => "s",
        "key" => %{"project_key" => "proj", "session_id" => "s"},
        "error" => "append failed"
      })

    assert {:ok, %Message{type: :system, subtype: :mirror_error, data: data}} =
             Message.from_json(json)

    assert data.key == %{"project_key" => "proj", "session_id" => "s"}
    assert data.error == "append failed"
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

  test "stream_event wrappers keep control-lane metadata optional" do
    json =
      Jason.encode!(%{
        "type" => "stream_event",
        "session_id" => "sess-123",
        "event" => %{"type" => "message_stop"}
      })

    assert {:ok, %Message{type: :stream_event, data: data}} = Message.from_json(json)
    assert data.session_id == "sess-123"
    assert data.uuid == nil
    assert data.event["type"] == "message_stop"
  end
end
