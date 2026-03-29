defmodule ClaudeAgentSDK.Streaming.SessionCwdSemanticsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Streaming.Session
  alias ClaudeAgentSDK.TestSupport.FakeCLI
  alias CliSubprocessCore.TestSupport.FakeSSH

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

  test "lazy startup returns cwd validation failures before init completes" do
    cwd =
      Path.join(
        System.tmp_dir!(),
        "claude_agent_sdk_lazy_missing_cwd_#{System.unique_integer([:positive])}"
      )

    _ = File.rm_rf(cwd)
    Process.flag(:trap_exit, true)

    assert capture_log(fn ->
             assert {:error, {:subprocess_failed, {:cwd_not_found, ^cwd}}} =
                      Session.start_link(%Options{cwd: cwd}, startup_mode: :lazy)
           end) == ""
  end

  test "remote execution surfaces do not prevalidate the cwd against the local filesystem" do
    cwd =
      Path.join(
        System.tmp_dir!(),
        "claude_agent_sdk_remote_missing_cwd_#{System.unique_integer([:positive])}"
      )

    _ = File.rm_rf(cwd)
    fake_cli = FakeCLI.new!()
    fake_ssh = FakeSSH.new!()

    options =
      fake_cli
      |> FakeCLI.options(%Options{
        cwd: cwd,
        execution_surface:
          FakeCLI.static_ssh_surface(fake_cli, fake_ssh, destination: "claude-cwd.example")
      })

    try do
      assert {:ok, session} = Session.start_link(options)
      assert :ok = Session.close(session)
    after
      FakeSSH.cleanup(fake_ssh)
      FakeCLI.cleanup(fake_cli)
    end
  end
end
