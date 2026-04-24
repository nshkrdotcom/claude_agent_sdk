defmodule ClaudeAgentSDK.Options.EffortTest do
  use ClaudeAgentSDK.SupertesterCase

  import ExUnit.CaptureLog

  alias ClaudeAgentSDK.Config.Env
  alias ClaudeAgentSDK.{Options, TestEnvHelpers}

  defp new_options(opts) do
    Options.new(Keyword.merge([model: "sonnet", provider_backend: :anthropic], opts))
  end

  describe "effort option" do
    test "defaults to nil" do
      opts = new_options([])
      assert opts.effort == nil
    end

    test "accepts :low" do
      opts = new_options(effort: :low)
      assert opts.effort == :low
    end

    test "accepts :medium" do
      opts = new_options(effort: :medium)
      assert opts.effort == :medium
    end

    test "accepts :high" do
      opts = new_options(effort: :high)
      assert opts.effort == :high
    end

    test "emits --effort flag when set" do
      opts = new_options(effort: :high)
      args = Options.to_args(opts)
      assert "--effort" in args
      idx = Enum.find_index(args, &(&1 == "--effort"))
      assert Enum.at(args, idx + 1) == "high"
    end

    test "does not emit --effort when nil" do
      opts = new_options(effort: nil)
      args = Options.to_args(opts)
      refute "--effort" in args
    end

    test "accepts :max" do
      opts = new_options(effort: :max)
      assert opts.effort == :max
    end

    test "emits --effort max" do
      opts = new_options(effort: :max, model: "opus")
      args = Options.to_args(opts)
      assert "--effort" in args
      idx = Enum.find_index(args, &(&1 == "--effort"))
      assert Enum.at(args, idx + 1) == "max"
    end

    test "rejects invalid effort at construction time" do
      assert_raise ArgumentError, ~r/effort must be one of/, fn ->
        Options.new(effort: :turbo)
      end
    end

    test "rejects invalid effort when converting a struct literal to args" do
      assert_raise ArgumentError, ~r/effort must be one of/, fn ->
        %Options{effort: :turbo}
        |> Options.to_args()
      end
    end
  end

  describe "effort + haiku gating" do
    test "strips effort when model is haiku short form" do
      opts = new_options(effort: :high, model: "haiku")

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          refute "--effort" in args
        end)

      assert log =~ "not supported for Haiku"
    end

    test "strips effort when model is haiku full ID" do
      opts = new_options(effort: :medium, model: "claude-haiku-4-5-20251001")

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          refute "--effort" in args
        end)

      assert log =~ "not supported for Haiku"
    end

    test "respects SDK log_level filter when warning is emitted" do
      previous_level = Application.get_env(:claude_agent_sdk, :log_level, :warning)
      Application.put_env(:claude_agent_sdk, :log_level, :off)

      on_exit(fn ->
        Application.put_env(:claude_agent_sdk, :log_level, previous_level)
      end)

      opts = new_options(effort: :high, model: "haiku")

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          refute "--effort" in args
        end)

      assert log == ""
    end

    test "allows effort on opus" do
      opts = new_options(effort: :high, model: "opus")
      args = Options.to_args(opts)
      assert "--effort" in args
    end

    test "allows :max effort on opus" do
      opts = new_options(effort: :max, model: "opus")
      args = Options.to_args(opts)
      assert "--effort" in args
      idx = Enum.find_index(args, &(&1 == "--effort"))
      assert Enum.at(args, idx + 1) == "max"
    end

    test "allows :max effort on claude-opus-4-7" do
      opts = new_options(effort: :max, model: "claude-opus-4-7")
      args = Options.to_args(opts)
      assert "--effort" in args
    end

    test "allows :max effort on opus[1m]" do
      opts = new_options(effort: :max, model: "opus[1m]")
      args = Options.to_args(opts)
      assert "--effort" in args
    end

    test "warns and strips :max effort on sonnet" do
      opts = new_options(effort: :max, model: "sonnet")

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          refute "--effort" in args
        end)

      assert log =~ "only supported on Opus"
    end

    test "allows effort on sonnet" do
      opts = new_options(effort: :low, model: "sonnet")
      args = Options.to_args(opts)
      assert "--effort" in args
    end

    test "allows effort when model is nil and the default model supports it" do
      TestEnvHelpers.with_system_env(
        [{Env.provider_backend(), "anthropic"}, {Env.anthropic_model(), "sonnet"}],
        fn ->
          opts = Options.new(effort: :high, model: nil)
          args = Options.to_args(opts)
          assert "--effort" in args
        end
      )
    end

    test "allows :max effort when model is nil and env default is opus" do
      TestEnvHelpers.with_system_env(
        [{Env.provider_backend(), "anthropic"}, {Env.anthropic_model(), "opus"}],
        fn ->
          opts = Options.new(effort: :max, model: nil)
          args = Options.to_args(opts)
          assert "--effort" in args
        end
      )
    end

    test "warns and strips :max effort when model is nil and registry default is sonnet" do
      TestEnvHelpers.with_system_env(
        [{Env.provider_backend(), "anthropic"}, {Env.anthropic_model(), nil}],
        fn ->
          opts = Options.new(effort: :max, model: nil, provider_backend: :anthropic)

          log =
            capture_log(fn ->
              args = Options.to_args(opts)
              refute "--effort" in args
            end)

          assert log =~ "only supported on Opus"
        end
      )
    end

    test "uses the resolved payload model when gating :max" do
      opts =
        new_options(
          effort: :max,
          model: nil,
          model_payload: resolved_payload!("sonnet")
        )

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          refute "--effort" in args
        end)

      assert log =~ "only supported on Opus"
    end

    test "uses the resolved payload model when gating Haiku effort" do
      opts =
        new_options(
          effort: :high,
          model: nil,
          model_payload: resolved_payload!("haiku")
        )

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          refute "--effort" in args
        end)

      assert log =~ "not supported for Haiku"
    end
  end

  defp resolved_payload!(model) do
    {:ok, payload} = CliSubprocessCore.ModelRegistry.build_arg_payload(:claude, model, [])
    payload
  end
end
