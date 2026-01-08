defmodule SkillInvocation.SkillTrackerTest do
  use ExUnit.Case, async: true

  alias SkillInvocation.SkillTracker

  setup do
    # Start a fresh tracker for each test
    {:ok, pid} = SkillTracker.start_link(name: nil)
    {:ok, tracker: pid}
  end

  describe "start_link/1" do
    test "starts the tracker GenServer" do
      assert {:ok, pid} = SkillTracker.start_link(name: nil)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with empty state" do
      {:ok, pid} = SkillTracker.start_link(name: nil)

      assert SkillTracker.get_invocations(pid) == []
      assert SkillTracker.get_stats(pid) == %{total: 0, by_skill: %{}}

      GenServer.stop(pid)
    end
  end

  describe "track_skill_invocation/4" do
    test "tracks a skill invocation", %{tracker: tracker} do
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_123", "commit", nil)

      invocations = SkillTracker.get_invocations(tracker)
      assert length(invocations) == 1

      [invocation] = invocations
      assert invocation.tool_use_id == "tool_123"
      assert invocation.skill_name == "commit"
      assert invocation.args == nil
      assert invocation.status == :started
      assert %DateTime{} = invocation.started_at
    end

    test "tracks skill with arguments", %{tracker: tracker} do
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_456", "pdf", "doc.pdf")

      [invocation] = SkillTracker.get_invocations(tracker)
      assert invocation.skill_name == "pdf"
      assert invocation.args == "doc.pdf"
    end

    test "tracks multiple invocations", %{tracker: tracker} do
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_1", "commit", nil)
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_2", "pdf", "file.pdf")
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_3", "commit", "-m 'test'")

      invocations = SkillTracker.get_invocations(tracker)
      assert length(invocations) == 3
    end
  end

  describe "complete_skill_invocation/3" do
    test "marks invocation as completed", %{tracker: tracker} do
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_123", "commit", nil)
      :ok = SkillTracker.complete_skill_invocation(tracker, "tool_123", :success)

      [invocation] = SkillTracker.get_invocations(tracker)
      assert invocation.status == :completed
      assert invocation.result == :success
      assert %DateTime{} = invocation.completed_at
    end

    test "marks invocation as failed", %{tracker: tracker} do
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_123", "commit", nil)
      :ok = SkillTracker.complete_skill_invocation(tracker, "tool_123", :error)

      [invocation] = SkillTracker.get_invocations(tracker)
      assert invocation.status == :completed
      assert invocation.result == :error
    end

    test "returns error for unknown tool_use_id", %{tracker: tracker} do
      result = SkillTracker.complete_skill_invocation(tracker, "unknown_id", :success)
      assert result == {:error, :not_found}
    end
  end

  describe "get_stats/1" do
    test "returns correct statistics", %{tracker: tracker} do
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_1", "commit", nil)
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_2", "pdf", "file.pdf")
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_3", "commit", "-m 'fix'")

      stats = SkillTracker.get_stats(tracker)

      assert stats.total == 3
      assert stats.by_skill["commit"] == 2
      assert stats.by_skill["pdf"] == 1
    end
  end

  describe "clear/1" do
    test "clears all tracked invocations", %{tracker: tracker} do
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_1", "commit", nil)
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_2", "pdf", "file.pdf")

      assert length(SkillTracker.get_invocations(tracker)) == 2

      :ok = SkillTracker.clear(tracker)

      assert SkillTracker.get_invocations(tracker) == []
      assert SkillTracker.get_stats(tracker) == %{total: 0, by_skill: %{}}
    end
  end

  describe "pre_tool_use_hook/3" do
    test "tracks Skill tool invocations", %{tracker: tracker} do
      input = %{
        "tool_name" => "Skill",
        "tool_input" => %{
          "skill" => "commit",
          "args" => "-m 'test'"
        }
      }

      result = SkillTracker.pre_tool_use_hook(tracker, input, "tool_abc", %{})

      assert result == %{}

      [invocation] = SkillTracker.get_invocations(tracker)
      assert invocation.skill_name == "commit"
      assert invocation.args == "-m 'test'"
    end

    test "ignores non-Skill tools", %{tracker: tracker} do
      input = %{
        "tool_name" => "Bash",
        "tool_input" => %{"command" => "echo hello"}
      }

      result = SkillTracker.pre_tool_use_hook(tracker, input, "tool_xyz", %{})

      assert result == %{}
      assert SkillTracker.get_invocations(tracker) == []
    end
  end

  describe "post_tool_use_hook/3" do
    test "completes tracked Skill invocations", %{tracker: tracker} do
      # First, track the invocation
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_abc", "commit", nil)

      input = %{
        "tool_name" => "Skill",
        "tool_response" => %{"is_error" => false}
      }

      result = SkillTracker.post_tool_use_hook(tracker, input, "tool_abc", %{})

      assert result == %{}

      [invocation] = SkillTracker.get_invocations(tracker)
      assert invocation.status == :completed
      assert invocation.result == :success
    end

    test "marks error responses correctly", %{tracker: tracker} do
      :ok = SkillTracker.track_skill_invocation(tracker, "tool_abc", "commit", nil)

      input = %{
        "tool_name" => "Skill",
        "tool_response" => %{"is_error" => true}
      }

      SkillTracker.post_tool_use_hook(tracker, input, "tool_abc", %{})

      [invocation] = SkillTracker.get_invocations(tracker)
      assert invocation.result == :error
    end

    test "ignores non-Skill tools", %{tracker: tracker} do
      input = %{
        "tool_name" => "Bash",
        "tool_response" => %{}
      }

      result = SkillTracker.post_tool_use_hook(tracker, input, "tool_xyz", %{})

      assert result == %{}
    end
  end
end
