defmodule ClaudeAgentSDK.Transport.ErlexecTransportTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Transport.Erlexec, as: ErlexecTransport

  test "returns error when command not found" do
    assert {:error, _reason} =
             ErlexecTransport.start(
               command: "/nonexistent/binary/xyz",
               args: [],
               options: %Options{}
             )
  end

  test "start_link preserves OTP ancestor metadata" do
    script =
      create_test_script("""
      while read -r line; do
        echo "$line"
      done
      """)

    {:ok, transport} = ErlexecTransport.start_link(command: script, args: [], options: %Options{})

    try do
      assert {:dictionary, dictionary} = Process.info(transport, :dictionary)
      assert {:"$ancestors", ancestors} = List.keyfind(dictionary, :"$ancestors", 0)
      assert self() in ancestors
    after
      ErlexecTransport.close(transport)
    end
  end

  test "start_link delegates directly to GenServer.start_link without manual linking" do
    start_link_form = function_form!(ErlexecTransport, :start_link, 1)

    assert contains_remote_call?(start_link_form, GenServer, :start_link)
    refute contains_local_call?(start_link_form, :start)
    refute contains_remote_call?(start_link_form, Process, :link)
  end

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

    {:ok, transport} =
      ErlexecTransport.start_link(
        command: script,
        args: [],
        options: options,
        subscriber: self()
      )

    assert :ok = ErlexecTransport.subscribe(transport, self())

    assert_receive {:stderr_line, "ERR_LINE"}, 1_000
    assert_receive {:transport_message, init_line}, 1_000
    assert init_line =~ ~s("type":"system")

    assert :ok = ErlexecTransport.send(transport, "PING\n")
    assert_receive {:transport_message, "PING"}, 1_000

    ErlexecTransport.close(transport)
  end

  test "emits CLIJSONDecodeError when max_buffer_size is exceeded" do
    options = %Options{max_buffer_size: 10}

    script =
      create_test_script("""
      while read -r line; do
        echo "$line"
      done
      """)

    {:ok, transport} = ErlexecTransport.start_link(command: script, args: [], options: options)
    assert :ok = ErlexecTransport.subscribe(transport, self())

    :ok = ErlexecTransport.send(transport, String.duplicate("a", 20))

    assert_receive {:transport_error, %CLIJSONDecodeError{message: message}}, 1_000
    assert message =~ "maximum buffer size"

    ErlexecTransport.close(transport)
  end

  test "lazy startup defers subprocess start failures" do
    Process.flag(:trap_exit, true)

    missing_cwd =
      Path.join(System.tmp_dir!(), "erlexec_missing_cwd_#{System.unique_integer([:positive])}")

    assert {:ok, transport} =
             ErlexecTransport.start_link(
               command: "/bin/cat",
               args: [],
               startup_mode: :lazy,
               options: %Options{cwd: missing_cwd}
             )

    assert_receive {:EXIT, ^transport, {:cwd_not_found, ^missing_cwd}}, 1_000
  end

  test "exec opts include :user when Options.user is set" do
    exec_opts = ErlexecTransport.__exec_opts__(%Options{user: "runner"})
    assert {:user, ~c"runner"} in exec_opts
  end

  test "repeated subscribe calls do not create duplicate subscriber monitors" do
    script =
      create_test_script("""
      while read -r line; do
        echo "$line"
      done
      """)

    {:ok, transport} = ErlexecTransport.start_link(command: script, args: [], options: %Options{})

    assert :ok = ErlexecTransport.subscribe(transport, self())
    assert :ok = ErlexecTransport.subscribe(transport, self())

    state = :sys.get_state(transport)
    assert map_size(state.subscribers) == 1

    ErlexecTransport.close(transport)
  end

  test "supports multiple concurrent subscribers" do
    script =
      create_test_script("""
      while read -r line; do
        echo "$line"
      done
      """)

    {:ok, transport} = ErlexecTransport.start_link(command: script, args: [], options: %Options{})

    parent = self()

    {:ok, _task_pid} =
      Task.start(fn ->
        assert :ok = ErlexecTransport.subscribe(transport, self())

        receive do
          {:transport_message, message} ->
            send(parent, {:child_received, message})
        after
          1_000 ->
            send(parent, {:child_timeout, self()})
        end
      end)

    assert :ok = ErlexecTransport.subscribe(transport, self())
    assert :ok = ErlexecTransport.send(transport, "broadcast")

    assert_receive {:transport_message, "broadcast"}, 1_000
    assert_receive {:child_received, "broadcast"}, 1_000
    refute_receive {:child_timeout, _}, 100

    ErlexecTransport.close(transport)
  end

  test "unsubscribe removes subscriber monitor" do
    script =
      create_test_script("""
      while read -r line; do
        echo "$line"
      done
      """)

    {:ok, transport} = ErlexecTransport.start_link(command: script, args: [], options: %Options{})

    assert :ok = ErlexecTransport.subscribe(transport, self())
    state = :sys.get_state(transport)
    assert map_size(state.subscribers) == 1

    assert :ok = ErlexecTransport.unsubscribe(transport, self())

    updated_state = :sys.get_state(transport)
    assert map_size(updated_state.subscribers) == 0

    ErlexecTransport.close(transport)
  end

  test "close/1 is idempotent when process is already gone" do
    script =
      create_test_script("""
      while read -r line; do
        echo "$line"
      done
      """)

    {:ok, transport} = ErlexecTransport.start_link(command: script, args: [], options: %Options{})

    assert :ok = ErlexecTransport.close(transport)
    assert :ok = ErlexecTransport.close(transport)
  end

  describe "force_close/1" do
    test "force_close stops subprocess and returns :ok" do
      script = create_test_script("while read -r line; do echo $line; done")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          subscriber: self()
        )

      ErlexecTransport.subscribe(transport, self())
      assert :ok = ErlexecTransport.force_close(transport)
    end

    test "returns typed error after transport exits" do
      script = create_test_script("echo hi")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          subscriber: self()
        )

      ErlexecTransport.subscribe(transport, self())
      assert_receive {:transport_exit, _}, 2_000
      Process.sleep(100)
      assert {:error, {:transport, :not_connected}} = ErlexecTransport.send(transport, "data")
    end
  end

  describe "safe_call/3 isolation" do
    test "handles transport death during call gracefully" do
      script = create_test_script("echo hi")

      {:ok, transport} =
        ErlexecTransport.start_link(command: script, args: [], options: %Options{})

      ErlexecTransport.subscribe(transport, self())
      assert_receive {:transport_exit, _}, 2_000
      Process.sleep(100)
      # Should not raise; status reports disconnected after exit
      assert :disconnected = ErlexecTransport.status(transport)
    end
  end

  describe "binary-safe stdout framing" do
    test "handles UTF-8 codepoint split across stdout chunks" do
      ref = make_ref()

      script =
        create_test_script("""
        printf 'hello \\342'
        sleep 0.1
        printf '\\200\\224 world\\n'
        sleep 0.1
        """)

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          subscriber: {self(), ref}
        )

      try do
        assert_receive {:claude_agent_sdk_transport, ^ref,
                        {:message, "hello " <> <<226, 128, 148>> <> " world"}},
                       2_000

        assert_receive {:claude_agent_sdk_transport, ^ref, {:exit, _}}, 2_000
      after
        _ = ErlexecTransport.force_close(transport)
      end
    end
  end

  describe "interrupt/1" do
    test "supports interrupting in-flight subprocesses" do
      script = create_test_script("while read -r _line; do :; done")

      {:ok, transport} =
        ErlexecTransport.start_link(command: script, args: [], options: %Options{})

      try do
        assert :ok = ErlexecTransport.interrupt(transport)
      after
        _ = ErlexecTransport.force_close(transport)
      end
    end
  end

  describe "tagged subscriber dispatch" do
    test "dispatches events with tagged ref" do
      ref = make_ref()
      script = create_test_script("while read -r line; do echo \"$line\"; done")

      {:ok, transport} =
        ErlexecTransport.start_link(command: script, args: [], options: %Options{})

      ErlexecTransport.subscribe(transport, self(), ref)
      assert :ok = ErlexecTransport.send(transport, "hello")
      assert :ok = ErlexecTransport.end_input(transport)

      assert_receive {:claude_agent_sdk_transport, ^ref, {:message, "hello"}}, 2_000
      assert_receive {:claude_agent_sdk_transport, ^ref, {:exit, _}}, 2_000
    end

    test "legacy subscribers still receive bare tuples" do
      script = create_test_script("while read -r line; do echo \"$line\"; done")

      {:ok, transport} =
        ErlexecTransport.start_link(command: script, args: [], options: %Options{})

      ErlexecTransport.subscribe(transport, self())
      assert :ok = ErlexecTransport.send(transport, "hello")
      assert :ok = ErlexecTransport.end_input(transport)

      assert_receive {:transport_message, "hello"}, 2_000
      assert_receive {:transport_exit, _}, 2_000
    end
  end

  describe "stderr dispatch" do
    test "dispatches stderr events to tagged subscribers" do
      ref = make_ref()

      script =
        create_test_script("""
        while read -r line; do
          echo err >&2
          echo "$line"
        done
        """)

      {:ok, transport} =
        ErlexecTransport.start_link(command: script, args: [], options: %Options{})

      ErlexecTransport.subscribe(transport, self(), ref)
      assert :ok = ErlexecTransport.send(transport, "out")
      assert :ok = ErlexecTransport.end_input(transport)

      assert_receive {:claude_agent_sdk_transport, ^ref, {:message, "out"}}, 2_000
      assert_receive {:claude_agent_sdk_transport, ^ref, {:stderr, stderr_data}}, 2_000
      assert stderr_data =~ "err"
      assert_receive {:claude_agent_sdk_transport, ^ref, {:exit, _}}, 2_000
    end
  end

  describe "queue-based drain" do
    test "handles burst output without losing messages" do
      script = create_test_script("for i in $(seq 1 500); do echo \"line_$i\"; done")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          subscriber: self()
        )

      ErlexecTransport.subscribe(transport, self())

      lines = collect_messages([], 5_000)
      assert length(lines) == 500
      assert "line_1" in lines
      assert "line_500" in lines
    end
  end

  describe "stderr buffer" do
    test "stderr/1 returns captured stderr" do
      script =
        create_test_script("""
        read -r _line
        echo err >&2
        while read -r _line; do
          :
        done
        """)

      {:ok, transport} =
        ErlexecTransport.start_link(command: script, args: [], options: %Options{})

      ErlexecTransport.subscribe(transport, self())
      assert :ok = ErlexecTransport.send(transport, "go")
      assert_receive {:transport_stderr, stderr_data}, 2_000
      assert stderr_data =~ "err"
      stderr = ErlexecTransport.stderr(transport)
      assert stderr =~ "err"
      ErlexecTransport.close(transport)
    end

    test "caps stderr buffer to max_stderr_buffer_size" do
      script =
        create_test_script(
          ~s|python3 -c "import sys; sys.stderr.write('x' * 1000000)"; while read -r _line; do :; done|
        )

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          max_stderr_buffer_size: 256
        )

      ErlexecTransport.subscribe(transport, self())
      assert_receive {:transport_stderr, _}, 5_000
      stderr = ErlexecTransport.stderr(transport)
      assert byte_size(stderr) <= 256
      ErlexecTransport.close(transport)
    end
  end

  describe "headless timeout" do
    test "auto-stops transport when no subscribers after timeout" do
      script = create_test_script("sleep 60")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          headless_timeout_ms: 100
        )

      monitor = Process.monitor(transport)
      assert_receive {:DOWN, ^monitor, :process, ^transport, _}, 2_000
    end

    test "cancels headless timer on subscribe" do
      script = create_test_script("while read -r line; do echo $line; done")

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          headless_timeout_ms: 200
        )

      ErlexecTransport.subscribe(transport, self())
      Process.sleep(300)
      assert :connected = ErlexecTransport.status(transport)
      ErlexecTransport.close(transport)
    end
  end

  describe "subscriber lifecycle" do
    test "auto-stops when last subscriber goes down" do
      script = create_test_script("while read -r line; do echo $line; done")

      subscriber =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          headless_timeout_ms: 100
        )

      ErlexecTransport.subscribe(transport, subscriber)
      monitor = Process.monitor(transport)

      send(subscriber, :stop)
      assert_receive {:DOWN, ^monitor, :process, ^transport, _}, 2_000
    end
  end

  describe "concurrency stress" do
    test "delivers full burst to multiple subscribers without loss or duplication" do
      subscriber_count = 5
      line_count = 300

      script =
        create_test_script("""
        while read -r _line; do
          for i in $(seq 1 #{line_count}); do
            echo "line_$i"
          done
          break
        done
        """)

      {:ok, transport} =
        ErlexecTransport.start_link(command: script, args: [], options: %Options{})

      parent = self()

      _subscriber_pids =
        for idx <- 1..subscriber_count do
          spawn(fn ->
            :ok = ErlexecTransport.subscribe(transport, self())
            send(parent, {:subscriber_ready, idx})
            lines = collect_messages([], 10_000)
            send(parent, {:subscriber_done, idx, lines})
          end)
        end

      for idx <- 1..subscriber_count do
        assert_receive {:subscriber_ready, ^idx}, 2_000
      end

      assert :ok = ErlexecTransport.send(transport, "go")

      for idx <- 1..subscriber_count do
        assert_receive {:subscriber_done, ^idx, lines}, 15_000
        assert length(lines) == line_count
        assert length(Enum.uniq(lines)) == line_count
        assert "line_1" in lines
        assert "line_#{line_count}" in lines
      end
    end
  end

  describe "finalize drain responsiveness" do
    test "status call remains responsive while finalize drains a large queue" do
      line_count = 20_000

      script =
        create_test_script("""
        for i in $(seq 1 #{line_count}); do
          echo "line_$i"
        done
        """)

      {:ok, transport} =
        ErlexecTransport.start_link(
          command: script,
          args: [],
          options: %Options{},
          subscriber: self()
        )

      monitor = Process.monitor(transport)

      try do
        statuses =
          Enum.map(1..20, fn _idx ->
            ErlexecTransport.status(transport)
          end)

        assert Enum.all?(statuses, &(&1 in [:connected, :disconnected]))

        lines = collect_messages([], 15_000)
        assert length(lines) == line_count
        assert "line_1" in lines
        assert "line_#{line_count}" in lines
        assert_receive {:DOWN, ^monitor, :process, ^transport, _reason}, 5_000
      after
        if Process.alive?(transport) do
          _ = ErlexecTransport.force_close(transport)
          assert_receive {:DOWN, ^monitor, :process, ^transport, _reason}, 2_000
        end
      end
    end
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

  defp collect_messages(acc, timeout) do
    receive do
      {:transport_message, line} -> collect_messages([line | acc], timeout)
      {:transport_exit, _} -> Enum.reverse(acc)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  defp function_form!(module, name, arity) do
    beam_path = :code.which(module)

    {:ok, {_, [abstract_code: {:raw_abstract_v1, forms}]}} =
      :beam_lib.chunks(beam_path, [:abstract_code])

    Enum.find(forms, fn
      {:function, _, ^name, ^arity, _clauses} -> true
      _other -> false
    end) || raise "function #{inspect(module)}.#{name}/#{arity} not found in abstract code"
  end

  defp contains_remote_call?(term, module, function)

  defp contains_remote_call?(
         {:call, _, {:remote, _, {:atom, _, module}, {:atom, _, function}}, _},
         module,
         function
       ),
       do: true

  defp contains_remote_call?(term, module, function) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.any?(&contains_remote_call?(&1, module, function))
  end

  defp contains_remote_call?(term, module, function) when is_list(term) do
    Enum.any?(term, &contains_remote_call?(&1, module, function))
  end

  defp contains_remote_call?(_term, _module, _function), do: false

  defp contains_local_call?(term, function)

  defp contains_local_call?({:call, _, {:atom, _, function}, _}, function), do: true

  defp contains_local_call?(term, function) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.any?(&contains_local_call?(&1, function))
  end

  defp contains_local_call?(term, function) when is_list(term) do
    Enum.any?(term, &contains_local_call?(&1, function))
  end

  defp contains_local_call?(_term, _function), do: false
end
