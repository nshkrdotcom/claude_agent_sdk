defmodule ClaudeAgentSDK.Transport.ErlexecTransportTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Transport.Erlexec, as: ErlexecTransport

  test "streams stdout lines to subscribers and routes stderr to callback" do
    test_pid = self()

    script =
      create_test_script("""
      echo "ERR_LINE" 1>&2
      echo '{"type":"system","subtype":"init","session_id":"s"}'
      while read -r line; do
        echo "$line"
      done
      """)

    stderr_cb = fn line -> send(test_pid, {:stderr_line, line}) end

    options = %Options{stderr: stderr_cb}

    {:ok, transport} = ErlexecTransport.start_link(command: script, args: [], options: options)
    assert :ok = ErlexecTransport.subscribe(transport, self())

    assert_receive {:stderr_line, "ERR_LINE"}, 1_000
    assert_receive {:transport_message, init_line}, 1_000
    assert init_line =~ ~s("type":"system")

    assert :ok = ErlexecTransport.send(transport, "PING\n")
    assert_receive {:transport_message, "PING"}, 1_000

    ErlexecTransport.close(transport)
  end

  test "exec opts include :user when Options.user is set" do
    exec_opts = ErlexecTransport.__exec_opts__(%Options{user: "runner"})
    assert {:user, ~c"runner"} in exec_opts
  end

  defp create_test_script(body) do
    dir = Path.join(System.tmp_dir!(), "erlexec_transport_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "erlexec_transport_test.sh")

    File.write!(path, """
    #!/usr/bin/env bash
    set -euo pipefail
    #{body}
    """)

    File.chmod!(path, 0o755)

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)

    path
  end
end
