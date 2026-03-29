defmodule ClaudeAgentSDK.LiveSSHTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Message, Options}
  alias CliSubprocessCore.TestSupport.LiveSSH

  @moduletag :live_ssh
  @moduletag timeout: 120_000

  @live_ssh_enabled LiveSSH.enabled?()

  if not @live_ssh_enabled do
    @moduletag skip: LiveSSH.skip_reason()
  end

  test "live SSH: ClaudeAgentSDK.query/2 returns a success result or a normalized error result" do
    messages =
      ClaudeAgentSDK.query(
        "Say exactly: CLAUDE_LIVE_SSH_OK",
        %Options{
          execution_surface: LiveSSH.execution_surface(),
          max_turns: 1,
          output_format: :stream_json,
          executable: LiveSSH.provider_command(:claude) || "claude"
        }
      )
      |> Enum.to_list()

    assert Enum.any?(messages, &(&1.type == :result))

    result = Enum.find(messages, &(&1.type == :result))

    if Message.error?(result) do
      error_text =
        result.data[:error] ||
          result.data[:result] ||
          get_in(result.data, [:error_details, :stderr]) ||
          ""

      assert error_text =~ "login" or error_text =~ "access" or error_text =~ "not found"
    else
      assert result.subtype == :success
      refute result.data.is_error
      assert Enum.any?(messages, &(&1.type == :assistant))
    end
  end
end
