defmodule ClaudeAgentSDK.Transport.EnvParityTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Options, Process}
  alias ClaudeAgentSDK.Transport.Port, as: PortTransport

  test "Port transport sets PWD when cwd is set" do
    tmp_dir = Path.join(System.tmp_dir!(), "pwd_env_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    options = %Options{cwd: tmp_dir}
    opts = PortTransport.__build_port_options__([], options)
    env = Keyword.fetch!(opts, :env)

    assert Enum.any?(env, fn {key, value} -> key == "PWD" and value == tmp_dir end)
  end

  test "Process env vars include PWD when cwd is set" do
    tmp_dir = Path.join(System.tmp_dir!(), "pwd_env_proc_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    options = %Options{cwd: tmp_dir}
    env = Process.__env_vars__(options)

    assert env["PWD"] == tmp_dir
  end
end
