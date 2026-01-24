defmodule ClaudeAgentSDK.TaskSupervisor do
  @moduledoc """
  Optional Task.Supervisor for supervised callback execution.

  This module provides a supervised environment for async callback execution
  in the Claude Agent SDK. Using supervised tasks ensures that:

  - Callback process crashes are detected and handled gracefully
  - No orphaned processes accumulate over time
  - Resource cleanup happens automatically on failure

  ## Usage

  Add to your application's supervision tree:

      children = [
        ClaudeAgentSDK.TaskSupervisor,
        # ... other children
      ]

  The SDK will automatically detect and use this supervisor when available.
  If the supervisor is not started, the SDK falls back to unlinked tasks
  with manual crash handling.

  ## Configuration

  You can customize the supervisor name if needed:

      {ClaudeAgentSDK.TaskSupervisor, name: MyApp.ClaudeTaskSupervisor}

  Then configure the SDK to use it:

      config :claude_agent_sdk, task_supervisor: MyApp.ClaudeTaskSupervisor

  ## Direct Usage

      {:ok, pid} = ClaudeAgentSDK.TaskSupervisor.start_child(fn ->
        # Your async work here
      end)

  ## OTP Notes

  Tasks are started with `restart: :temporary` by default (no automatic restarts).
  """

  @doc """
  Starts the task supervisor.

  ## Options

  - `:name` - The supervisor name (default: `ClaudeAgentSDK.TaskSupervisor`)
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    Task.Supervisor.start_link(opts)
  end

  @doc """
  Returns the child specification for supervision tree inclusion.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts a supervised child task.

  The caller should monitor the returned pid if it needs crash signals.

  ## Parameters

  - `fun` - Zero-arity function to execute
  - `opts` - Options passed to Task.Supervisor.start_child/3

  ## Returns

  - `{:ok, pid}` - Task started successfully (falls back to `spawn/1` if needed)
  """
  @spec start_child((-> any()), keyword()) :: {:ok, pid()}
  def start_child(fun, opts \\ []) when is_function(fun, 0) do
    supervisor = configured_supervisor()

    if supervisor_available?(supervisor) do
      case Task.Supervisor.start_child(
             supervisor,
             fun,
             Keyword.put_new(opts, :restart, :temporary)
           ) do
        {:ok, pid} -> {:ok, pid}
        {:error, _reason} -> {:ok, spawn(fun)}
      end
    else
      {:ok, spawn(fun)}
    end
  rescue
    _ -> {:ok, spawn(fun)}
  end

  @doc """
  Checks if the task supervisor is available and running.
  """
  @spec available?() :: boolean()
  def available? do
    supervisor_available?(configured_supervisor())
  end

  # Private helpers

  defp configured_supervisor do
    Application.get_env(:claude_agent_sdk, :task_supervisor, __MODULE__)
  end

  defp supervisor_available?(pid) when is_pid(pid), do: Process.alive?(pid)

  defp supervisor_available?(name) do
    case Process.whereis(name) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
    end
  end
end
