defmodule ClaudeAgentSDK.UserOptionTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Process}
  alias ClaudeAgentSDK.Streaming.Session
  alias ClaudeAgentSDK.Transport.Port

  defp env_list_to_map(nil), do: %{}

  defp env_list_to_map(list) do
    list
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  test "process exec options include user for erlexec runs" do
    options = %Options{user: "runner"}

    exec_opts = Process.__exec_options__(options)

    assert {:user, ~c"runner"} in exec_opts

    env_map =
      exec_opts
      |> Enum.find_value([], fn
        {:env, env_list} -> env_list
        _ -> nil
      end)
      |> env_list_to_map()

    assert env_map["USER"] == "runner"
    assert env_map["LOGNAME"] == "runner"
  end

  test "transport port env includes user overrides" do
    options = %Options{user: "runner"}

    opts =
      Port.__build_port_options__([{:env, [{"EXISTING", "1"}]}], options)

    env_map =
      opts
      |> Keyword.get(:env)
      |> env_list_to_map()

    assert env_map["EXISTING"] == "1"
    assert env_map["USER"] == "runner"
    assert env_map["LOGNAME"] == "runner"
  end

  test "streaming session exec opts propagate user" do
    options = %Options{user: "runner"}

    exec_opts = Session.__exec_opts__(options)

    assert {:user, ~c"runner"} in exec_opts

    env_map =
      exec_opts
      |> Enum.find_value([], fn
        {:env, env_list} -> env_list
        _ -> nil
      end)
      |> env_list_to_map()

    assert env_map["USER"] == "runner"
  end
end
