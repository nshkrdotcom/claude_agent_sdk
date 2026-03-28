defmodule ClaudeAgentSDK.ClientPermissionValidationTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "rejects permission_prompt_tool when can_use_tool is set" do
    Process.flag(:trap_exit, true)

    options = %Options{
      can_use_tool: fn _ -> :ok end,
      permission_prompt_tool: "bash"
    }

    assert {:error, {:validation_failed, :permission_prompt_tool_conflict}} =
             Client.start_link(options)
  end

  test "auto-sets permission_prompt_tool when can_use_tool is set" do
    options = %Options{can_use_tool: fn _ -> :ok end}
    fake_cli = FakeCLI.new!()

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, options))

    on_exit(fn ->
      try do
        Client.stop(client)
      catch
        :exit, _ -> :ok
      end

      FakeCLI.cleanup(fake_cli)
    end)

    state = :sys.get_state(client)
    assert state.options.permission_prompt_tool == "stdio"
    assert state.options.permission_mode == nil
    assert state.options.include_partial_messages == true
  end
end
