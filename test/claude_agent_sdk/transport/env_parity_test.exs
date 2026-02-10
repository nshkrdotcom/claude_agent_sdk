defmodule ClaudeAgentSDK.Transport.EnvParityTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Options, Process}

  test "Process env vars include PWD when cwd is set" do
    tmp_dir = Path.join(System.tmp_dir!(), "pwd_env_proc_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    options = %Options{cwd: tmp_dir}
    env = Process.__env_vars__(options)

    assert env["PWD"] == tmp_dir
  end
end
