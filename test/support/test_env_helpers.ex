defmodule ClaudeAgentSDK.TestEnvHelpers do
  @moduledoc false

  @task_supervisor_lock {:claude_agent_sdk_test, :task_supervisor_env}

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

  defp restore_env(key, nil), do: Application.delete_env(:claude_agent_sdk, key)
  defp restore_env(key, value), do: Application.put_env(:claude_agent_sdk, key, value)
end
