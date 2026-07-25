defmodule ClaudeAgentSDK.Options.CustomModelTest do
  @moduledoc """
  A user must be able to select a model that is newer than the shared model
  registry. The Claude CLI accepts arbitrary `--model` strings, so an unknown
  model id passes through to `--model` (with a warning) instead of raising.
  """
  use ClaudeAgentSDK.SupertesterCase

  import ExUnit.CaptureLog, only: [capture_log: 1, with_log: 1]

  alias ClaudeAgentSDK.Options

  describe "unknown / not-yet-registered models" do
    test "Options.new/1 passes an unknown model through with a warning" do
      log =
        capture_log(fn ->
          opts = Options.new(model: "claude-brand-new-2027", provider_backend: :anthropic)
          assert opts.model == "claude-brand-new-2027"
        end)

      assert log =~ "not in the Claude model registry"
    end

    test "an unknown model is emitted verbatim to --model" do
      {opts, _log} =
        with_log(fn ->
          Options.new(model: "claude-brand-new-2027", provider_backend: :anthropic)
        end)

      args = Options.to_args(opts)
      assert "--model" in args
      idx = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, idx + 1) == "claude-brand-new-2027"
    end

    test "allow_unknown_model: false restores strict rejection" do
      assert_raise ArgumentError, ~r/model resolution failed/, fn ->
        Options.new(
          model: "claude-brand-new-2027",
          allow_unknown_model: false,
          provider_backend: :anthropic
        )
      end
    end

    test "known aliases still resolve normally (no warning)" do
      log =
        capture_log(fn ->
          opts = Options.new(model: "claude-opus-4-8", provider_backend: :anthropic)
          args = Options.to_args(opts)
          assert "--model" in args
        end)

      refute log =~ "not in the Claude model registry"
    end

    test "fable alias resolves and emits --model fable" do
      opts = Options.new(model: "fable", provider_backend: :anthropic)
      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, idx + 1) == "fable"
    end
  end

  describe "opus short forms after the Opus 5 registry refresh" do
    for short_form <- ["opus", "opus[1m]"] do
      test "#{short_form} resolves without an unregistered-model warning" do
        short_form = unquote(short_form)

        log =
          capture_log(fn ->
            opts = Options.new(model: short_form, provider_backend: :anthropic)
            assert opts.model == short_form

            args = Options.to_args(opts)
            idx = Enum.find_index(args, &(&1 == "--model"))
            assert Enum.at(args, idx + 1) == short_form
          end)

        refute log =~ "not in the Claude model registry"
      end

      test "#{short_form} still resolves under allow_unknown_model: false" do
        short_form = unquote(short_form)

        opts =
          Options.new(
            model: short_form,
            allow_unknown_model: false,
            provider_backend: :anthropic
          )

        assert opts.model == short_form
      end
    end

    test "the Opus 5 full ID and the retained prior full IDs normalize to a short form" do
      cases = [
        {"claude-opus-5", "opus"},
        {"claude-opus-4-8", "opus"},
        {"claude-opus-4-7", "opus"},
        {"claude-opus-4-8[1m]", "opus[1m]"},
        {"claude-opus-4-7[1m]", "opus[1m]"}
      ]

      for {full_id, short_form} <- cases do
        log =
          capture_log(fn ->
            opts = Options.new(model: full_id, provider_backend: :anthropic)
            assert opts.model == short_form
          end)

        refute log =~ "not in the Claude model registry"
      end
    end
  end
end
