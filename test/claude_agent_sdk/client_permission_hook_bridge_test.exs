defmodule ClaudeAgentSDK.ClientPermissionHookBridgeTest do
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Permission.Result
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  test "invokes permission callback via PreToolUse hook when can_use_tool is missing" do
    test_pid = self()

    callback = fn context ->
      send(test_pid, {:permission_callback, context.tool_name, context.tool_input})
      Result.allow(updated_input: Map.put(context.tool_input, "extra", "ok"))
    end

    options = %Options{can_use_tool: callback, permission_mode: :default}

    %{client: client, transport: transport, init_request: init_request} =
      start_client_with_fake_cli(options)

    on_exit(fn -> stop_client(client) end)

    callback_id = hook_callback_id(init_request)

    send_pre_tool_use_hook(
      transport,
      callback_id,
      "req_hook_1",
      "Write",
      %{"file_path" => "/tmp/permission_test.txt"}
    )

    assert_receive {:permission_callback, "Write", %{"file_path" => "/tmp/permission_test.txt"}},
                   1_000

    response =
      ClaudeAgentSDK.SupertesterCase.eventually(
        fn -> find_control_response(transport, "req_hook_1") end,
        timeout: 1_000
      )

    hook_output = response["response"]["response"]["hookSpecificOutput"]
    assert hook_output["permissionDecision"] == "allow"
    assert hook_output["updatedInput"]["extra"] == "ok"
  end

  test "skips hook callback after can_use_tool request is seen" do
    test_pid = self()

    callback = fn context ->
      send(test_pid, {:permission_callback, context.tool_name})
      Result.allow()
    end

    options = %Options{can_use_tool: callback, permission_mode: :default}

    %{client: client, transport: transport, init_request: init_request} =
      start_client_with_fake_cli(options)

    on_exit(fn -> stop_client(client) end)

    callback_id = hook_callback_id(init_request)

    send_can_use_tool_request(transport, "req_perm_1", "Write", %{"file_path" => "/tmp/foo"})

    assert_receive {:permission_callback, "Write"}, 1_000

    send_pre_tool_use_hook(transport, callback_id, "req_hook_2", "Write", %{
      "file_path" => "/tmp/foo"
    })

    refute_receive {:permission_callback, "Write"}, 200

    response =
      ClaudeAgentSDK.SupertesterCase.eventually(
        fn -> find_control_response(transport, "req_hook_2") end,
        timeout: 1_000
      )

    hook_output = response["response"]["response"]["hookSpecificOutput"]
    assert hook_output["permissionDecision"] == "allow"
  end

  test "respects bypass_permissions when using hook fallback" do
    test_pid = self()

    callback = fn _context ->
      send(test_pid, :permission_callback)
      Result.allow()
    end

    options = %Options{can_use_tool: callback, permission_mode: :bypass_permissions}

    %{client: client, transport: transport, init_request: init_request} =
      start_client_with_fake_cli(options)

    on_exit(fn -> stop_client(client) end)

    callback_id = hook_callback_id(init_request)

    send_pre_tool_use_hook(transport, callback_id, "req_hook_3", "Write", %{
      "file_path" => "/tmp/foo"
    })

    refute_receive :permission_callback, 200

    response =
      ClaudeAgentSDK.SupertesterCase.eventually(
        fn -> find_control_response(transport, "req_hook_3") end,
        timeout: 1_000
      )

    hook_output = response["response"]["response"]["hookSpecificOutput"]
    assert hook_output["permissionDecision"] == "allow"
  end

  defp start_client_with_fake_cli(options) do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    {:ok, init_request} = FakeCLI.initialize_request(fake_cli)

    init_response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => init_request["request_id"],
        "response" => %{}
      }
    }

    FakeCLI.push_message(fake_cli, init_response)

    %{client: client, transport: fake_cli, init_request: init_request}
  end

  defp hook_callback_id(init_request) do
    init_request
    |> get_in(["request", "hooks", "PreToolUse"])
    |> List.first()
    |> Map.fetch!("hookCallbackIds")
    |> List.first()
  end

  defp send_pre_tool_use_hook(transport, callback_id, request_id, tool_name, tool_input) do
    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "hook_callback",
        "callback_id" => callback_id,
        "input" => %{
          "hook_event_name" => "PreToolUse",
          "tool_name" => tool_name,
          "tool_input" => tool_input,
          "session_id" => "session_1",
          "transcript_path" => "/tmp/claude.json",
          "cwd" => "/tmp"
        },
        "tool_use_id" => "tool_use_1"
      }
    }

    FakeCLI.push_message(transport, request)
  end

  defp send_can_use_tool_request(transport, request_id, tool_name, tool_input) do
    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "can_use_tool",
        "tool_name" => tool_name,
        "input" => tool_input,
        "permission_suggestions" => []
      }
    }

    FakeCLI.push_message(transport, request)
  end

  defp find_control_response(transport, request_id) do
    case FakeCLI.wait_for_control_response(transport, request_id, 0) do
      {:ok, response} -> response
      {:error, :timeout} -> nil
    end
  end

  defp stop_client(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
