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
      assert Enum.any?(hooks.pre_tool_use, &(&1.matcher == "Agent"))
      assert Enum.any?(hooks.pre_tool_use, &(&1.matcher == "*"))
      assert Enum.any?(hooks.post_tool_use, &(&1.matcher == "Agent"))
    end

    test "pre_tool_use hooks track Agent tool spawns" do
      {:ok, tracker} = SubagentTracker.start_link(name: :pre_hook_tracker)
      on_exit(fn -> if Process.alive?(tracker), do: GenServer.stop(tracker) end)

      hooks = HookCoordinator.build_hooks(tracker)

      matcher = Enum.find(hooks.pre_tool_use, &(&1.matcher == "Agent"))
      [callback] = matcher.hooks

      # Simulate an Agent tool call
      input = %{
        "tool_name" => "Agent",
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
      pre_matcher = Enum.find(hooks.pre_tool_use, &(&1.matcher == "Agent"))
      [pre_callback] = pre_matcher.hooks

      spawn_input = %{
        "tool_name" => "Agent",
        "tool_input" => %{
          "description" => "Analyze data",
          "subagent_type" => "analyst"
        }
      }

      pre_callback.(spawn_input, "toolu_456", %{})

      # Now complete it
      post_matcher = Enum.find(hooks.post_tool_use, &(&1.matcher == "Agent"))
      [post_callback] = post_matcher.hooks

      complete_input = %{
        "tool_name" => "Agent",
        "tool_response" => %{"content" => "Analysis complete"}
      }

      post_callback.(complete_input, "toolu_456", %{})

      # Verify completion
      agents = SubagentTracker.list_agents(tracker)
      assert length(agents) == 1
      assert hd(agents).status == :completed
    end

    test "ignores non-Agent tools" do
      {:ok, tracker} = SubagentTracker.start_link(name: :ignore_tracker)
      on_exit(fn -> if Process.alive?(tracker), do: GenServer.stop(tracker) end)

      hooks = HookCoordinator.build_hooks(tracker)
      matcher = Enum.find(hooks.pre_tool_use, &(&1.matcher == "Agent"))
      [callback] = matcher.hooks

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
