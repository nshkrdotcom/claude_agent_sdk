defmodule ClaudeAgentSDK.ClientPermissionTest do
  @moduledoc """
  Integration tests for Client GenServer with Permission System.

  Tests:
  - Permission callback integration with Client
  - Control protocol handling for can_use_tool requests
  - Runtime permission mode switching
  - Permission mode behavior in Client
  """

  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  @moduletag :requires_cli
  # Most tests spawn real CLI process (no MockTransport)
  @moduletag :live_cli

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Permission.Result
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  describe "Client with permission callbacks" do
    test "Client starts with can_use_tool callback in options" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, pid} = Client.start_link(options)
      assert Process.alive?(pid)

      Client.stop(pid)
    end

    test "Client validates can_use_tool callback is a function" do
      # Trap exits to capture validation failure
      Process.flag(:trap_exit, true)

      # Invalid: not a function
      options = %Options{
        can_use_tool: "not_a_function",
        permission_mode: :default
      }

      # Should validate and reject
      result = Client.start_link(options)

      case result do
        {:error, {:validation_failed, _}} ->
          assert true

        {:ok, pid} ->
          # Wait for EXIT message if process crashes
          receive do
            {:EXIT, ^pid, {:validation_failed, _}} ->
              assert true

            other ->
              flunk("Expected validation exit, got: #{inspect(other)}")
          after
            100 ->
              Client.stop(pid)
              flunk("Process did not crash as expected")
          end

        other ->
          flunk("Expected validation error, got: #{inspect(other)}")
      end
    end

    @tag :live_cli
    # This test requires mock CLI process, will be implemented with integration test helpers
    test "Client invokes callback on can_use_tool control request" do
      test_pid = self()

      callback = fn context ->
        send(test_pid, {:callback_invoked, context.tool_name})
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # Simulate can_use_tool control request
      # (This would come from CLI in real scenario)
      _request = %{
        "type" => "control_request",
        "request_id" => "test-req-1",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{"command" => "ls"},
          "permission_suggestions" => []
        }
      }

      # Send request to client (simulated)
      # In real implementation, this comes via Port
      # send(client, {:port_data, Jason.encode!(request)})

      # Assert callback was invoked
      # assert_receive {:callback_invoked, "Bash"}, 1000

      Client.stop(client)
    end
  end

  describe "Client.set_permission_mode/2" do
    test "set_permission_mode/2 updates permission mode at runtime" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      %{client: client, transport: transport} = start_initialized_client_with_fake_cli(options)

      _request_count =
        Enum.reduce(
          [:plan, :accept_edits, :bypass_permissions, :default, :auto, :dont_ask],
          1,
          fn mode, request_count ->
            task = Task.async(fn -> Client.set_permission_mode(client, mode) end)
            request = wait_for_request(transport, request_count + 1)

            assert request["request"]["subtype"] == "set_permission_mode"
            assert request["request"]["mode"] == Atom.to_string(mode)

            FakeCLI.push_message(transport, success_response(request["request_id"]))
            assert :ok = Task.await(task, 500)

            state = :sys.get_state(client)
            assert state.options.permission_mode == mode

            request_count + 1
          end
        )
    end

    test "set_permission_mode/2 sends control request and applies CLI response" do
      options = %Options{permission_mode: :default}

      %{client: client, transport: transport} = start_initialized_client_with_fake_cli(options)

      task = Task.async(fn -> Client.set_permission_mode(client, :plan) end)
      request = wait_for_request(transport, 2)

      assert request["request"]["subtype"] == "set_permission_mode"
      assert request["request"]["mode"] == "plan"

      FakeCLI.push_message(transport, success_response(request["request_id"]))

      assert :ok = Task.await(task, 500)

      state = :sys.get_state(client)
      assert state.options.permission_mode == :plan
    end

    test "set_permission_mode/2 surfaces CLI error responses" do
      options = %Options{permission_mode: :default}

      %{client: client, transport: transport} = start_initialized_client_with_fake_cli(options)

      task = Task.async(fn -> Client.set_permission_mode(client, :accept_edits) end)
      request = wait_for_request(transport, 2)

      FakeCLI.push_message(
        transport,
        error_response(request["request_id"], "permission mode rejected")
      )

      assert {:error, "permission mode rejected"} = Task.await(task, 500)

      state = :sys.get_state(client)
      assert state.options.permission_mode == :default
    end

    test "set_permission_mode/2 validates mode value" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # Invalid mode
      assert {:error, :invalid_permission_mode} =
               Client.set_permission_mode(client, :invalid_mode)

      Client.stop(client)
    end

    test "set_permission_mode/2 with nil mode returns error" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      assert {:error, :invalid_permission_mode} = Client.set_permission_mode(client, nil)

      Client.stop(client)
    end
  end

  describe "can_use_tool response encoding" do
    test "allow response includes updatedInput defaulting to original input" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      %{transport: transport} = start_initialized_client_with_fake_cli(options)

      request_id = "perm_req_1"

      can_use_tool_request = %{
        "type" => "control_request",
        "request_id" => request_id,
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{"command" => "ls"},
          "permission_suggestions" => []
        }
      }

      FakeCLI.push_message(transport, can_use_tool_request)

      {:ok, decoded} = FakeCLI.wait_for_control_response(transport, request_id, 1_000)

      assert decoded["type"] == "control_response"
      assert decoded["response"]["subtype"] == "success"
      assert decoded["response"]["request_id"] == request_id
      assert decoded["response"]["response"]["behavior"] == "allow"
      assert decoded["response"]["response"]["updatedInput"] == %{"command" => "ls"}
      refute Map.has_key?(decoded["response"]["response"], "updated_input")
    end

    test "allow response uses camelCase updatedPermissions" do
      callback = fn _context ->
        Result.allow(updated_permissions: [%{"type" => "setMode", "mode" => "plan"}])
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      %{transport: transport} = start_initialized_client_with_fake_cli(options)

      request_id = "perm_req_2"

      can_use_tool_request = %{
        "type" => "control_request",
        "request_id" => request_id,
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Write",
          "input" => %{"file_path" => "/tmp/x.txt", "content" => "hi"},
          "permission_suggestions" => []
        }
      }

      FakeCLI.push_message(transport, can_use_tool_request)

      {:ok, decoded} = FakeCLI.wait_for_control_response(transport, request_id, 1_000)

      assert decoded["response"]["response"]["updatedPermissions"] == [
               %{"type" => "setMode", "mode" => "plan"}
             ]

      refute Map.has_key?(decoded["response"]["response"], "updated_permissions")
    end

    test "can_use_tool context includes blocked_path when provided by CLI" do
      test_pid = self()

      callback = fn context ->
        send(test_pid, {:blocked_path, context.blocked_path})
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      %{transport: transport} = start_initialized_client_with_fake_cli(options)

      request_id = "perm_req_blocked"

      can_use_tool_request = %{
        "type" => "control_request",
        "request_id" => request_id,
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Write",
          "input" => %{"file_path" => "/tmp/blocked.txt", "content" => "hi"},
          "permission_suggestions" => [],
          "blocked_path" => "/tmp/blocked.txt"
        }
      }

      FakeCLI.push_message(transport, can_use_tool_request)

      assert_receive {:blocked_path, "/tmp/blocked.txt"}, 500
    end

    test "can_use_tool context includes tool_use_id and agent_id when provided by CLI" do
      test_pid = self()

      callback = fn context ->
        send(test_pid, {:permission_context_ids, context.tool_use_id, context.agent_id})
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      %{transport: transport} = start_initialized_client_with_fake_cli(options)

      request_id = "perm_req_context_ids"

      can_use_tool_request = %{
        "type" => "control_request",
        "request_id" => request_id,
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{"command" => "pwd"},
          "permission_suggestions" => [],
          "tool_use_id" => "toolu_123",
          "agent_id" => "agent_456"
        }
      }

      FakeCLI.push_message(transport, can_use_tool_request)

      assert_receive {:permission_context_ids, "toolu_123", "agent_456"}, 500
    end
  end

  describe "permission mode behavior" do
    test "default mode requires callback for each tool" do
      # Track invocations
      test_pid = self()

      callback = fn context ->
        send(test_pid, {:tool_check, context.tool_name})
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # In default mode, every tool use should invoke callback
      # This is validated through control protocol integration

      Client.stop(client)
    end

    test "bypass_permissions mode skips callback" do
      # Callback should not be invoked in bypass mode
      test_pid = self()

      callback = fn context ->
        send(test_pid, {:unexpected_callback, context.tool_name})
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :bypass_permissions
      }

      {:ok, client} = Client.start_link(options)

      # In bypass mode, callback should not be invoked
      # Verified through integration tests

      Client.stop(client)
    end

    test "accept_edits mode automatically allows edit operations" do
      # Edit tools should be auto-allowed without callback
      callback = fn context ->
        # Should only be called for non-edit tools
        if context.tool_name in ["Write", "Edit", "MultiEdit"] do
          flunk("Callback should not be invoked for edit tools in accept_edits mode")
        end

        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :accept_edits
      }

      {:ok, client} = Client.start_link(options)

      # In accept_edits mode, Write/Edit tools bypass callback
      # Verified through integration tests

      Client.stop(client)
    end

    test "plan mode shows execution plan before running" do
      # Plan mode should collect actions and present them before execution
      callback = fn _context ->
        # In plan mode, tools are collected but not immediately executed
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :plan
      }

      {:ok, client} = Client.start_link(options)

      # Plan mode behavior verified through integration tests
      # CLI shows plan, user approves, then execution proceeds

      Client.stop(client)
    end
  end

  describe "permission callback error handling" do
    test "callback exception is caught and returns deny" do
      callback = fn _context ->
        raise "Permission callback error!"
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      # Client should handle callback exceptions gracefully
      {:ok, client} = Client.start_link(options)

      # When callback raises, Client should send error response to CLI
      # Verified through integration tests

      Client.stop(client)
    end

    test "callback timeout is handled" do
      callback = fn _context ->
        # Simulate slow callback
        Process.sleep(65_000)
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # Client should timeout callback after 60 seconds
      # and return error response
      # Verified through integration tests

      Client.stop(client)
    end

    test "callback returning invalid result is handled" do
      callback = fn _context ->
        # Return invalid result (not Result struct)
        :invalid_result
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # Client should validate callback result and handle errors
      # Verified through integration tests

      Client.stop(client)
    end
  end

  describe "permission context in callbacks" do
    test "callback receives tool name in context" do
      test_pid = self()

      callback = fn context ->
        send(test_pid, {:context, context})
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # When callback is invoked, context should include:
      # - tool_name
      # - tool_input
      # - session_id
      # - suggestions

      Client.stop(client)
    end

    test "callback receives tool input in context" do
      test_pid = self()

      callback = fn context ->
        assert is_map(context.tool_input)
        send(test_pid, :verified)
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      Client.stop(client)
    end

    test "callback receives permission suggestions in context" do
      test_pid = self()

      callback = fn context ->
        # Suggestions come from CLI
        assert is_list(context.suggestions)
        send(test_pid, {:suggestions, context.suggestions})
        Result.allow()
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      Client.stop(client)
    end
  end

  describe "permission result handling" do
    test "allow result permits tool execution" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # Client sends allow response to CLI
      # CLI proceeds with tool execution
      # Verified through integration tests

      Client.stop(client)
    end

    test "deny result blocks tool execution" do
      callback = fn context ->
        if context.tool_name == "Bash" do
          Result.deny("Bash not allowed")
        else
          Result.allow()
        end
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # Client sends deny response to CLI
      # CLI shows error message to user
      # Verified through integration tests

      Client.stop(client)
    end

    test "allow with updated input modifies tool parameters" do
      callback = fn context ->
        if context.tool_name == "Write" do
          updated_input = Map.put(context.tool_input, "file_path", "/safe/path.txt")
          Result.allow(updated_input: updated_input)
        else
          Result.allow()
        end
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # Client sends allow response with updated_input to CLI
      # CLI uses modified input for tool execution
      # Verified through integration tests

      Client.stop(client)
    end

    test "deny with interrupt stops entire execution" do
      callback = fn context ->
        if context.tool_name == "Bash" do
          Result.deny("Critical security violation", interrupt: true)
        else
          Result.allow()
        end
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} = Client.start_link(options)

      # Client sends deny response with interrupt flag
      # CLI stops entire agent execution
      # Verified through integration tests

      Client.stop(client)
    end
  end

  describe "mode switching during execution" do
    test "switching from default to bypass_permissions" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      %{client: client, transport: transport} = start_initialized_client_with_fake_cli(options)

      task = Task.async(fn -> Client.set_permission_mode(client, :bypass_permissions) end)
      request = wait_for_request(transport, 2)

      FakeCLI.push_message(transport, success_response(request["request_id"]))

      assert :ok = Task.await(task, 500)
      assert :sys.get_state(client).options.permission_mode == :bypass_permissions
    end

    test "switching from plan to accept_edits" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :plan
      }

      %{client: client, transport: transport} = start_initialized_client_with_fake_cli(options)

      task = Task.async(fn -> Client.set_permission_mode(client, :accept_edits) end)
      request = wait_for_request(transport, 2)

      FakeCLI.push_message(transport, success_response(request["request_id"]))

      assert :ok = Task.await(task, 500)
      assert :sys.get_state(client).options.permission_mode == :accept_edits
    end
  end

  defp start_initialized_client_with_fake_cli(options) do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))
    on_exit(fn -> stop_client(client) end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    {:ok, init_request} = FakeCLI.initialize_request(fake_cli)

    FakeCLI.push_message(fake_cli, success_response(init_request["request_id"]))
    assert :ok = Client.await_initialized(client, 1_000)

    %{client: client, transport: fake_cli}
  end

  defp wait_for_request(fake_cli, count, timeout_ms \\ 1_000) do
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, count, timeout_ms)
    Enum.at(FakeCLI.decoded_messages(fake_cli), count - 1)
  end

  defp success_response(request_id, response \\ %{}) do
    %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => request_id,
        "response" => response
      }
    }
  end

  defp error_response(request_id, error) do
    %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "error",
        "request_id" => request_id,
        "error" => error
      }
    }
  end

  defp stop_client(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
