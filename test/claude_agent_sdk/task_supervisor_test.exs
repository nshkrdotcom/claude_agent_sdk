defmodule ClaudeAgentSDK.TaskSupervisorTest do
  @moduledoc """
  Tests for ClaudeAgentSDK.TaskSupervisor module.
  """

  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.TaskSupervisor

  # Ensure we clean up any running supervisor before and after tests
  setup do
    stop_supervisor_if_running()
    on_exit(fn -> stop_supervisor_if_running() end)
    :ok
  end

  defp stop_supervisor_if_running do
    case Process.whereis(ClaudeAgentSDK.TaskSupervisor) do
      nil -> :ok
      pid -> Supervisor.stop(pid, :normal, 1000)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  describe "start_link/1" do
    test "starts supervisor with default name" do
      {:ok, pid} = TaskSupervisor.start_link()
      assert Process.alive?(pid)
    end

    test "starts supervisor with custom name" do
      {:ok, pid} = TaskSupervisor.start_link(name: :test_supervisor_custom)
      assert Process.alive?(pid)
      assert Process.whereis(:test_supervisor_custom) == pid
      Supervisor.stop(pid)
    end
  end

  describe "start_child/2" do
    test "starts a supervised child task" do
      {:ok, _sup} = TaskSupervisor.start_link()
      parent = self()

      {:ok, pid} =
        TaskSupervisor.start_child(fn ->
          send(parent, {:child_running, self()})
        end)

      assert is_pid(pid)
      assert_receive {:child_running, ^pid}, 1000
    end

    test "child task completes successfully" do
      {:ok, _sup} = TaskSupervisor.start_link()
      parent = self()

      {:ok, _pid} =
        TaskSupervisor.start_child(fn ->
          send(parent, :done)
        end)

      assert_receive :done, 1000
    end

    test "child task crashes are detectable via monitor" do
      {:ok, _sup} = TaskSupervisor.start_link()
      Process.flag(:trap_exit, true)

      {:ok, pid} =
        TaskSupervisor.start_child(fn ->
          raise "boom"
        end)

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
    end

    test "starts a supervised child task when configured supervisor name is custom" do
      Application.put_env(:claude_agent_sdk, :task_supervisor, :custom_task_supervisor)
      on_exit(fn -> Application.delete_env(:claude_agent_sdk, :task_supervisor) end)

      {:ok, sup} = TaskSupervisor.start_link(name: :custom_task_supervisor)
      parent = self()

      {:ok, pid} =
        TaskSupervisor.start_child(fn ->
          send(parent, {:custom_child_running, self()})
          Process.sleep(200)
        end)

      assert is_pid(pid)
      assert_receive {:custom_child_running, ^pid}, 1000
      assert %{active: active} = DynamicSupervisor.count_children(:custom_task_supervisor)
      assert active >= 1
      Supervisor.stop(sup)
    end
  end

  describe "available?/0" do
    test "returns true when supervisor is running" do
      {:ok, _sup} = TaskSupervisor.start_link()
      assert TaskSupervisor.available?()
    end

    test "returns true when supervisor is running with configured custom name" do
      Application.put_env(:claude_agent_sdk, :task_supervisor, :custom_task_supervisor)
      on_exit(fn -> Application.delete_env(:claude_agent_sdk, :task_supervisor) end)

      {:ok, sup} = TaskSupervisor.start_link(name: :custom_task_supervisor)

      assert TaskSupervisor.available?()
      Supervisor.stop(sup)
    end

    test "returns false when supervisor is not running" do
      refute TaskSupervisor.available?()
    end
  end

  describe "fallback behavior" do
    test "starts unlinked task when supervisor is not available" do
      # Supervisor is not running (cleaned up in setup)
      parent = self()

      {:ok, pid} =
        TaskSupervisor.start_child(fn ->
          send(parent, {:fallback_running, self()})
        end)

      assert is_pid(pid)
      assert_receive {:fallback_running, ^pid}, 1000
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = TaskSupervisor.child_spec([])

      assert spec.id == ClaudeAgentSDK.TaskSupervisor
      assert spec.type == :supervisor
      assert {ClaudeAgentSDK.TaskSupervisor, :start_link, [[]]} == spec.start
    end

    test "respects custom name in child spec" do
      spec = TaskSupervisor.child_spec(name: :custom_supervisor)

      assert spec.id == :custom_supervisor
    end
  end
end
