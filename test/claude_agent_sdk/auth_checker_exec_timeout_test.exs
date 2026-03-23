defmodule ClaudeAgentSDK.AuthCheckerExecTimeoutTest do
  @moduledoc """
  Regression test for shared command-lane timeout handling.

  The auth checker now routes shell commands through
  `CliSubprocessCore.Command.run/2` instead of using the legacy low-level
  launcher directly.

  This test calls a test-only wrapper around `run_command_with_timeout/2`
  to ensure the shared timeout path still succeeds.
  """
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.AuthChecker

  @tag :live_cli
  test "AuthChecker uses the shared command timeout lane" do
    result = AuthChecker.run_command_with_timeout_for_test("echo hello", 5_000)

    assert match?({:ok, output} when is_binary(output), result)
    assert {:ok, output} = result
    assert String.contains?(output, "hello")
  end
end
