defmodule ClaudeAgentSDK.QueryCLIStreamCleanupTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Message, Options}
  alias ClaudeAgentSDK.Query.CLIStream
  alias ClaudeAgentSDK.Transport

  test "cleanup force-stops stubborn subprocesses that ignore TERM/INT" do
    dir = tmp_dir!("cli_stream_stubborn_cleanup")

    try do
      pid_file = Path.join(dir, "stub_pid.txt")
      script_path = write_stubborn_stream_stub!(dir)

      options = %Options{
        env: %{
          "CLAUDE_SDK_TEST_PID_FILE" => pid_file
        }
      }

      stream =
        CLIStream.stream_args(
          [],
          options,
          {Transport, [command: script_path, args: []]},
          nil
        )

      assert [%Message{type: :assistant}] = Enum.take(stream, 1)

      assert :ok == wait_until(fn -> File.exists?(pid_file) end, 1_000)
      pid = pid_file |> File.read!() |> String.trim() |> String.to_integer()

      assert :ok == wait_until(fn -> not process_alive?(pid) end, 4_000)
    after
      File.rm_rf(dir)
    end
  end

  defp write_stubborn_stream_stub!(dir) do
    script = """
    #!/usr/bin/env bash
    set -euo pipefail

    if [ -n "${CLAUDE_SDK_TEST_PID_FILE:-}" ]; then
      echo $$ > "$CLAUDE_SDK_TEST_PID_FILE"
    fi

    echo '{"type":"assistant","message":{"role":"assistant","content":"hello"},"session_id":"sess_cleanup"}'

    trap '' TERM
    trap '' INT

    tail -f /dev/null
    """

    path = Path.join(dir, "stubborn_stream_stub.sh")
    File.write!(path, script)
    File.chmod!(path, 0o755)
    path
  end

  defp tmp_dir!(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp process_alive?(pid) when is_integer(pid) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp wait_until(fun, timeout_ms) when is_function(fun, 0) and is_integer(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(25)
        do_wait_until(fun, deadline)
    end
  end
end
