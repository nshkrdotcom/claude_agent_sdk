defmodule ClaudeAgentSDK.RuntimeTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Runtime}

  test "use_mock?/0 respects LIVE_MODE override" do
    original_live_mode = System.get_env("LIVE_MODE")
    original_live_tests = System.get_env("LIVE_TESTS")
    original_use_mock = Application.get_env(:claude_agent_sdk, :use_mock)

    System.put_env("LIVE_MODE", "true")
    System.delete_env("LIVE_TESTS")
    Application.put_env(:claude_agent_sdk, :use_mock, true)

    on_exit(fn ->
      restore_env("LIVE_MODE", original_live_mode)
      restore_env("LIVE_TESTS", original_live_tests)
      restore_app_env(:use_mock, original_use_mock)
    end)

    refute Runtime.use_mock?()
  end

  test "force_real?/1 returns true when custom executable is provided" do
    assert Runtime.force_real?(%Options{executable: "/usr/bin/claude"})
    assert Runtime.force_real?(%Options{path_to_claude_code_executable: "/usr/bin/claude"})
    refute Runtime.force_real?(%Options{})
  end

  defp restore_env(var, nil), do: System.delete_env(var)
  defp restore_env(var, value), do: System.put_env(var, value)

  defp restore_app_env(key, nil), do: Application.delete_env(:claude_agent_sdk, key)
  defp restore_app_env(key, value), do: Application.put_env(:claude_agent_sdk, key, value)
end
