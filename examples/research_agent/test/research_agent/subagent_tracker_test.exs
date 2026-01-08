defmodule ResearchAgent.SubagentTrackerTest do
  use ExUnit.Case, async: true

  alias ResearchAgent.SubagentTracker

  describe "start_link/1" do
    test "starts the tracker with a named ETS table" do
      {:ok, pid} = SubagentTracker.start_link(name: :test_tracker_1)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "creates an ETS table with the given name" do
      {:ok, pid} = SubagentTracker.start_link(name: :test_tracker_2)
      assert :ets.whereis(:test_tracker_2) != :undefined
      GenServer.stop(pid)
    end
  end

  describe "track_spawn/3" do
    setup do
      {:ok, pid} = SubagentTracker.start_link(name: :test_spawn_tracker)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{tracker: pid}
    end

    test "records a subagent spawn event", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "agent_1", "researcher")

      agents = SubagentTracker.list_agents(tracker)
      assert length(agents) == 1
      assert hd(agents).id == "agent_1"
      assert hd(agents).role == "researcher"
      assert hd(agents).status == :running
    end

    test "records metadata with spawn", %{tracker: tracker} do
      metadata = %{topic: "quantum computing", depth: "deep"}
      :ok = SubagentTracker.track_spawn(tracker, "agent_2", "researcher", metadata)

      agents = SubagentTracker.list_agents(tracker)
      agent = hd(agents)
      assert agent.metadata.topic == "quantum computing"
    end

    test "assigns a unique spawned_at timestamp", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "agent_3", "researcher")
      Process.sleep(5)
      :ok = SubagentTracker.track_spawn(tracker, "agent_4", "analyst")

      agents = SubagentTracker.list_agents(tracker)
      [a1, a2] = Enum.sort_by(agents, & &1.spawned_at)
      assert a1.spawned_at < a2.spawned_at
    end
  end

  describe "track_complete/2" do
    setup do
      {:ok, pid} = SubagentTracker.start_link(name: :test_complete_tracker)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{tracker: pid}
    end

    test "marks an agent as completed", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "agent_5", "researcher")
      :ok = SubagentTracker.track_complete(tracker, "agent_5")

      agents = SubagentTracker.list_agents(tracker)
      assert hd(agents).status == :completed
    end

    test "records completion time", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "agent_6", "analyst")
      Process.sleep(5)
      :ok = SubagentTracker.track_complete(tracker, "agent_6")

      agent = hd(SubagentTracker.list_agents(tracker))
      assert agent.completed_at != nil
      assert agent.completed_at > agent.spawned_at
    end

    test "stores result when provided", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "agent_7", "writer")
      result = %{report: "final report content"}
      :ok = SubagentTracker.track_complete(tracker, "agent_7", result)

      agent = hd(SubagentTracker.list_agents(tracker))
      assert agent.result == result
    end
  end

  describe "get_agent/2" do
    setup do
      {:ok, pid} = SubagentTracker.start_link(name: :test_get_tracker)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{tracker: pid}
    end

    test "retrieves an agent by ID", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "agent_8", "researcher")

      {:ok, agent} = SubagentTracker.get_agent(tracker, "agent_8")
      assert agent.id == "agent_8"
      assert agent.role == "researcher"
    end

    test "returns error for non-existent agent", %{tracker: tracker} do
      assert {:error, :not_found} = SubagentTracker.get_agent(tracker, "non_existent")
    end
  end

  describe "list_agents/1" do
    setup do
      {:ok, pid} = SubagentTracker.start_link(name: :test_list_tracker)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{tracker: pid}
    end

    test "returns all tracked agents", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "agent_9", "researcher")
      :ok = SubagentTracker.track_spawn(tracker, "agent_10", "analyst")
      :ok = SubagentTracker.track_spawn(tracker, "agent_11", "writer")

      agents = SubagentTracker.list_agents(tracker)
      assert length(agents) == 3
    end

    test "returns empty list when no agents", %{tracker: tracker} do
      assert SubagentTracker.list_agents(tracker) == []
    end
  end

  describe "list_by_role/2" do
    setup do
      {:ok, pid} = SubagentTracker.start_link(name: :test_role_tracker)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{tracker: pid}
    end

    test "filters agents by role", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "a1", "researcher")
      :ok = SubagentTracker.track_spawn(tracker, "a2", "analyst")
      :ok = SubagentTracker.track_spawn(tracker, "a3", "researcher")

      researchers = SubagentTracker.list_by_role(tracker, "researcher")
      assert length(researchers) == 2
      assert Enum.all?(researchers, &(&1.role == "researcher"))
    end
  end

  describe "get_summary/1" do
    setup do
      {:ok, pid} = SubagentTracker.start_link(name: :test_summary_tracker)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{tracker: pid}
    end

    test "returns aggregated statistics", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "s1", "researcher")
      :ok = SubagentTracker.track_spawn(tracker, "s2", "analyst")
      :ok = SubagentTracker.track_complete(tracker, "s1")

      summary = SubagentTracker.get_summary(tracker)
      assert summary.total == 2
      assert summary.completed == 1
      assert summary.running == 1
      assert summary.by_role["researcher"] == 1
      assert summary.by_role["analyst"] == 1
    end
  end

  describe "clear/1" do
    setup do
      {:ok, pid} = SubagentTracker.start_link(name: :test_clear_tracker)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{tracker: pid}
    end

    test "removes all tracked agents", %{tracker: tracker} do
      :ok = SubagentTracker.track_spawn(tracker, "c1", "researcher")
      :ok = SubagentTracker.track_spawn(tracker, "c2", "analyst")

      assert length(SubagentTracker.list_agents(tracker)) == 2
      :ok = SubagentTracker.clear(tracker)
      assert SubagentTracker.list_agents(tracker) == []
    end
  end
end
