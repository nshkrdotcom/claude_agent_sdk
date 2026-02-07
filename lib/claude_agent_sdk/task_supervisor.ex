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
  If the supervisor is not started, the SDK falls back to `Task.start/1`
  unless strict mode is enabled.

  ## Configuration

  You can customize the supervisor name if needed:

      {ClaudeAgentSDK.TaskSupervisor, name: MyApp.ClaudeTaskSupervisor}

  Then configure the SDK to use it:

      config :claude_agent_sdk, task_supervisor: MyApp.ClaudeTaskSupervisor

  If a custom supervisor is configured but not running, the SDK logs a warning.
  You can enforce stricter behavior in dev/test:

      config :claude_agent_sdk, task_supervisor_strict: true

  ## Direct Usage

      {:ok, pid} = ClaudeAgentSDK.TaskSupervisor.start_child(fn ->
        # Your async work here
      end)

  ## OTP Notes

  Tasks are started with `restart: :temporary` by default (no automatic restarts).
  """

  alias ClaudeAgentSDK.Log, as: Logger

  @missing_supervisor_warned_key {__MODULE__, :missing_task_supervisor}

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

  - `{:ok, pid}` - Task started successfully
  - `{:error, {:task_supervisor_unavailable, supervisor}}` - Strict mode blocked fallback
  """
  @spec start_child((-> any()), keyword()) ::
          {:ok, pid()} | {:error, {:task_supervisor_unavailable, pid() | atom()}}
  def start_child(fun, opts \\ []) when is_function(fun, 0) do
    {supervisor, explicit?} = configured_supervisor()
    do_start_child(fun, opts, supervisor, explicit?)
  end

  @doc """
  Checks if the task supervisor is available and running.
  """
  @spec available?() :: boolean()
  def available? do
    {supervisor, _explicit?} = configured_supervisor()
    supervisor_available?(supervisor)
  end

  # Private helpers

  defp configured_supervisor do
    case Application.get_env(:claude_agent_sdk, :task_supervisor) do
      nil -> {__MODULE__, false}
      value -> {value, true}
    end
  end

  defp do_start_child(fun, opts, supervisor, explicit?) do
    case Task.Supervisor.start_child(
           supervisor,
           fun,
           Keyword.put_new(opts, :restart, :temporary)
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:noproc, _}} ->
        fallback_start(fun, true, supervisor, explicit?)

      {:error, :noproc} ->
        fallback_start(fun, true, supervisor, explicit?)

      {:error, _reason} ->
        fallback_start(fun, false, supervisor, explicit?)
    end
  catch
    :exit, {:noproc, _} ->
      fallback_start(fun, true, supervisor, explicit?)

    :exit, :noproc ->
      fallback_start(fun, true, supervisor, explicit?)

    :exit, _reason ->
      fallback_start(fun, false, supervisor, explicit?)
  end

  defp fallback_start(fun, missing?, supervisor, explicit?) do
    strict? = strict_task_supervisor?()

    if missing? do
      handle_missing_supervisor(supervisor, explicit?, strict?)
    end

    if strict? do
      {:error, {:task_supervisor_unavailable, supervisor}}
    else
      Task.start(fun)
    end
  end

  defp handle_missing_supervisor(supervisor, true, strict?) when supervisor != __MODULE__ do
    action =
      if strict?,
        do: "strict mode enabled; refusing fallback",
        else: "falling back to Task.start/1"

    message =
      "Task supervisor configured but not running: #{inspect(supervisor)} " <>
        "(#{action})"

    warn_missing_supervisor(message, supervisor)
  end

  # Keep backward compatibility: default missing SDK supervisor should still
  # transparently fall back without noisy logs unless strict mode is enabled.
  defp handle_missing_supervisor(_supervisor, false, false), do: :ok

  defp handle_missing_supervisor(supervisor, _explicit?, true) do
    warn_missing_supervisor(
      "Task supervisor not running: #{inspect(supervisor)} " <>
        "(strict mode enabled; refusing fallback)",
      supervisor
    )
  end

  defp warn_missing_supervisor(message, supervisor) do
    key = {@missing_supervisor_warned_key, supervisor}

    unless :persistent_term.get(key, false) do
      :persistent_term.put(key, true)
      Logger.warning(message)
    end
  end

  defp strict_task_supervisor? do
    Application.get_env(:claude_agent_sdk, :task_supervisor_strict, false)
  end

  defp supervisor_available?(pid) when is_pid(pid), do: process_running?(pid)

  defp supervisor_available?(name) do
    is_pid(Process.whereis(name))
  end

  defp process_running?(pid) when is_pid(pid) do
    Process.info(pid, :status) != nil
  end
end
