defmodule ClaudeAgentSDK.Transport.StderrCallbackTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Transport.Port, as: PortTransport

  test "invokes Options.stderr callback for non-JSON stderr lines" do
    test_pid = self()

    script =
      create_test_script("""
      echo "ERR_LINE" 1>&2
      echo '{"type":"system","subtype":"init","session_id":"s"}'
      exec cat
      """)

    stderr_cb = fn line -> send(test_pid, {:stderr_line, line}) end
    options = %Options{stderr: stderr_cb}

    {:ok, transport} = PortTransport.start_link(command: script, args: [], options: options)
    PortTransport.subscribe(transport, self())

    assert_receive {:stderr_line, "ERR_LINE"}, 500
    assert_receive {:transport_message, json_line}, 500
    assert json_line =~ ~s("type":"system")

    PortTransport.close(transport)
  end

  defp create_test_script(body) do
    dir = Path.join(System.tmp_dir!(), "stderr_cb_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "stderr_callback_test.sh")

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
