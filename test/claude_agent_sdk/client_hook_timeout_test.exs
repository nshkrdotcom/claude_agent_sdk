defmodule ClaudeAgentSDK.ClientHookTimeoutTest do
  use ClaudeAgentSDK.SupertesterCase
  @moduletag capture_log: true

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output, Registry}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

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

    {client, transport} = start_client_with_fake_cli(options)

    [init_request] = FakeCLI.decoded_messages(transport)

    state = :sys.get_state(client)
    callback_id = Registry.get_id(state.registry, callback)
    [matcher_config] = init_request["request"]["hooks"]["PreToolUse"]

    assert matcher_config["timeout"] == 1.0
    assert matcher_config["matcher"] == "Bash"
    assert matcher_config["hookCallbackIds"] == [callback_id]

    # Ensure the transport captured the same payload for later assertions
    recorded =
      transport
      |> FakeCLI.decoded_messages()

    assert Enum.any?(recorded, fn msg ->
             msg["request"]["hooks"]["PreToolUse"]
             |> List.first()
             |> Map.get("timeout") == 1.0
           end)
  end

  # Intentionally slow: tests timeout behavior with 1.3s sleep
  @tag :slow
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

    {client, transport} = start_client_with_fake_cli(options)

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

  # Intentionally slow: tests 1s timeout floor with 1.2s sleep
  @tag :slow
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

    {client, transport} = start_client_with_fake_cli(options)

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

    {client, _transport} = start_client_with_fake_cli(options)

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

    FakeCLI.push_message(transport, request)
  end

  defp find_response(transport, request_id) do
    case FakeCLI.wait_for_control_response(transport, request_id, 0) do
      {:ok, response} -> response
      {:error, :timeout} -> nil
    end
  end

  defp start_client_with_fake_cli(options) do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))
    on_exit(fn -> safe_stop(client) end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, 1, 1_000)

    {client, fake_cli}
  end

  defp safe_stop(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
