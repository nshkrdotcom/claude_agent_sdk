defmodule ClaudeAgentSDK.ClientCancelTest do
  use ClaudeAgentSDK.SupertesterCase, isolation: :full_isolation
  @moduletag capture_log: true

  alias ClaudeAgentSDK.{AbortSignal, Permission}
  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output, Registry}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  test "control_cancel_request cancels hook callbacks and sets abort signal" do
    parent = self()

    callback = fn _input, _tool_use_id, %{signal: signal} ->
      send(parent, {:hook_signal, signal})
      # Block until cancelled so the cancel request has an effect
      SupertesterCase.eventually(fn -> AbortSignal.cancelled?(signal) end, timeout: 2_000)
      Output.allow()
    end

    options = %Options{
      hooks: %{
        user_prompt_submit: [
          Matcher.new(nil, [callback])
        ]
      }
    }

    {client, transport} = start_client_with_fake_cli(options)

    state = :sys.get_state(client)
    callback_id = Registry.get_id(state.registry, callback)
    request_id = "req_hook_cancel"

    send_hook_request(transport, callback_id, request_id)

    signal =
      receive do
        {:hook_signal, sig} -> sig
      after
        2_000 -> flunk("Hook callback did not start")
      end

    refute AbortSignal.cancelled?(signal)

    send_cancel_request(transport, request_id)

    SupertesterCase.eventually(fn -> AbortSignal.cancelled?(signal) end, timeout: 2_000)

    response = find_control_response(transport, request_id)
    assert response["response"]["subtype"] == "error"
    assert String.contains?(response["response"]["error"], "cancelled")
  end

  test "control_cancel_request cancels permission callbacks and propagates abort signal" do
    parent = self()

    permission_callback = fn context ->
      send(parent, {:permission_signal, context.signal})
      SupertesterCase.eventually(fn -> AbortSignal.cancelled?(context.signal) end, timeout: 2_000)
      Permission.Result.allow()
    end

    options = %Options{
      can_use_tool: permission_callback
    }

    {client, transport} = start_client_with_fake_cli(options)

    # Ensure subscription is complete by making a synchronous call to the client
    _ = :sys.get_state(client)

    request_id = "req_permission_cancel"
    send_permission_request(transport, request_id)

    signal =
      SupertesterCase.eventually(
        fn ->
          state = :sys.get_state(client)

          case Map.get(state.pending_callbacks, request_id) do
            %{signal: sig} -> sig
            _ -> nil
          end
        end,
        timeout: 5_000
      )

    send_cancel_request(transport, request_id)

    SupertesterCase.eventually(fn -> AbortSignal.cancelled?(signal) end, timeout: 2_000)

    response = find_control_response(transport, request_id)
    assert response["response"]["subtype"] == "error"
    assert String.contains?(response["response"]["error"], "cancelled")
  end

  defp send_hook_request(transport, callback_id, request_id) do
    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "hook_callback",
        "callback_id" => callback_id,
        "input" => %{"hook_event_name" => "UserPromptSubmit"},
        "tool_use_id" => nil
      }
    }

    FakeCLI.push_message(transport, request)
  end

  defp send_permission_request(transport, request_id) do
    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "can_use_tool",
        "tool_name" => "Bash",
        "input" => %{},
        "permission_suggestions" => []
      }
    }

    FakeCLI.push_message(transport, request)
  end

  defp send_cancel_request(transport, request_id) do
    cancel = %{
      "type" => "control_cancel_request",
      "request_id" => request_id
    }

    FakeCLI.push_message(transport, cancel)
  end

  defp find_control_response(transport, request_id) do
    SupertesterCase.eventually(fn ->
      case FakeCLI.wait_for_control_response(transport, request_id, 0) do
        {:ok, response} -> response
        {:error, :timeout} -> nil
      end
    end)
  end

  defp start_client_with_fake_cli(options) do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))
    on_exit(fn -> safe_stop(client) end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    _request_id = FakeCLI.respond_initialize_success!(fake_cli)
    assert :ok = Client.await_initialized(client, 1_000)

    {client, fake_cli}
  end

  defp safe_stop(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
