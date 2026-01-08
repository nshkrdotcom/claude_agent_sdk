defmodule ResearchAgent.HookCoordinatorTest do
  use ExUnit.Case, async: true

  alias ResearchAgent.{HookCoordinator, SubagentTracker}

  describe "build_hooks/1" do
    test "returns a valid hooks configuration map" do
      {:ok, tracker} = SubagentTracker.start_link(name: :hook_test_tracker)
      on_exit(fn -> if Process.alive?(tracker), do: GenServer.stop(tracker) end)

      hooks = HookCoordinator.build_hooks(tracker)

      assert is_map(hooks)
      assert Map.has_key?(hooks, :pre_tool_use)
      assert Map.has_key?(hooks, :post_tool_use)
    end

    test "pre_tool_use hooks track Task tool spawns" do
      {:ok, tracker} = SubagentTracker.start_link(name: :pre_hook_tracker)
      on_exit(fn -> if Process.alive?(tracker), do: GenServer.stop(tracker) end)

      hooks = HookCoordinator.build_hooks(tracker)

      # Extract the pre_tool_use callbacks
      [matcher] = hooks.pre_tool_use
      [callback | _] = matcher.hooks

      # Simulate a Task tool call
      input = %{
        "tool_name" => "Task",
        "tool_input" => %{
          "description" => "Research quantum computing",
          "subagent_type" => "researcher"
        }
      }

      # Call the callback
      result = callback.(input, "toolu_123", %{})

      # Verify agent was tracked
      agents = SubagentTracker.list_agents(tracker)
      assert length(agents) == 1
      assert hd(agents).role == "researcher"

      # Verify it returns an allow output
      assert result.hookSpecificOutput.permissionDecision == "allow"
    end

    test "post_tool_use hooks mark agents as completed" do
      {:ok, tracker} = SubagentTracker.start_link(name: :post_hook_tracker)
      on_exit(fn -> if Process.alive?(tracker), do: GenServer.stop(tracker) end)

      hooks = HookCoordinator.build_hooks(tracker)

      # First spawn an agent
      [pre_matcher] = hooks.pre_tool_use
      [pre_callback | _] = pre_matcher.hooks

      spawn_input = %{
        "tool_name" => "Task",
        "tool_input" => %{
          "description" => "Analyze data",
          "subagent_type" => "analyst"
        }
      }

      pre_callback.(spawn_input, "toolu_456", %{})

      # Now complete it
      [post_matcher] = hooks.post_tool_use
      [post_callback | _] = post_matcher.hooks

      complete_input = %{
        "tool_name" => "Task",
        "tool_response" => %{"content" => "Analysis complete"}
      }

      post_callback.(complete_input, "toolu_456", %{})

      # Verify completion
      agents = SubagentTracker.list_agents(tracker)
      assert length(agents) == 1
      assert hd(agents).status == :completed
    end

    test "ignores non-Task tools" do
      {:ok, tracker} = SubagentTracker.start_link(name: :ignore_tracker)
      on_exit(fn -> if Process.alive?(tracker), do: GenServer.stop(tracker) end)

      hooks = HookCoordinator.build_hooks(tracker)
      [matcher] = hooks.pre_tool_use
      [callback | _] = matcher.hooks

      # Bash tool should be ignored
      input = %{
        "tool_name" => "Bash",
        "tool_input" => %{"command" => "ls -la"}
      }

      result = callback.(input, "toolu_789", %{})

      # Should still return allow but not track anything
      agents = SubagentTracker.list_agents(tracker)
      assert agents == []
      assert result == %{}
    end
  end

  describe "create_audit_hook/0" do
    test "creates a logging callback" do
      callback = HookCoordinator.create_audit_hook()
      assert is_function(callback, 3)

      # Should not raise when called
      result = callback.(%{"tool_name" => "Read"}, "test_id", %{})
      assert result == %{}
    end
  end
end
