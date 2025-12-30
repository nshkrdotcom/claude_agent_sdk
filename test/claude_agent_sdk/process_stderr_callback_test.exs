defmodule ClaudeAgentSDK.ProcessStderrCallbackTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{Options, Process}

  test "invokes Options.stderr callback for stderr output" do
    test_pid = self()

    script =
      create_test_script("""
      echo "ERR_LINE" 1>&2
      echo '{"type":"system","subtype":"init","session_id":"s"}'
      """)

    options = %Options{
      executable: script,
      stderr: fn line -> send(test_pid, {:stderr_line, line}) end
    }

    messages = Process.stream(["--print"], options, nil) |> Enum.to_list()

    assert_receive {:stderr_line, "ERR_LINE"}, 1_000
    assert Enum.any?(messages, &(&1.type == :system))
  end

  defp create_test_script(body) do
    dir = Path.join(System.tmp_dir!(), "process_stderr_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "process_stderr_test.sh")

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
