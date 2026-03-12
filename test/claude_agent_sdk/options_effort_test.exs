defmodule ClaudeAgentSDK.Options.EffortTest do
  use ClaudeAgentSDK.SupertesterCase

  import ExUnit.CaptureLog

  alias ClaudeAgentSDK.Options

  describe "effort option" do
    test "defaults to nil" do
      opts = Options.new()
      assert opts.effort == nil
    end

    test "accepts :low" do
      opts = Options.new(effort: :low)
      assert opts.effort == :low
    end

    test "accepts :medium" do
      opts = Options.new(effort: :medium)
      assert opts.effort == :medium
    end

    test "accepts :high" do
      opts = Options.new(effort: :high)
      assert opts.effort == :high
    end

    test "emits --effort flag when set" do
      opts = Options.new(effort: :high)
      args = Options.to_args(opts)
      assert "--effort" in args
      idx = Enum.find_index(args, &(&1 == "--effort"))
      assert Enum.at(args, idx + 1) == "high"
    end

    test "does not emit --effort when nil" do
      opts = Options.new(effort: nil)
      args = Options.to_args(opts)
      refute "--effort" in args
    end

    test "accepts :max" do
      opts = Options.new(effort: :max)
      assert opts.effort == :max
    end

    test "emits --effort max" do
      opts = Options.new(effort: :max)
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
      opts = Options.new(effort: :high, model: "haiku")

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          refute "--effort" in args
        end)

      assert log =~ "not supported for Haiku"
    end

    test "strips effort when model is haiku full ID" do
      opts = Options.new(effort: :medium, model: "claude-haiku-4-5-20251001")

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

      opts = Options.new(effort: :high, model: "haiku")

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          refute "--effort" in args
        end)

      assert log == ""
    end

    test "allows effort on opus" do
      opts = Options.new(effort: :high, model: "opus")
      args = Options.to_args(opts)
      assert "--effort" in args
    end

    test "allows :max effort on opus" do
      opts = Options.new(effort: :max, model: "opus")
      args = Options.to_args(opts)
      assert "--effort" in args
      idx = Enum.find_index(args, &(&1 == "--effort"))
      assert Enum.at(args, idx + 1) == "max"
    end

    test "allows :max effort on claude-opus-4-6" do
      opts = Options.new(effort: :max, model: "claude-opus-4-6")
      args = Options.to_args(opts)
      assert "--effort" in args
    end

    test "warns but passes :max effort on sonnet" do
      opts = Options.new(effort: :max, model: "sonnet")

      log =
        capture_log(fn ->
          args = Options.to_args(opts)
          assert "--effort" in args
        end)

      assert log =~ "only supported on Opus"
    end

    test "allows effort on sonnet" do
      opts = Options.new(effort: :low, model: "sonnet")
      args = Options.to_args(opts)
      assert "--effort" in args
    end

    test "allows effort when model is nil" do
      opts = Options.new(effort: :high, model: nil)
      args = Options.to_args(opts)
      assert "--effort" in args
    end

    test "allows :max effort when model is nil" do
      opts = Options.new(effort: :max, model: nil)
      args = Options.to_args(opts)
      assert "--effort" in args
    end
  end
end
