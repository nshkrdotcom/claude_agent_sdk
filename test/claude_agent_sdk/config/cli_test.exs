defmodule ClaudeAgentSDK.Config.CLITest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Config.CLI

  setup do
    original = Application.get_env(:claude_agent_sdk, CLI)
    on_exit(fn -> restore(original) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:claude_agent_sdk, CLI)
  defp restore(val), do: Application.put_env(:claude_agent_sdk, CLI, val)

  describe "defaults" do
    test "minimum_version" do
      assert CLI.minimum_version() == "2.0.0"
    end

    test "recommended_version" do
      assert CLI.recommended_version() == "2.0.75"
    end

    test "executable_candidates" do
      assert CLI.executable_candidates() == ["claude-code", "claude"]
    end

    test "install_command" do
      assert CLI.install_command() =~ "npm install"
    end
  end

  describe "streaming args" do
    test "streaming_output_args returns output+verbose flags" do
      args = CLI.streaming_output_args()
      assert "--output-format" in args
      assert "stream-json" in args
      assert "--verbose" in args
      refute "--input-format" in args
    end

    test "streaming_bidirectional_args includes input-format" do
      args = CLI.streaming_bidirectional_args()
      assert "--output-format" in args
      assert "--input-format" in args
      assert "stream-json" in args
      assert "--verbose" in args
    end
  end

  describe "runtime override" do
    test "overrides minimum_version" do
      Application.put_env(:claude_agent_sdk, CLI, minimum_version: "3.0.0")
      assert CLI.minimum_version() == "3.0.0"
    end
  end
end
