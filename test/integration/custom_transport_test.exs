defmodule Integration.CustomTransportTest do
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.{Client, Options}

  test "rejects removed custom transport injection" do
    assert {:error,
            {:validation_failed,
             {:unsupported_runtime_override, :transport,
              "custom transport injection has been removed; use execution_surface instead"}}} =
             Client.start_link(%Options{}, transport: :legacy_transport)
  end
end
