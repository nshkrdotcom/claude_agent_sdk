defmodule ClaudeAgentSDK.ClientTransportStderrTest do
  @moduledoc """
  Regression tests for transport stderr handling in the Client.
  """
  use ClaudeAgentSDK.SupertesterCase

  import ExUnit.CaptureLog

  @moduletag capture_log: true

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  describe "transport_stderr handling" do
    test "client survives text and non-UTF-8 {:transport_stderr, _} messages without crashing" do
      fake_cli = FakeCLI.new!()

      {:ok, client} =
        Client.start_link(FakeCLI.options(fake_cli, %Options{}))

      on_exit(fn ->
        safe_stop(client)
        FakeCLI.cleanup(fake_cli)
      end)

      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

      send(client, {:protocol_stderr, "Error: something went wrong on stderr\n"})
      send(client, {:protocol_stderr, <<255, "\n">>})
      state = :sys.get_state(client)

      assert state.stderr_buffer == ""
      assert {:error, :timeout} = Client.await_initialized(client, 100)
    end

    test "buffers split stderr chunks and invokes callback once per completed line" do
      test_pid = self()
      fake_cli = FakeCLI.new!()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      {:ok, client} =
        Client.start_link(FakeCLI.options(fake_cli, options))

      on_exit(fn ->
        safe_stop(client)
        FakeCLI.cleanup(fake_cli)
      end)

      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

      send(client, {:protocol_stderr, "ERR"})
      state = :sys.get_state(client)

      assert state.stderr_buffer == "ERR"
      refute_receive {:stderr_line, _}, 50

      send(client, {:protocol_stderr, "_LINE\n"})
      state = :sys.get_state(client)

      assert state.stderr_buffer == ""
      assert_receive {:stderr_line, "ERR_LINE"}, 1_000
      refute_receive {:stderr_line, "ERR_LINE"}, 50
    end

    test "flushes a buffered stderr line before transport shutdown" do
      test_pid = self()
      fake_cli = FakeCLI.new!()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      {:ok, client} =
        Client.start_link(FakeCLI.options(fake_cli, options))

      on_exit(fn ->
        safe_stop(client)
        FakeCLI.cleanup(fake_cli)
      end)

      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

      send(client, {:protocol_stderr, "partial stderr"})
      state = :sys.get_state(client)
      assert state.stderr_buffer == "partial stderr"

      monitor = Process.monitor(client)
      Process.exit(state.protocol_session, :test_disconnect)

      assert_receive {:stderr_line, "partial stderr"}, 1_000
      assert_receive {:DOWN, ^monitor, :process, ^client, :normal}, 1_000
    end

    test "ignores unexpected mailbox messages without crashing" do
      fake_cli = FakeCLI.new!()

      {:ok, client} =
        Client.start_link(FakeCLI.options(fake_cli, %Options{}))

      on_exit(fn ->
        safe_stop(client)
        FakeCLI.cleanup(fake_cli)
      end)

      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

      log =
        capture_log(fn ->
          send(client, {:unexpected_transport_shape, %{raw: true}})
          _ = :sys.get_state(client)
          Process.sleep(50)
          Logger.flush()
        end)

      assert Process.alive?(client)
      assert log =~ "Ignoring unexpected client mailbox message"
    end

    test "built-in transport delivers stderr callback exactly once via the client" do
      test_pid = self()
      fake_cli = FakeCLI.new!()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))

      on_exit(fn ->
        safe_stop(client)
        FakeCLI.cleanup(fake_cli)
      end)

      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
      request_id = FakeCLI.respond_initialize_success!(fake_cli)
      assert is_binary(request_id)
      FakeCLI.push_stderr(fake_cli, "ERR_LINE")

      assert_receive {:stderr_line, "ERR_LINE"}, 1_000
      assert :ok = Client.await_initialized(client, 1_000)
      refute_receive {:stderr_line, "ERR_LINE"}, 100
    end

    test "built-in transport preserves invalid UTF-8 stderr lines" do
      test_pid = self()
      fake_cli = FakeCLI.new!()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))

      on_exit(fn ->
        safe_stop(client)
        FakeCLI.cleanup(fake_cli)
      end)

      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
      _request_id = FakeCLI.respond_initialize_success!(fake_cli)
      FakeCLI.push_stderr(fake_cli, <<255>>)
      assert_receive {:stderr_line, <<255>>}, 1_000
      assert :ok = Client.await_initialized(client, 1_000)
    end

    test "built-in transport flushes a partial stderr fragment on fast exit" do
      test_pid = self()
      fake_cli = FakeCLI.new!()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))

      on_exit(fn ->
        safe_stop(client)
        FakeCLI.cleanup(fake_cli)
      end)

      monitor = Process.monitor(client)
      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
      state = :sys.get_state(client)
      send(client, {:protocol_stderr, "TAIL_FRAGMENT"})
      Process.exit(state.protocol_session, :test_disconnect)

      assert_receive {:stderr_line, "TAIL_FRAGMENT"}, 1_000
      assert_receive {:DOWN, ^monitor, :process, ^client, :normal}, 1_000
    end

    test "built-in transport surfaces stderr emitted after initialize" do
      test_pid = self()
      fake_cli = FakeCLI.new!()

      options = %Options{
        stderr: fn line -> send(test_pid, {:stderr_line, line}) end
      }

      {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))

      on_exit(fn ->
        safe_stop(client)
        FakeCLI.cleanup(fake_cli)
      end)

      assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
      _request_id = FakeCLI.respond_initialize_success!(fake_cli)
      assert :ok = Client.await_initialized(client, 1_000)
      assert :ok = Client.query(client, "hi")
      assert :ok = FakeCLI.wait_for_request_count(fake_cli, 2, 1_000)
      FakeCLI.push_stderr(fake_cli, "ERR_AFTER_INIT")
      assert_receive {:stderr_line, "ERR_AFTER_INIT"}, 1_000
    end
  end

  defp safe_stop(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Client.stop(pid)
  catch
    :exit, _ -> :ok
  end
end
