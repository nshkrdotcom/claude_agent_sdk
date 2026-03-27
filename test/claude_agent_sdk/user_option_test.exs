defmodule ClaudeAgentSDK.UserOptionTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Process}
  alias ClaudeAgentSDK.Runtime.CLI, as: RuntimeCLI
  alias CliSubprocessCore.Command

  test "process env vars include user overrides" do
    options = %Options{user: "runner"}

    env_map = Process.__env_vars__(options)

    assert env_map["USER"] == "runner"
    assert env_map["LOGNAME"] == "runner"
  end

  test "runtime invocation propagates user onto the core command" do
    cat = System.find_executable("cat") || "cat"

    assert {:ok, %Command{} = command} =
             RuntimeCLI.build_invocation(
               options: %Options{
                 executable: cat,
                 user: "runner",
                 model: "sonnet",
                 provider_backend: :anthropic
               }
             )

    assert command.command == cat
    assert command.user == "runner"
  end
end
