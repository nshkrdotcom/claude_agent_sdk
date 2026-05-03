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

    error =
      assert_raise ArgumentError, fn ->
        Options.new(model_payload: payload, model: "opus")
      end

    assert Exception.message(error) =~ "model_payload_conflict"
  end

  test "normalizes unsupported provider backend strings without creating atoms" do
    error =
      assert_raise ArgumentError, fn ->
        Options.new(model: "sonnet", provider_backend: "Experimental_Backend")
      end

    assert String.contains?(String.downcase(Exception.message(error)), "provider_backend")
  end

  test "normalizes provider backend env strings without creating atoms" do
    TestEnvHelpers.with_system_env([{Env.provider_backend(), "Experimental_Backend"}], fn ->
      error =
        assert_raise ArgumentError, fn ->
          Options.new(model: "sonnet")
          |> Options.to_args()
        end

      assert String.contains?(String.downcase(Exception.message(error)), "provider_backend")
    end)
  end

  test "rejects unsupported output format enums without pattern assertions" do
    error =
      assert_raise ArgumentError, fn ->
        %Options{output_format: :xml}
        |> Options.to_args()
      end

    assert Exception.message(error) =~ "Unsupported output_format"
  end

  defp resolved_payload!(model) do
    {:ok, payload} = CliSubprocessCore.ModelRegistry.build_arg_payload(:claude, model, [])
    payload
  end
end
