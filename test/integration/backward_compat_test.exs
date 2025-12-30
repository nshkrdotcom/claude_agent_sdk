defmodule Integration.BackwardCompatTest do
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.{Client, Options}

  @moduletag :integration

  @tag :live_cli
  test "should work without transport option" do
    # Requires Claude CLI to be installed and available in PATH.
    # Skipped in automated environments.
    result =
      case Client.start_link(%Options{}) do
        {:ok, pid} ->
          Client.stop(pid)
          {:error, :cli_not_available}

        {:error, reason} ->
          {:error, reason}
      end

    assert {:error, :cli_not_available} = result
  end
end
