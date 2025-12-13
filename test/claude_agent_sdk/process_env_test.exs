defmodule ClaudeAgentSDK.ProcessEnvTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Options, Process}
  alias ClaudeAgentSDK.Transport.Port, as: PortTransport

  test "env builder merges option overrides and user" do
    options = %Options{
      env: %{"PORT_ENV_TEST" => "from_process", :PATH => "/custom"},
      user: "runner"
    }

    env_map =
      Process.__env_vars__(options)
      |> Map.new()

    assert env_map["PORT_ENV_TEST"] == "from_process"
    assert env_map["PATH"] == "/custom"
    assert env_map["USER"] == "runner"
    assert env_map["LOGNAME"] == "runner"
    assert env_map["CLAUDE_CODE_ENTRYPOINT"] == "sdk-elixir"
    assert env_map["CLAUDE_AGENT_SDK_VERSION"]
  end

  test "env builder sets file checkpointing env var when enabled" do
    options = %Options{enable_file_checkpointing: true}

    env_map =
      options
      |> Process.__env_vars__()
      |> Map.new()

    assert env_map["CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"] == "true"
  end

  test "port transport env builder sets file checkpointing env var when enabled" do
    env_var = "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"
    original_value = System.get_env(env_var)
    System.put_env(env_var, "false")

    on_exit(fn ->
      if is_binary(original_value) do
        System.put_env(env_var, original_value)
      else
        System.delete_env(env_var)
      end
    end)

    options = %Options{enable_file_checkpointing: true}
    opts = PortTransport.__build_port_options__([], options)

    env_map =
      opts
      |> Keyword.fetch!(:env)
      |> Map.new()

    assert env_map[env_var] == "true"
  end

  test "shell escaping preserves empty string arguments" do
    assert Process.__shell_escape__("") == "\"\""
  end
end
