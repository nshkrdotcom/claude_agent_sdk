defmodule ClaudeAgentSDK.ClientCallbackCrashTest do
  @moduledoc """
  Tests for OTP supervision compliance: callback task crash handling.

  These tests verify that when callback tasks crash, the Client:
  1. Detects the crash via Process.monitor
  2. Sends an error response to the CLI
  3. Cleans up pending_callbacks map
  4. Continues operating normally
  """

  use ClaudeAgentSDK.SupertesterCase
  @moduletag capture_log: true

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Hooks.{Matcher, Registry}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  @hook_input %{
    "hook_event_name" => "PreToolUse",
    "tool_name" => "Bash",
    "tool_input" => %{}
  }

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  describe "hook callback crash handling" do
    test "sends error response when hook callback crashes with raise" do
      # Callback that will crash
      callback = fn _input, _tool_use_id, _context ->
        raise "intentional crash for testing"
      end

      options = %Options{
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [callback])
          ]
        }
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      transport =
        receive do
          {:mock_transport_started, pid} -> pid
        end

      # Wait for init message
      receive do
        {:mock_transport_send, _} -> :ok
      after
        500 -> flunk("Did not receive initialize payload")
      end

      state = :sys.get_state(client)
      callback_id = Registry.get_id(state.registry, callback)
      request_id = "req_crash_test"

      send_hook_request(transport, callback_id, request_id)

      # Wait for error response
      response =
        SupertesterCase.eventually(
          fn ->
            find_response(transport, request_id)
          end,
          timeout: 2_000
        )

      assert response["response"]["subtype"] == "error"
      assert response["response"]["error"] =~ "intentional crash for testing"

      # Verify pending_callbacks is cleaned up
      state = :sys.get_state(client)
      assert state.pending_callbacks == %{}
    end

    test "sends error response when hook callback crashes with exit" do
      callback = fn _input, _tool_use_id, _context ->
        exit(:intentional_exit)
      end

      options = %Options{
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [callback])
          ]
        }
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      transport =
        receive do
          {:mock_transport_started, pid} -> pid
        end

      receive do
        {:mock_transport_send, _} -> :ok
      after
        500 -> flunk("Did not receive initialize payload")
      end

      state = :sys.get_state(client)
      callback_id = Registry.get_id(state.registry, callback)
      request_id = "req_exit_test"

      send_hook_request(transport, callback_id, request_id)

      response =
        SupertesterCase.eventually(
          fn ->
            find_response(transport, request_id)
          end,
          timeout: 2_000
        )

      assert response["response"]["subtype"] == "error"
      assert response["response"]["error"] =~ "crash" or response["response"]["error"] =~ "exit"

      state = :sys.get_state(client)
      assert state.pending_callbacks == %{}
    end

    test "client continues operating after callback crash" do
      crash_callback = fn _input, _tool_use_id, _context ->
        raise "boom"
      end

      normal_callback = fn _input, _tool_use_id, _context ->
        %{}
      end

      options = %Options{
        hooks: %{
          pre_tool_use: [
            Matcher.new("CrashTool", [crash_callback]),
            Matcher.new("NormalTool", [normal_callback])
          ]
        }
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      transport =
        receive do
          {:mock_transport_started, pid} -> pid
        end

      receive do
        {:mock_transport_send, _} -> :ok
      after
        500 -> flunk("Did not receive initialize payload")
      end

      state = :sys.get_state(client)
      crash_callback_id = Registry.get_id(state.registry, crash_callback)
      normal_callback_id = Registry.get_id(state.registry, normal_callback)

      # First trigger the crash
      send_hook_request(transport, crash_callback_id, "req_crash")

      SupertesterCase.eventually(
        fn ->
          find_response(transport, "req_crash")
        end,
        timeout: 2_000
      )

      # Client should still be alive
      assert Process.alive?(client)

      # Now trigger the normal callback
      send_hook_request_for_tool(transport, normal_callback_id, "req_normal", "NormalTool")

      response =
        SupertesterCase.eventually(
          fn ->
            find_response(transport, "req_normal")
          end,
          timeout: 2_000
        )

      # Normal callback should succeed
      assert response["response"]["subtype"] == "success"
    end
  end

  describe "permission callback crash handling" do
    test "sends error response when permission callback crashes" do
      callback = fn _ctx ->
        raise "permission callback crash"
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

      on_exit(fn -> safe_stop(client) end)

      transport =
        receive do
          {:mock_transport_started, pid} -> pid
        end

      receive do
        {:mock_transport_send, _} -> :ok
      after
        500 -> flunk("Did not receive initialize payload")
      end

      request_id = "req_perm_crash"
      send_permission_request(transport, request_id)

      response =
        SupertesterCase.eventually(
          fn ->
            find_permission_response(transport, request_id)
          end,
          timeout: 2_000
        )

      assert response["response"]["subtype"] == "error"

      assert response["response"]["error"] =~ "crash" or
               response["response"]["error"] =~ "permission callback"

      state = :sys.get_state(client)
      assert state.pending_callbacks == %{}
    end
  end

  describe "pending_callbacks cleanup" do
    test "monitor refs are properly cleaned up after normal callback completion" do
      callback = fn _input, _tool_use_id, _context ->
        %{}
      end

      options = %Options{
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [callback])
          ]
        }
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      transport =
        receive do
          {:mock_transport_started, pid} -> pid
        end

      receive do
        {:mock_transport_send, _} -> :ok
      after
        500 -> flunk("Did not receive initialize payload")
      end

      state = :sys.get_state(client)
      callback_id = Registry.get_id(state.registry, callback)

      # Trigger callback
      send_hook_request(transport, callback_id, "req_cleanup_test")

      SupertesterCase.eventually(
        fn ->
          find_response(transport, "req_cleanup_test")
        end,
        timeout: 2_000
      )

      # Verify cleanup
      state = :sys.get_state(client)
      assert state.pending_callbacks == %{}
    end

    test "ignores :DOWN with :normal when callback result is still pending" do
      callback = fn _input, _tool_use_id, _context ->
        Process.sleep(200)
        %{}
      end

      options = %Options{
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [callback])
          ]
        }
      }

      {:ok, client} =
        Client.start_link(options,
          transport: MockTransport,
          transport_opts: [test_pid: self()]
        )

      on_exit(fn -> safe_stop(client) end)

      transport =
        receive do
          {:mock_transport_started, pid} -> pid
        end

      receive do
        {:mock_transport_send, _} -> :ok
      after
        500 -> flunk("Did not receive initialize payload")
      end

      state = :sys.get_state(client)
      callback_id = Registry.get_id(state.registry, callback)
      request_id = "req_normal_down"

      send_hook_request(transport, callback_id, request_id)

      {monitor_ref, pid} =
        SupertesterCase.eventually(
          fn ->
            state = :sys.get_state(client)

            case state.pending_callbacks do
              %{^request_id => %{monitor_ref: ref, pid: task_pid}} -> {ref, task_pid}
              _ -> nil
            end
          end,
          timeout: 1_000
        )

      send(client, {:DOWN, monitor_ref, :process, pid, :normal})

      response =
        SupertesterCase.eventually(
          fn ->
            find_response(transport, request_id)
          end,
          timeout: 2_000
        )

      assert response["response"]["subtype"] == "success"

      state = :sys.get_state(client)
      assert state.pending_callbacks == %{}
    end
  end

  # Helper functions

  defp send_hook_request(transport, callback_id, request_id) do
    send_hook_request_for_tool(transport, callback_id, request_id, "Bash")
  end

  defp send_hook_request_for_tool(transport, callback_id, request_id, tool_name) do
    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "hook_callback",
        "callback_id" => callback_id,
        "input" => %{@hook_input | "tool_name" => tool_name},
        "tool_use_id" => "tool_use_1"
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))
  end

  defp send_permission_request(transport, request_id) do
    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "can_use_tool",
        "tool_name" => "Bash",
        "input" => %{"command" => "echo test"},
        "permission_suggestions" => []
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))
  end

  defp find_response(transport, request_id) do
    MockTransport.recorded_messages(transport)
    |> Enum.map(&Jason.decode!/1)
    |> Enum.find(fn
      %{
        "type" => "control_response",
        "response" => %{"request_id" => ^request_id}
      } ->
        true

      _ ->
        false
    end)
  end

  defp find_permission_response(transport, request_id) do
    MockTransport.recorded_messages(transport)
    |> Enum.map(&Jason.decode!/1)
    |> Enum.find(fn
      %{
        "type" => "control_response",
        "response" => %{"request_id" => ^request_id}
      } ->
        true

      _ ->
        false
    end)
  end

  defp safe_stop(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
