defmodule ClaudeAgentSDK.Runtime do
  @moduledoc false

  alias ClaudeAgentSDK.{Config, Options}
  alias ClaudeAgentSDK.Config.Env

  @spec use_mock?() :: boolean()
  def use_mock? do
    case {System.get_env(Env.live_mode()), System.get_env(Env.live_tests())} do
      {"true", _} -> false
      {_, "true"} -> false
      _ -> Config.use_mock?()
    end
  end

  @spec force_real?(Options.t()) :: boolean()
  def force_real?(%Options{executable: executable, path_to_claude_code_executable: path}) do
    is_binary(executable) or is_binary(path)
  end

  @spec ensure_erlexec_started() :: :ok | {:error, {:erlexec_not_started, term()}}
  def ensure_erlexec_started do
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:erlexec_not_started, reason}}
    end
  end

  @spec ensure_erlexec_started!() :: :ok
  def ensure_erlexec_started! do
    case ensure_erlexec_started() do
      :ok ->
        :ok

      {:error, {:erlexec_not_started, reason}} ->
        raise "Failed to start erlexec application: #{inspect(reason)}"
    end
  end
end
