defmodule ClaudeAgentSDK.ClientPermissionValidationTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  test "rejects permission_prompt_tool when can_use_tool is set" do
    Process.flag(:trap_exit, true)

    options = %Options{
      can_use_tool: fn _ -> :ok end,
      permission_prompt_tool: "bash"
    }

    assert {:error, {:validation_failed, :permission_prompt_tool_conflict}} =
             Client.start_link(options,
               transport: MockTransport,
               transport_opts: [test_pid: self()]
             )
  end

  test "auto-sets permission_prompt_tool when can_use_tool is set" do
    options = %Options{can_use_tool: fn _ -> :ok end}

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end
    end)

    state = :sys.get_state(client)
    assert state.options.permission_prompt_tool == "stdio"
    assert state.options.permission_mode == nil
    assert state.options.include_partial_messages == true
  end
end
