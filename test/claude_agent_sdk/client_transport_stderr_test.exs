defmodule ClaudeAgentSDK.ClientTransportStderrTest do
  @moduledoc """
  Regression tests for transport stderr handling in the Client.
  """
  use ClaudeAgentSDK.SupertesterCase

  import ExUnit.CaptureLog

  @moduletag capture_log: true

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport
  alias ClaudeAgentSDK.Transport.Erlexec, as: ErlexecTransport

  describe "transport_stderr handling" do
    test "client survives text and non-UTF-8 {:transport_stderr, _} messages without crashing" do
      {:ok, client} =
        Client.start_link(%Options{},
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      assert_receive {:mock_transport_started, _transport_pid}, 1_000

      send(client, {:transport_stderr, "Error: something went wrong on stderr\n"})
      send(client, {:transport_stderr, <<255, "\n">>})
      state = :sys.get_state(client)

      assert state.stderr_buffer == ""
      assert {:error, :timeout} = Client.await_initialized(client, 100)
    end

    test "buffers split stderr chunks and invokes callback once per completed line" do
      test_pid = self()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      assert_receive {:mock_transport_started, _transport_pid}, 1_000

      send(client, {:transport_stderr, "ERR"})
      state = :sys.get_state(client)

      assert state.stderr_buffer == "ERR"
      refute_receive {:stderr_line, _}, 50

      send(client, {:transport_stderr, "_LINE\n"})
      state = :sys.get_state(client)

      assert state.stderr_buffer == ""
      assert_receive {:stderr_line, "ERR_LINE"}, 1_000
      refute_receive {:stderr_line, "ERR_LINE"}, 50
    end

    test "flushes a buffered stderr line before transport shutdown" do
      test_pid = self()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      assert_receive {:mock_transport_started, _transport_pid}, 1_000

      send(client, {:transport_stderr, "partial stderr"})
      state = :sys.get_state(client)
      assert state.stderr_buffer == "partial stderr"

      monitor = Process.monitor(client)
      send(client, {:transport_exit, :test_disconnect})

      assert_receive {:stderr_line, "partial stderr"}, 1_000
      assert_receive {:DOWN, ^monitor, :process, ^client, :normal}, 1_000
    end

    test "ignores unexpected mailbox messages without crashing" do
      {:ok, client} =
        Client.start_link(%Options{},
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      assert_receive {:mock_transport_started, _transport_pid}, 1_000

      log =
        capture_log(fn ->
          send(client, {:unexpected_transport_shape, %{raw: true}})
          _ = :sys.get_state(client)
          Logger.flush()
        end)

      assert Process.alive?(client)
      assert log =~ "Ignoring unexpected client mailbox message"
    end

    test "built-in erlexec transport delivers stderr callback exactly once via the client" do
      test_pid = self()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      script =
        create_test_script("""
        python3 -c "$(cat <<'PY'
        import json
        import sys

        line = sys.stdin.readline()
        if not line:
            raise SystemExit(1)

        print("ERR_LINE", file=sys.stderr, flush=True)
        request = json.loads(line)
        response = {
            "type": "control_response",
            "response": {
                "subtype": "success",
                "request_id": request["request_id"],
                "response": {}
            }
        }
        print(json.dumps(response), flush=True)

        for _ in sys.stdin:
            pass
        PY
        )"
        """)

      {:ok, client} =
        Client.start_link(options,
          transport: ErlexecTransport,
          transport_opts: [command: script, args: []]
        )

      on_exit(fn -> safe_stop(client) end)

      assert is_reference(:sys.get_state(client).transport_ref)
      assert_receive {:stderr_line, "ERR_LINE"}, 1_000
      assert :ok = Client.await_initialized(client, 1_000)
      refute_receive {:stderr_line, "ERR_LINE"}, 100
    end

    test "built-in erlexec preserves invalid UTF-8 stderr lines" do
      test_pid = self()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      script =
        create_test_script("""
        python3 -c "$(cat <<'PY'
        import json
        import sys

        line = sys.stdin.readline()
        if not line:
            raise SystemExit(1)

        sys.stderr.buffer.write(b"\\xff\\n")
        sys.stderr.flush()

        request = json.loads(line)
        response = {
            "type": "control_response",
            "response": {
                "subtype": "success",
                "request_id": request["request_id"],
                "response": {}
            }
        }
        print(json.dumps(response), flush=True)

        for _ in sys.stdin:
            pass
        PY
        )"
        """)

      {:ok, client} =
        Client.start_link(options,
          transport: ErlexecTransport,
          transport_opts: [command: script, args: []]
        )

      on_exit(fn -> safe_stop(client) end)

      assert_receive {:stderr_line, <<255>>}, 1_000
      assert :ok = Client.await_initialized(client, 1_000)
    end

    test "built-in erlexec flushes a partial stderr fragment on fast exit" do
      test_pid = self()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      script =
        create_test_script("""
        python3 -c "$(cat <<'PY'
        import json
        import sys

        line = sys.stdin.readline()
        if not line:
            raise SystemExit(1)

        request = json.loads(line)
        response = {
            "type": "control_response",
            "response": {
                "subtype": "success",
                "request_id": request["request_id"],
                "response": {}
            }
        }
        print(json.dumps(response), flush=True)
        sys.stderr.write("TAIL_FRAGMENT")
        sys.stderr.flush()
        PY
        )"
        """)

      {:ok, client} =
        Client.start_link(options,
          transport: ErlexecTransport,
          transport_opts: [command: script, args: []]
        )

      monitor = Process.monitor(client)

      assert_receive {:stderr_line, "TAIL_FRAGMENT"}, 1_000
      assert_receive {:DOWN, ^monitor, :process, ^client, :normal}, 1_000
    end

    test "built-in erlexec surfaces stderr emitted after initialize" do
      test_pid = self()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      script =
        create_test_script("""
        python3 -c "$(cat <<'PY'
        import json
        import sys

        line = sys.stdin.readline()
        if not line:
            raise SystemExit(1)

        request = json.loads(line)
        response = {
            "type": "control_response",
            "response": {
                "subtype": "success",
                "request_id": request["request_id"],
                "response": {}
            }
        }
        print(json.dumps(response), flush=True)

        for line in sys.stdin:
            if not line:
                break
            print("ERR_AFTER_INIT", file=sys.stderr, flush=True)
        PY
        )"
        """)

      {:ok, client} =
        Client.start_link(options,
          transport: ErlexecTransport,
          transport_opts: [command: script, args: []]
        )

      on_exit(fn -> safe_stop(client) end)

      assert :ok = Client.await_initialized(client, 1_000)
      assert :ok = Client.query(client, "hi")
      assert_receive {:stderr_line, "ERR_AFTER_INIT"}, 1_000
    end
  end

  defp safe_stop(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Client.stop(pid)
  catch
    :exit, _ -> :ok
  end

  defp create_test_script(body) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "client_transport_stderr_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "client_transport_stderr_test.sh")

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
