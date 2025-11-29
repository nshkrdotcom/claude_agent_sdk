defmodule ClaudeAgentSDK.ClientHookTimeoutTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output, Registry}
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

  test "sends matcher timeout metadata during initialize handshake" do
    callback = fn _, _, _ -> Output.allow() end

    options = %Options{
      hooks: %{
        pre_tool_use: [
          Matcher.new("Bash", [callback], timeout_ms: 10)
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

    init_request =
      receive do
        {:mock_transport_send, json} -> Jason.decode!(json)
      after
        500 -> flunk("Did not receive initialize payload")
      end

    state = :sys.get_state(client)
    callback_id = Registry.get_id(state.registry, callback)
    [matcher_config] = init_request["request"]["hooks"]["PreToolUse"]

    assert matcher_config["timeout"] == 1_000
    assert matcher_config["matcher"] == "Bash"
    assert matcher_config["hookCallbackIds"] == [callback_id]

    # Ensure the transport captured the same payload for later assertions
    recorded =
      transport
      |> MockTransport.recorded_messages()
      |> Enum.map(&Jason.decode!/1)

    assert Enum.any?(recorded, fn msg ->
             msg["request"]["hooks"]["PreToolUse"]
             |> List.first()
             |> Map.get("timeout") == 1_000
           end)
  end

  test "uses matcher-specific timeout when executing hook callbacks" do
    callback = fn _input, _tool_use_id, _context ->
      Process.sleep(1_300)
      Output.allow()
    end

    options = %Options{
      hooks: %{
        pre_tool_use: [
          Matcher.new("Bash", [callback], timeout_ms: 1_100)
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

    state = :sys.get_state(client)
    callback_id = Registry.get_id(state.registry, callback)
    request_id = "req_hook_timeout"

    send_hook_request(transport, callback_id, request_id)

    response =
      SupertesterCase.eventually(
        fn ->
          find_response(transport, request_id)
        end,
        timeout: 2_500
      )

    assert response["response"]["subtype"] == "error"
    assert response["response"]["error"] =~ "Hook callback timeout"
    assert response["response"]["error"] =~ "1.1"
  end

  test "applies floor for extremely small matcher timeout values" do
    callback = fn _input, _tool_use_id, _context ->
      Process.sleep(1_200)
      Output.allow()
    end

    options = %Options{
      hooks: %{
        pre_tool_use: [
          Matcher.new("Bash", [callback], timeout_ms: 10)
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

    state = :sys.get_state(client)
    callback_id = Registry.get_id(state.registry, callback)
    request_id = "req_hook_timeout_floor"

    send_hook_request(transport, callback_id, request_id)

    response =
      SupertesterCase.eventually(
        fn ->
          find_response(transport, request_id)
        end,
        timeout: 2_500
      )

    assert response["response"]["subtype"] == "error"
    assert response["response"]["error"] =~ "Hook callback timeout"
    assert response["response"]["error"] =~ "1s"
  end

  test "defaults to 60s timeout when matcher timeout is not set" do
    callback = fn _, _, _ -> Output.allow() end

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

    receive do
      {:mock_transport_started, _} -> :ok
    end

    state = :sys.get_state(client)
    callback_id = Registry.get_id(state.registry, callback)

    assert state.hook_callback_timeouts[callback_id] == 60_000
  end

  defp send_hook_request(transport, callback_id, request_id) do
    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "hook_callback",
        "callback_id" => callback_id,
        "input" => @hook_input,
        "tool_use_id" => "tool_use_1"
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

  defp safe_stop(client) do
    try do
      Client.stop(client)
    catch
      :exit, _ -> :ok
    end
  end
end
