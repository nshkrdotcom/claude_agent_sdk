defmodule ResearchAgent.CoordinatorTest do
  use ExUnit.Case, async: false

  alias ResearchAgent.Coordinator

  @output_dir System.tmp_dir!()

  describe "start_link/1" do
    test "starts the coordinator supervisor" do
      {:ok, pid} = Coordinator.start_link(output_dir: @output_dir)
      assert Process.alive?(pid)
      Supervisor.stop(pid)
    end

    test "initializes subagent tracker" do
      {:ok, pid} = Coordinator.start_link(output_dir: @output_dir)

      # Tracker should be running
      tracker = Coordinator.get_tracker(pid)
      assert is_pid(tracker)

      Supervisor.stop(pid)
    end

    test "initializes transcript logger" do
      {:ok, pid} = Coordinator.start_link(output_dir: @output_dir)

      # Logger should be running
      logger = Coordinator.get_logger(pid)
      assert is_pid(logger)

      Supervisor.stop(pid)
    end
  end

  describe "get_hooks/1" do
    test "returns hooks configuration for Claude SDK" do
      {:ok, pid} = Coordinator.start_link(output_dir: @output_dir)

      hooks = Coordinator.get_hooks(pid)
      assert is_map(hooks)
      assert Map.has_key?(hooks, :pre_tool_use)
      assert Map.has_key?(hooks, :post_tool_use)

      Supervisor.stop(pid)
    end
  end

  describe "get_status/1" do
    test "returns current coordinator status" do
      {:ok, pid} = Coordinator.start_link(output_dir: @output_dir)

      status = Coordinator.get_status(pid)
      assert status.tracker_status == :running
      assert status.logger_status == :running
      assert status.subagent_count == 0

      Supervisor.stop(pid)
    end
  end
end
