defmodule ClaudeAgentSDK.Options.ModelInputTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Config.Env
  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.TestEnvHelpers

  test "treats an explicit model_payload as authoritative" do
    payload = resolved_payload!("sonnet")

    opts = Options.new(model_payload: payload, model: "sonnet")

    assert opts.model_payload == payload
    assert opts.model == "sonnet"
  end

  test "does not treat env defaults as active config when model_payload is explicit" do
    TestEnvHelpers.with_system_env(
      [
        {Env.provider_backend(), "ollama"},
        {Env.anthropic_model(), "opus"}
      ],
      fn ->
        payload = resolved_payload!("sonnet")
        opts = Options.new(model_payload: payload)

        assert opts.model_payload == payload
        assert opts.model == "sonnet"
      end
    )
  end

  test "raises when raw attrs conflict with an explicit model_payload" do
    payload = resolved_payload!("sonnet")

    assert_raise ArgumentError, ~r/model_payload_conflict/, fn ->
      Options.new(model_payload: payload, model: "opus")
    end
  end

  defp resolved_payload!(model) do
    {:ok, payload} = CliSubprocessCore.ModelRegistry.build_arg_payload(:claude, model, [])
    payload
  end
end
