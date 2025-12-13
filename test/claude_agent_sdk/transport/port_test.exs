defmodule ClaudeAgentSDK.Transport.PortTest do
  @moduledoc """
  TDD tests for the default port-based transport implementation.
  """
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Transport.Port, as: PortTransport

  @cat_executable System.find_executable("cat") || "/bin/cat"

  describe "start_link/1" do
    test "should_start_genserver_when_given_valid_options" do
      {:ok, transport} = PortTransport.start_link(command: @cat_executable, args: [])
      assert is_pid(transport)
      assert Process.alive?(transport)
      assert :connected = PortTransport.status(transport)
      PortTransport.close(transport)
    end

    test "should_return_error_when_command_not_found" do
      assert {:error, {:command_not_found, "nonexistent_command_xyz"}} =
               PortTransport.start_link(command: "nonexistent_command_xyz")
    end
  end

  describe "send/2" do
    setup do
      {:ok, transport} = PortTransport.start_link(command: @cat_executable, args: [])

      on_exit(fn ->
        try do
          PortTransport.close(transport)
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, transport: transport}
    end

    test "should_send_message_to_port_and_receive_response", %{transport: transport} do
      PortTransport.subscribe(transport, self())

      assert :ok = PortTransport.send(transport, ~s({"message":"hello"}))

      assert_receive {:transport_message, ~s({"message":"hello"})}, 500
    end

    test "should_append_newline_if_missing", %{transport: transport} do
      PortTransport.subscribe(transport, self())
      assert :ok = PortTransport.send(transport, "ping")

      assert_receive {:transport_message, "ping"}, 500
    end

    test "should_return_error_when_transport_closed", %{transport: transport} do
      PortTransport.close(transport)
      refute Process.alive?(transport)
      assert {:noproc, _} = catch_exit(PortTransport.send(transport, "ping"))
    end
  end

  describe "subscribe/2" do
    setup do
      {:ok, transport} = PortTransport.start_link(command: @cat_executable, args: [])

      on_exit(fn ->
        try do
          PortTransport.close(transport)
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, transport: transport}
    end

    test "should_register_subscriber_and_deliver_messages", %{transport: transport} do
      PortTransport.subscribe(transport, self())
      PortTransport.send(transport, "hello")

      assert_receive {:transport_message, "hello"}, 500
    end

    test "should_support_multiple_subscribers", %{transport: transport} do
      parent = self()

      Task.start(fn ->
        PortTransport.subscribe(transport, self())

        receive do
          {:transport_message, message} ->
            send(parent, {:child_received, message})
        after
          500 ->
            send(parent, {:child_timeout, self()})
        end
      end)

      PortTransport.subscribe(transport, self())
      PortTransport.send(transport, "broadcast")

      assert_receive {:transport_message, "broadcast"}, 500
      assert_receive {:child_received, "broadcast"}, 500
      refute_receive {:child_timeout, _}, 100
    end
  end

  describe "close/1 and status/1" do
    test "should_close_port_and_update_status" do
      {:ok, transport} = PortTransport.start_link(command: @cat_executable, args: [])
      assert :connected = PortTransport.status(transport)

      assert :ok = PortTransport.close(transport)

      refute Process.alive?(transport)
    end
  end

  describe "option propagation" do
    test "passes env overrides to the spawned process" do
      script =
        create_test_script("""
        printf "%s\\n" "$PORT_ENV_TEST"
        exec cat
        """)

      options = %Options{env: %{"PORT_ENV_TEST" => "from_options"}}

      {:ok, transport} = PortTransport.start_link(command: script, args: [], options: options)
      PortTransport.subscribe(transport, self())

      assert_receive {:transport_message, "from_options"}, 500
      PortTransport.close(transport)
    end

    test "applies cwd from options" do
      tmp_dir = Path.join(System.tmp_dir!(), "port_cwd_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      script =
        create_test_script("""
        pwd
        exec cat
        """)

      options = %Options{cwd: tmp_dir}

      {:ok, transport} = PortTransport.start_link(command: script, args: [], options: options)
      PortTransport.subscribe(transport, self())

      assert_receive {:transport_message, ^tmp_dir}, 500
      PortTransport.close(transport)
    end
  end

  defp create_test_script(body) do
    dir = Path.join(System.tmp_dir!(), "port_transport_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "transport_port_test.sh")

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
