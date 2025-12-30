defmodule ClaudeAgentSDK.BuildEnv do
  @moduledoc false

  @spec current() :: :dev | :test | :prod
  def current do
    :claude_agent_sdk
    |> Application.get_env(:build_env)
    |> normalize_env()
  end

  defp normalize_env(nil) do
    case System.get_env("MIX_ENV") do
      nil -> :prod
      env -> normalize_env(env)
    end
  end

  defp normalize_env(:dev), do: :dev
  defp normalize_env(:test), do: :test
  defp normalize_env(:prod), do: :prod
  defp normalize_env("dev"), do: :dev
  defp normalize_env("test"), do: :test
  defp normalize_env("prod"), do: :prod
  defp normalize_env(_), do: :prod
end
