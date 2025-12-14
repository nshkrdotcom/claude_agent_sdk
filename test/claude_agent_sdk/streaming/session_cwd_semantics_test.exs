defmodule ClaudeAgentSDK.Streaming.SessionCwdSemanticsTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Streaming.Session

  test "start_link errors when cwd does not exist" do
    cwd =
      Path.join(
        System.tmp_dir!(),
        "claude_agent_sdk_missing_cwd_#{System.unique_integer([:positive])}"
      )

    _ = File.rm_rf(cwd)

    Process.flag(:trap_exit, true)

    assert {:error, {:subprocess_failed, {:cwd_not_found, ^cwd}}} =
             Session.start_link(%Options{cwd: cwd})
  end
end
