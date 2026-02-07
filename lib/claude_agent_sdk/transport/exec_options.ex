defmodule ClaudeAgentSDK.Transport.ExecOptions do
  @moduledoc false

  alias ClaudeAgentSDK.{Options, Process}

  @spec erlexec(Options.t(), [atom()]) :: keyword()
  def erlexec(%Options{} = options, base \\ [:stdin, :stdout, :stderr, :monitor]) do
    env =
      options
      |> Process.__env_vars__()
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    base
    |> maybe_put_env_option(env)
    |> maybe_put_user_option(options.user)
    |> maybe_put_cd_option(options.cwd)
  end

  defp maybe_put_env_option(opts, []), do: opts
  defp maybe_put_env_option(opts, env) when is_list(env), do: [{:env, env} | opts]

  defp maybe_put_user_option(opts, nil), do: opts

  defp maybe_put_user_option(opts, user) when is_binary(user) do
    [{:user, String.to_charlist(user)} | opts]
  end

  defp maybe_put_cd_option(opts, nil), do: opts
  defp maybe_put_cd_option(opts, cwd) when is_binary(cwd), do: [{:cd, cwd} | opts]
end
