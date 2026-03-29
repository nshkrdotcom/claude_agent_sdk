defmodule ClaudeAgentSDK.LiveSSHTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Options
  alias CliSubprocessCore.TestSupport.LiveSSH

  @moduletag :live_ssh
  @moduletag timeout: 120_000

  @live_ssh_enabled LiveSSH.enabled?()

  if not @live_ssh_enabled do
    @moduletag skip: LiveSSH.skip_reason()
  end

  setup_all do
    runnable? = LiveSSH.runnable?("claude-code") or LiveSSH.runnable?("claude")

    {:ok,
     skip: not runnable?,
     skip_reason:
       "Remote SSH target #{inspect(LiveSSH.destination())} does not have a runnable Claude CLI."}
  end

  test "live SSH: ClaudeAgentSDK.query/2 runs against the remote Claude CLI", %{
    skip: skip?,
    skip_reason: skip_reason
  } do
    if skip? do
      assert is_binary(skip_reason)
    else
      messages =
        ClaudeAgentSDK.query(
          "Say exactly: CLAUDE_LIVE_SSH_OK",
          %Options{
            execution_surface: LiveSSH.execution_surface(),
            max_turns: 1,
            output_format: :stream_json
          }
        )
        |> Enum.to_list()

      assert Enum.any?(messages, &(&1.type == :assistant))
      assert Enum.any?(messages, &match?(%{type: :result, subtype: :success}, &1))
    end
  end
end
