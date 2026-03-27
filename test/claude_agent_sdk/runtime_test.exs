defmodule ClaudeAgentSDK.RuntimeTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Runtime}
  alias ClaudeAgentSDK.TestEnvHelpers

  test "use_mock?/0 respects LIVE_MODE override" do
    TestEnvHelpers.with_system_and_app_env(
      :claude_agent_sdk,
      [{"LIVE_MODE", "true"}, {"LIVE_TESTS", nil}],
      [use_mock: true],
      fn ->
        refute Runtime.use_mock?()
      end
    )
  end

  test "force_real?/1 returns true when custom executable is provided" do
    assert Runtime.force_real?(%Options{executable: "/usr/bin/claude"})
    assert Runtime.force_real?(%Options{path_to_claude_code_executable: "/usr/bin/claude"})
    refute Runtime.force_real?(%Options{})
  end
end
