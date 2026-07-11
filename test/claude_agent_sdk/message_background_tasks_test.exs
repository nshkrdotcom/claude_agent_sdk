defmodule ClaudeAgentSDK.MessageBackgroundTasksTest do
  @moduledoc """
  Coverage for the `background_tasks_changed` system frame (CLI 2.1.203+ /
  TS v0.3.203): a level-based frame carrying the full live background-task
  set on every membership change (vs the task_started/task_notification
  edge frames).
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.Message

  defp parse!(map) do
    {:ok, msg} = map |> Jason.encode!() |> Message.from_json()
    msg
  end

  test "parses background_tasks_changed into a typed task list" do
    msg =
      parse!(%{
        "type" => "system",
        "subtype" => "background_tasks_changed",
        "session_id" => "s1",
        "uuid" => "u1",
        "tasks" => [
          %{"task_id" => "t1", "task_type" => "local_bash", "description" => "a"},
          %{"task_id" => "t2", "task_type" => "agent", "description" => "b"}
        ]
      })

    assert msg.type == :system
    assert msg.subtype == :background_tasks_changed
    assert length(msg.data.tasks) == 2
    assert Enum.map(msg.data.tasks, & &1.task_id) == ["t1", "t2"]
    assert Enum.map(msg.data.tasks, & &1.task_type) == ["local_bash", "agent"]
    assert msg.data.session_id == "s1"
    assert msg.data.uuid == "u1"
  end

  test "live_background_tasks/1 keeps statusless tasks and drops terminal ones" do
    msg =
      parse!(%{
        "type" => "system",
        "subtype" => "background_tasks_changed",
        "tasks" => [
          %{"task_id" => "t1", "status" => "running"},
          %{"task_id" => "t2", "status" => "completed"},
          %{"task_id" => "t3"}
        ]
      })

    live = Message.live_background_tasks(msg)
    assert Enum.map(live, & &1.task_id) == ["t1", "t3"]
  end

  test "live_background_tasks/1 returns [] for other messages" do
    msg = parse!(%{"type" => "system", "subtype" => "init", "session_id" => "s"})
    assert Message.live_background_tasks(msg) == []
  end

  test "empty tasks array parses to []" do
    msg =
      parse!(%{
        "type" => "system",
        "subtype" => "background_tasks_changed",
        "tasks" => []
      })

    assert msg.data.tasks == []
    assert Message.live_background_tasks(msg) == []
  end

  test "absent tasks key parses to []" do
    msg = parse!(%{"type" => "system", "subtype" => "background_tasks_changed"})
    assert msg.data.tasks == []
  end

  test "unknown per-task keys survive" do
    msg =
      parse!(%{
        "type" => "system",
        "subtype" => "background_tasks_changed",
        "tasks" => [%{"task_id" => "t1", "future_field" => 1}]
      })

    [task] = msg.data.tasks
    assert task["future_field"] == 1
  end

  test "the live golden fixture parses with a typed task list" do
    fixture =
      Path.expand(
        "../support/fixtures/cli_2_1_207/system_background_tasks_changed.jsonl",
        __DIR__
      )

    {:ok, msg} = fixture |> File.read!() |> String.trim() |> Message.from_json()
    assert msg.subtype == :background_tasks_changed
    assert [%{task_id: "bmeym4cxp", task_type: "local_bash"}] = msg.data.tasks
    assert [%{task_id: "bmeym4cxp"}] = Message.live_background_tasks(msg)
  end
end
