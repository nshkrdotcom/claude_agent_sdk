defmodule ClaudeAgentSDK.Message.TaskTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Message

  describe "task_started system message" do
    test "parses task_started subtype with structured fields" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "subtype" => "task_started",
          "task_id" => "task-abc",
          "description" => "Running tests",
          "uuid" => "uuid-123",
          "session_id" => "sess-1",
          "tool_use_id" => "tool-1",
          "task_type" => "general-purpose"
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.type == :system
      assert msg.subtype == :task_started
      assert msg.data.task_id == "task-abc"
      assert msg.data.description == "Running tests"
      assert msg.data.uuid == "uuid-123"
      assert msg.data.session_id == "sess-1"
      assert msg.data.tool_use_id == "tool-1"
      assert msg.data.task_type == "general-purpose"
    end

    test "parses task_started with optional fields absent" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "subtype" => "task_started",
          "task_id" => "task-abc",
          "description" => "Running tests",
          "uuid" => "uuid-123",
          "session_id" => "sess-1"
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.data.tool_use_id == nil
      assert msg.data.task_type == nil
    end
  end

  describe "task_progress system message" do
    test "parses task_progress with usage" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "subtype" => "task_progress",
          "task_id" => "task-abc",
          "description" => "Analyzing code",
          "uuid" => "uuid-456",
          "session_id" => "sess-1",
          "usage" => %{
            "total_tokens" => 5000,
            "tool_uses" => 3,
            "duration_ms" => 2000
          },
          "last_tool_name" => "Read"
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.type == :system
      assert msg.subtype == :task_progress
      assert msg.data.task_id == "task-abc"
      assert msg.data.description == "Analyzing code"
      assert msg.data.usage == %{"total_tokens" => 5000, "tool_uses" => 3, "duration_ms" => 2000}
      assert msg.data.last_tool_name == "Read"
    end
  end

  describe "task_notification system message" do
    test "parses task_notification completed" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "subtype" => "task_notification",
          "task_id" => "task-abc",
          "status" => "completed",
          "output_file" => "/tmp/output.txt",
          "summary" => "Analysis complete",
          "uuid" => "uuid-789",
          "session_id" => "sess-1",
          "usage" => %{
            "total_tokens" => 10_000,
            "tool_uses" => 7,
            "duration_ms" => 5000
          }
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.type == :system
      assert msg.subtype == :task_notification
      assert msg.data.task_id == "task-abc"
      assert msg.data.status == "completed"
      assert msg.data.output_file == "/tmp/output.txt"
      assert msg.data.summary == "Analysis complete"
      assert msg.data.usage["total_tokens"] == 10_000
    end

    test "parses task_notification failed" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "subtype" => "task_notification",
          "task_id" => "task-abc",
          "status" => "failed",
          "output_file" => "/tmp/output.txt",
          "summary" => "Task failed",
          "uuid" => "uuid-789",
          "session_id" => "sess-1"
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.data.status == "failed"
      assert msg.data.usage == nil
    end

    test "parses task_notification stopped" do
      json =
        Jason.encode!(%{
          "type" => "system",
          "subtype" => "task_notification",
          "task_id" => "task-abc",
          "status" => "stopped",
          "output_file" => "/tmp/output.txt",
          "summary" => "Stopped by user",
          "uuid" => "uuid-789",
          "session_id" => "sess-1"
        })

      {:ok, msg} = Message.from_json(json)
      assert msg.data.status == "stopped"
    end
  end
end
