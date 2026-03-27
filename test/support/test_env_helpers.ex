defmodule ClaudeAgentSDK.TestEnvHelpers do
  @moduledoc false

  @global_state_lock {:claude_agent_sdk_test, :global_state}
  @task_supervisor_lock {:claude_agent_sdk_test, :task_supervisor_env}

  @spec with_global_state((-> result)) :: result when result: var
  def with_global_state(fun) when is_function(fun, 0) do
    :global.trans(@global_state_lock, fun)
  end

  @spec acquire_global_state_lock() :: term()
  def acquire_global_state_lock do
    lock_id = {@global_state_lock, self()}
    true = :global.set_lock(lock_id)
    lock_id
  end

  @spec release_global_state_lock(term()) :: :ok
  def release_global_state_lock(lock_id) do
    :global.del_lock(lock_id)
    :ok
  end

  @spec with_task_supervisor_env(pid() | atom(), boolean(), (-> result)) :: result
        when result: var
  def with_task_supervisor_env(supervisor, strict?, fun) when is_function(fun, 0) do
    :global.trans(@task_supervisor_lock, fn ->
      previous_supervisor = Application.get_env(:claude_agent_sdk, :task_supervisor)
      previous_strict = Application.get_env(:claude_agent_sdk, :task_supervisor_strict)

      Application.put_env(:claude_agent_sdk, :task_supervisor, supervisor)
      Application.put_env(:claude_agent_sdk, :task_supervisor_strict, strict?)

      try do
        fun.()
      after
        restore_env(:task_supervisor, previous_supervisor)
        restore_env(:task_supervisor_strict, previous_strict)
      end
    end)
  end

  @spec with_system_env([{String.t(), String.t() | nil}], (-> result)) :: result
        when result: var
  def with_system_env(overrides, fun) when is_function(fun, 0) do
    with_global_state(fn ->
      previous =
        overrides
        |> Enum.map(fn {key, _value} -> {key, System.get_env(key)} end)
        |> Map.new()

      Enum.each(overrides, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      try do
        fun.()
      after
        restore_system_env(previous)
      end
    end)
  end

  @spec with_app_env(atom(), keyword(), (-> result)) :: result when result: var
  def with_app_env(app, overrides, fun) when is_atom(app) and is_function(fun, 0) do
    with_global_state(fn ->
      previous =
        overrides
        |> Enum.map(fn {key, _value} -> {key, Application.get_env(app, key)} end)
        |> Map.new()

      Enum.each(overrides, fn
        {key, nil} -> Application.delete_env(app, key)
        {key, value} -> Application.put_env(app, key, value)
      end)

      try do
        fun.()
      after
        restore_app_env(app, previous)
      end
    end)
  end

  @spec with_system_and_app_env(atom(), [{String.t(), String.t() | nil}], keyword(), (-> result)) ::
          result
        when result: var
  def with_system_and_app_env(app, system_overrides, app_overrides, fun)
      when is_atom(app) and is_function(fun, 0) do
    with_global_state(fn ->
      previous_system =
        system_overrides
        |> Enum.map(fn {key, _value} -> {key, System.get_env(key)} end)
        |> Map.new()

      previous_app =
        app_overrides
        |> Enum.map(fn {key, _value} -> {key, Application.get_env(app, key)} end)
        |> Map.new()

      Enum.each(system_overrides, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      Enum.each(app_overrides, fn
        {key, nil} -> Application.delete_env(app, key)
        {key, value} -> Application.put_env(app, key, value)
      end)

      try do
        fun.()
      after
        restore_system_env(previous_system)
        restore_app_env(app, previous_app)
      end
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:claude_agent_sdk, key)
  defp restore_env(key, value), do: Application.put_env(:claude_agent_sdk, key, value)

  defp restore_system_env(previous) do
    Enum.each(previous, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)
  end

  defp restore_app_env(app, previous) do
    Enum.each(previous, fn
      {key, nil} -> Application.delete_env(app, key)
      {key, value} -> Application.put_env(app, key, value)
    end)
  end
end
