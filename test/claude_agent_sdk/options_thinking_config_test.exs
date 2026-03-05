defmodule ClaudeAgentSDK.Options.ThinkingConfigTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Options

  describe "thinking config option" do
    test "defaults to nil" do
      opts = Options.new()
      assert opts.thinking == nil
    end

    test "accepts adaptive config" do
      opts = Options.new(thinking: %{type: :adaptive})
      assert opts.thinking == %{type: :adaptive}
    end

    test "accepts enabled config with budget_tokens" do
      opts = Options.new(thinking: %{type: :enabled, budget_tokens: 16_000})
      assert opts.thinking == %{type: :enabled, budget_tokens: 16_000}
    end

    test "accepts disabled config" do
      opts = Options.new(thinking: %{type: :disabled})
      assert opts.thinking == %{type: :disabled}
    end

    test "thinking takes precedence over max_thinking_tokens" do
      opts =
        Options.new(
          thinking: %{type: :enabled, budget_tokens: 8_000},
          max_thinking_tokens: 50_000
        )

      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--max-thinking-tokens"))
      assert Enum.at(args, idx + 1) == "8000"
    end

    test "adaptive defaults to 32000 when max_thinking_tokens is nil" do
      opts = Options.new(thinking: %{type: :adaptive})
      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--max-thinking-tokens"))
      assert Enum.at(args, idx + 1) == "32000"
    end

    test "adaptive uses max_thinking_tokens as fallback when set" do
      opts = Options.new(thinking: %{type: :adaptive}, max_thinking_tokens: 64_000)
      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--max-thinking-tokens"))
      assert Enum.at(args, idx + 1) == "64000"
    end

    test "disabled emits 0" do
      opts = Options.new(thinking: %{type: :disabled})
      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--max-thinking-tokens"))
      assert Enum.at(args, idx + 1) == "0"
    end

    test "nil thinking falls back to max_thinking_tokens" do
      opts = Options.new(thinking: nil, max_thinking_tokens: 10_000)
      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--max-thinking-tokens"))
      assert Enum.at(args, idx + 1) == "10000"
    end

    test "nil thinking and nil max_thinking_tokens emits nothing" do
      opts = Options.new(thinking: nil, max_thinking_tokens: nil)
      args = Options.to_args(opts)
      refute "--max-thinking-tokens" in args
    end
  end
end
