defmodule ClaudeAgentSDK.TaskSupervisorTest do
  @moduledoc """
  Tests for ClaudeAgentSDK.TaskSupervisor module.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

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

  defp clear_missing_supervisor_warning(supervisor) do
    key = {{ClaudeAgentSDK.TaskSupervisor, :missing_task_supervisor}, supervisor}
    :persistent_term.erase(key)
    :ok
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
    test "falls back to Task.start/1 when supervisor is not available" do
      # Supervisor is not running (cleaned up in setup)
      parent = self()

      {:ok, pid} =
        TaskSupervisor.start_child(fn ->
          send(parent, {:fallback_running, self()})

          receive do
            :stop -> :ok
          end
        end)

      assert is_pid(pid)
      assert_receive {:fallback_running, ^pid}, 1000

      assert {:initial_call, {Task.Supervised, _func, _arity}} =
               Process.info(pid, :initial_call)

      send(pid, :stop)
    end

    test "does not log warning when default supervisor is missing in non-strict mode" do
      Application.delete_env(:claude_agent_sdk, :task_supervisor)
      Application.delete_env(:claude_agent_sdk, :task_supervisor_strict)

      log =
        capture_log(fn ->
          assert {:ok, pid} = TaskSupervisor.start_child(fn -> :ok end)
          assert is_pid(pid)
        end)

      refute log =~ "Task supervisor not running"
    end

    test "logs warning when explicitly configured supervisor is missing" do
      Application.put_env(:claude_agent_sdk, :task_supervisor, :missing_custom_supervisor)
      Application.delete_env(:claude_agent_sdk, :task_supervisor_strict)
      clear_missing_supervisor_warning(:missing_custom_supervisor)

      on_exit(fn ->
        Application.delete_env(:claude_agent_sdk, :task_supervisor)
      end)

      log =
        capture_log(fn ->
          assert {:ok, pid} = TaskSupervisor.start_child(fn -> :ok end)
          assert is_pid(pid)
        end)

      assert log =~ "Task supervisor configured but not running: :missing_custom_supervisor"
      assert log =~ "falling back to Task.start/1"
    end

    test "raises in strict mode when explicit configured supervisor is missing" do
      Application.put_env(:claude_agent_sdk, :task_supervisor, :missing_custom_supervisor)
      Application.put_env(:claude_agent_sdk, :task_supervisor_strict, true)
      clear_missing_supervisor_warning(:missing_custom_supervisor)

      on_exit(fn ->
        Application.delete_env(:claude_agent_sdk, :task_supervisor)
        Application.delete_env(:claude_agent_sdk, :task_supervisor_strict)
      end)

      log =
        capture_log(fn ->
          assert {:error, {:task_supervisor_unavailable, :missing_custom_supervisor}} =
                   TaskSupervisor.start_child(fn -> :ok end)
        end)

      assert log =~ "strict mode enabled; refusing fallback"
    end

    test "returns error in strict mode when default supervisor is missing" do
      Application.put_env(:claude_agent_sdk, :task_supervisor_strict, true)
      clear_missing_supervisor_warning(ClaudeAgentSDK.TaskSupervisor)
      on_exit(fn -> Application.delete_env(:claude_agent_sdk, :task_supervisor_strict) end)

      log =
        capture_log(fn ->
          assert {:error, {:task_supervisor_unavailable, ClaudeAgentSDK.TaskSupervisor}} =
                   TaskSupervisor.start_child(fn -> :ok end)
        end)

      assert log =~ "Task supervisor not running: ClaudeAgentSDK.TaskSupervisor"
      assert log =~ "strict mode enabled; refusing fallback"
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
