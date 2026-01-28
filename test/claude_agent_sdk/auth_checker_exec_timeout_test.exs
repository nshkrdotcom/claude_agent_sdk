defmodule ClaudeAgentSDK.AuthCheckerExecTimeoutTest do
  @moduledoc """
  Regression test for erlexec timeout handling.

  Bug: `run_command_with_timeout/2` passed `{:timeout, ms}` in the options
  list to `:exec.run/2`, which erlexec rejects as `{:invalid_option, _}`.
  Fix: use `:exec.run/3` and pass the timeout as the third argument.

  This test calls a test-only wrapper around `run_command_with_timeout/2`
  to ensure the corrected `:exec.run/3` signature succeeds.
  """
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.AuthChecker

  @tag :live_cli
  test "AuthChecker uses the valid erlexec timeout signature" do
    {:ok, _} = Application.ensure_all_started(:erlexec)

    result = AuthChecker.run_command_with_timeout_for_test("echo hello", 5_000)

    assert match?({:ok, output} when is_binary(output), result)
    assert {:ok, output} = result
    assert String.contains?(output, "hello")
  end
end
