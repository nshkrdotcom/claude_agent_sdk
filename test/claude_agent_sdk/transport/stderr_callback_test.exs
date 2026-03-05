defmodule ClaudeAgentSDK.Transport.StderrCallbackTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Transport.Erlexec, as: ErlexecTransport

  test "invokes Options.stderr callback for non-JSON stderr lines" do
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

    {:ok, transport} =
      ErlexecTransport.start_link(
        command: script,
        args: [],
        options: options,
        subscriber: self()
      )

    ErlexecTransport.subscribe(transport, self())

    assert_receive {:stderr_line, "ERR_LINE"}, 1_000
    assert_receive {:transport_message, json_line}, 1_000
    assert json_line =~ ~s("type":"system")

    ErlexecTransport.close(transport)
  end

  test "buffers split stderr chunks until a full line is available" do
    test_pid = self()

    script =
      create_test_script("""
      printf "ERR" 1>&2
      sleep 0.1
      printf "_LINE\\n" 1>&2
      echo '{"type":"system","subtype":"init","session_id":"s"}'
      while read -r line; do
        echo "$line"
      done
      """)

    stderr_cb = fn line -> send(test_pid, {:stderr_line, line}) end
    options = %Options{stderr: stderr_cb}

    {:ok, transport} =
      ErlexecTransport.start_link(
        command: script,
        args: [],
        options: options,
        subscriber: self()
      )

    ErlexecTransport.subscribe(transport, self())

    assert_receive {:stderr_line, "ERR_LINE"}, 1_000
    refute_receive {:stderr_line, "ERR"}, 100
    refute_receive {:stderr_line, "_LINE"}, 100

    ErlexecTransport.close(transport)
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
