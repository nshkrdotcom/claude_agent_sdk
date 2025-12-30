defmodule ClaudeAgentSDK.Streaming.SessionStderrCallbackTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Streaming}
  alias ClaudeAgentSDK.Streaming.Session

  test "invokes Options.stderr callback for streaming session stderr" do
    Process.flag(:trap_exit, true)
    test_pid = self()

    script =
      create_test_script("""
      echo "ERR_LINE" 1>&2
      echo '{"type":"message_stop"}'
      """)

    options = %Options{
      executable: script,
      stderr: fn line -> send(test_pid, {:stderr_line, line}) end
    }

    {:ok, session} = Session.start_link(options)

    assert_receive {:stderr_line, "ERR_LINE"}, 1_000

    # The session may have already terminated after emitting the message.
    # Wrap in try/catch to handle race between alive? check and close call.
    try do
      if Process.alive?(session), do: Streaming.close_session(session)
    catch
      :exit, _ -> :ok
    end
  end

  defp create_test_script(body) do
    dir =
      Path.join(System.tmp_dir!(), "streaming_stderr_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    path = Path.join(dir, "streaming_stderr_test.sh")

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
