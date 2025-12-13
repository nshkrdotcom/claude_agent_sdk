defmodule Integration.LiveSmokeTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Options

  @moduletag :integration
  @moduletag :live

  test "ClaudeAgentSDK.query/2 succeeds end-to-end" do
    messages =
      ClaudeAgentSDK.query(
        "Say exactly: live smoke ok",
        %Options{max_turns: 1, output_format: :stream_json}
      )
      |> Enum.to_list()

    assert Enum.any?(messages, &(&1.type == :assistant))
    assert Enum.any?(messages, &match?(%{type: :result, subtype: :success}, &1))
  end
end
