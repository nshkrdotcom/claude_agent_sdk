defmodule ClaudeAgentSDK.Parity.MessageToolUseResultTest do
  @moduledoc """
  Tests for Phase 6: tool_use_result field in user messages.

  The user message parser (Message.parse_by_type/3 for :user) extracts
  the `tool_use_result` field from the raw JSON into the data map.
  This verifies correct parsing behavior for messages with and without
  that field.
  """

  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Message

  describe "user message with tool_use_result" do
    test "parses tool_use_result correctly" do
      json =
        Jason.encode!(%{
          "type" => "user",
          "session_id" => "sess-123",
          "message" => %{
            "role" => "user",
            "content" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_abc",
                "content" => "Result text"
              }
            ]
          },
          "tool_use_result" => %{
            "tool_use_id" => "toolu_abc",
            "output" => "some output",
            "is_error" => false
          }
        })

      assert {:ok, %Message{type: :user, data: data}} = Message.from_json(json)

      assert data.tool_use_result == %{
               "tool_use_id" => "toolu_abc",
               "output" => "some output",
               "is_error" => false
             }
    end

    test "user message without tool_use_result has nil for that field" do
      json =
        Jason.encode!(%{
          "type" => "user",
          "session_id" => "sess-456",
          "message" => %{
            "role" => "user",
            "content" => "Hello, how are you?"
          }
        })

      assert {:ok, %Message{type: :user, data: data}} = Message.from_json(json)

      assert data.tool_use_result == nil
    end

    test "tool_use_result with nested content round-trips through from_json/1" do
      tool_use_result = %{
        "tool_use_id" => "toolu_xyz",
        "output" => "File contents here",
        "is_error" => false,
        "content" => [
          %{"type" => "text", "text" => "Read 42 bytes"}
        ]
      }

      json =
        Jason.encode!(%{
          "type" => "user",
          "session_id" => "sess-789",
          "parent_tool_use_id" => "toolu_parent",
          "message" => %{
            "role" => "user",
            "content" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_xyz",
                "content" => "Read 42 bytes"
              }
            ]
          },
          "tool_use_result" => tool_use_result
        })

      assert {:ok, %Message{type: :user, data: data}} = Message.from_json(json)

      assert data.tool_use_result == tool_use_result
      assert data.parent_tool_use_id == "toolu_parent"
      assert data.session_id == "sess-789"
    end

    test "tool_use_result with is_error true is preserved" do
      json =
        Jason.encode!(%{
          "type" => "user",
          "session_id" => "sess-err",
          "message" => %{
            "role" => "user",
            "content" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "toolu_fail",
                "content" => "Permission denied",
                "is_error" => true
              }
            ]
          },
          "tool_use_result" => %{
            "tool_use_id" => "toolu_fail",
            "output" => "Permission denied",
            "is_error" => true
          }
        })

      assert {:ok, %Message{type: :user, data: data}} = Message.from_json(json)

      assert data.tool_use_result["is_error"] == true
      assert data.tool_use_result["tool_use_id"] == "toolu_fail"
    end

    test "other user message fields are unaffected by presence of tool_use_result" do
      json =
        Jason.encode!(%{
          "type" => "user",
          "session_id" => "sess-full",
          "uuid" => "uuid-12345",
          "parent_tool_use_id" => "toolu_parent_full",
          "message" => %{
            "role" => "user",
            "content" => "tool output"
          },
          "tool_use_result" => %{
            "tool_use_id" => "toolu_full",
            "output" => "done"
          }
        })

      assert {:ok, %Message{type: :user, data: data}} = Message.from_json(json)

      assert data.session_id == "sess-full"
      assert data.parent_tool_use_id == "toolu_parent_full"
      assert data.message == %{"role" => "user", "content" => "tool output"}
      assert data.tool_use_result == %{"tool_use_id" => "toolu_full", "output" => "done"}
      assert data.uuid == "uuid-12345"
    end
  end
end
