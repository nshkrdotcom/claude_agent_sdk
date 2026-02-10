defmodule ClaudeAgentSDK.TransportReasonTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Transport

  test "normalizes legacy transport reason aliases" do
    assert Transport.normalize_reason({:command_not_found, "claude"}) == :cli_not_found
    assert Transport.normalize_reason(:send_failed) == :send_failed
  end
end
