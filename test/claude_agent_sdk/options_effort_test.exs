defmodule ClaudeAgentSDK.Options.EffortTest do
  use ClaudeAgentSDK.SupertesterCase

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

    test "accepts :max" do
      opts = Options.new(effort: :max)
      assert opts.effort == :max
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

    test "emits --effort max" do
      opts = Options.new(effort: :max)
      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--effort"))
      assert Enum.at(args, idx + 1) == "max"
    end
  end
end
