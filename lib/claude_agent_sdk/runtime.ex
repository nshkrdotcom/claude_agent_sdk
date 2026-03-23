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
end
