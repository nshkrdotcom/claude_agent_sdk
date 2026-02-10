defmodule ClaudeAgentSDK.ProcessEnvTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Options, Process}
  alias ClaudeAgentSDK.Streaming.Session

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

  test "shell escaping preserves empty string arguments" do
    assert Process.__shell_escape__("") == "\"\""
  end

  test "shell escaping includes redirection operators" do
    assert Process.__shell_escape__("a>b") == "\"a>b\""
    assert Process.__shell_escape__("a<b") == "\"a<b\""
  end

  test "process and streaming session use the same shell escaping rules" do
    for arg <- ["plain", "needs space", "quote\"test", "bang!", "a>b", "a<b"] do
      assert Process.__shell_escape__(arg) == Session.__shell_escape__(arg)
    end
  end
end
