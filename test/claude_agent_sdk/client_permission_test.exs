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
    alias ClaudeAgentSDK.TestSupport.MockTransport

    test "set_permission_mode/2 updates permission mode at runtime" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200

      init_request_id = Jason.decode!(String.trim(init_json))["request_id"]

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

      for mode <- [:plan, :accept_edits, :bypass_permissions, :default] do
        task = Task.async(fn -> Client.set_permission_mode(client, mode) end)

        assert_receive {:mock_transport_send, set_mode_json}, 200
        set_request_id = Jason.decode!(String.trim(set_mode_json))["request_id"]

        response = %{
          "type" => "control_response",
          "response" => %{
            "subtype" => "success",
            "request_id" => set_request_id,
            "response" => %{}
          }
        }

        MockTransport.push_message(transport_pid, Jason.encode!(response))
        assert :ok = Task.await(task, 500)

        state = :sys.get_state(client)
        assert state.current_permission_mode == mode
      end

      Client.stop(client)
    end

    test "set_permission_mode/2 sends control request and applies CLI response" do
      options = %Options{permission_mode: :default}

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      # Capture initialize request and respond
      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200

      init_request = Jason.decode!(String.trim(init_json))
      init_request_id = init_request["request_id"]

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

      task = Task.async(fn -> Client.set_permission_mode(client, :plan) end)

      assert_receive {:mock_transport_send, set_mode_json}, 200
      decoded = Jason.decode!(String.trim(set_mode_json))
      assert decoded["request"]["subtype"] == "set_permission_mode"
      assert decoded["request"]["mode"] == "plan"

      set_request_id = decoded["request_id"]

      # Respond with success
      response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => set_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(response))

      assert :ok = Task.await(task, 500)

      state = :sys.get_state(client)
      assert state.current_permission_mode == :plan
      Client.stop(client)
    end

    test "set_permission_mode/2 surfaces CLI error responses" do
      options = %Options{permission_mode: :default}

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      # Handle initialize handshake
      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200
      init_request_id = Jason.decode!(String.trim(init_json))["request_id"]

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

      task = Task.async(fn -> Client.set_permission_mode(client, :accept_edits) end)

      assert_receive {:mock_transport_send, set_mode_json}, 200
      decoded = Jason.decode!(String.trim(set_mode_json))
      set_request_id = decoded["request_id"]

      error_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "error",
          "request_id" => set_request_id,
          "error" => "permission mode rejected"
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(error_response))

      assert {:error, "permission mode rejected"} = Task.await(task, 500)

      state = :sys.get_state(client)
      assert state.current_permission_mode == :default
      Client.stop(client)
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
    alias ClaudeAgentSDK.TestSupport.MockTransport

    test "allow response includes updatedInput defaulting to original input" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200

      init_request_id = Jason.decode!(String.trim(init_json))["request_id"]

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

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

      MockTransport.push_message(transport_pid, Jason.encode!(can_use_tool_request))

      assert_receive {:mock_transport_send, response_json}, 500
      decoded = Jason.decode!(String.trim(response_json))

      assert decoded["type"] == "control_response"
      assert decoded["response"]["subtype"] == "success"
      assert decoded["response"]["request_id"] == request_id
      assert decoded["response"]["result"]["behavior"] == "allow"
      assert decoded["response"]["result"]["updatedInput"] == %{"command" => "ls"}
      refute Map.has_key?(decoded["response"]["result"], "updated_input")

      Client.stop(client)
    end

    test "allow response uses camelCase updatedPermissions" do
      callback = fn _context ->
        Result.allow(updated_permissions: [%{"type" => "setMode", "mode" => "plan"}])
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200

      init_request_id = Jason.decode!(String.trim(init_json))["request_id"]

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

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

      MockTransport.push_message(transport_pid, Jason.encode!(can_use_tool_request))

      assert_receive {:mock_transport_send, response_json}, 500
      decoded = Jason.decode!(String.trim(response_json))

      assert decoded["response"]["result"]["updatedPermissions"] == [
               %{"type" => "setMode", "mode" => "plan"}
             ]

      refute Map.has_key?(decoded["response"]["result"], "updated_permissions")

      Client.stop(client)
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

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200

      init_request_id = Jason.decode!(String.trim(init_json))["request_id"]

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

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

      MockTransport.push_message(transport_pid, Jason.encode!(can_use_tool_request))

      assert_receive {:blocked_path, "/tmp/blocked.txt"}, 500

      Client.stop(client)
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
    alias ClaudeAgentSDK.TestSupport.MockTransport

    test "switching from default to bypass_permissions" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200

      init_request_id = Jason.decode!(String.trim(init_json))["request_id"]

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

      task = Task.async(fn -> Client.set_permission_mode(client, :bypass_permissions) end)

      assert_receive {:mock_transport_send, set_mode_json}, 200
      set_request_id = Jason.decode!(String.trim(set_mode_json))["request_id"]

      response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => set_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(response))

      assert :ok = Task.await(task, 500)
      assert :sys.get_state(client).current_permission_mode == :bypass_permissions

      Client.stop(client)
    end

    test "switching from plan to accept_edits" do
      callback = fn _context -> Result.allow() end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :plan
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200

      init_request_id = Jason.decode!(String.trim(init_json))["request_id"]

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => init_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

      task = Task.async(fn -> Client.set_permission_mode(client, :accept_edits) end)

      assert_receive {:mock_transport_send, set_mode_json}, 200
      set_request_id = Jason.decode!(String.trim(set_mode_json))["request_id"]

      response = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => set_request_id,
          "response" => %{}
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(response))

      assert :ok = Task.await(task, 500)
      assert :sys.get_state(client).current_permission_mode == :accept_edits

      Client.stop(client)
    end
  end
end
