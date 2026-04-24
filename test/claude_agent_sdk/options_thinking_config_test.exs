defmodule ClaudeAgentSDK.Options.ThinkingConfigTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Options

  defp new_options(opts) do
    Options.new(Keyword.merge([model: "sonnet", provider_backend: :anthropic], opts))
  end

  describe "thinking config option" do
    test "defaults to nil" do
      opts = new_options([])
      assert opts.thinking == nil
    end

    test "accepts adaptive config" do
      opts = new_options(thinking: %{type: :adaptive})
      assert opts.thinking == %{type: :adaptive}
    end

    test "accepts enabled config with budget_tokens" do
      opts = new_options(thinking: %{type: :enabled, budget_tokens: 16_000})
      assert opts.thinking == %{type: :enabled, budget_tokens: 16_000}
    end

    test "accepts disabled config" do
      opts = new_options(thinking: %{type: :disabled})
      assert opts.thinking == %{type: :disabled}
    end

    test "thinking takes precedence over max_thinking_tokens" do
      opts =
        new_options(
          thinking: %{type: :enabled, budget_tokens: 8_000},
          max_thinking_tokens: 50_000
        )

      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--max-thinking-tokens"))
      assert Enum.at(args, idx + 1) == "8000"
    end

    test "adaptive emits --thinking adaptive" do
      opts = new_options(thinking: %{type: :adaptive})
      args = Options.to_args(opts)

      idx = Enum.find_index(args, &(&1 == "--thinking"))
      assert Enum.at(args, idx + 1) == "adaptive"
      refute "--max-thinking-tokens" in args
    end

    test "adaptive ignores deprecated max_thinking_tokens fallback" do
      opts = new_options(thinking: %{type: :adaptive}, max_thinking_tokens: 64_000)
      args = Options.to_args(opts)

      idx = Enum.find_index(args, &(&1 == "--thinking"))
      assert Enum.at(args, idx + 1) == "adaptive"
      refute "--max-thinking-tokens" in args
    end

    test "disabled emits --thinking disabled" do
      opts = new_options(thinking: %{type: :disabled})
      args = Options.to_args(opts)

      idx = Enum.find_index(args, &(&1 == "--thinking"))
      assert Enum.at(args, idx + 1) == "disabled"
      refute "--max-thinking-tokens" in args
    end

    test "thinking display emits --thinking-display for adaptive and enabled configs" do
      adaptive = new_options(thinking: %{type: :adaptive, display: :summarized})
      enabled = new_options(thinking: %{type: :enabled, budget_tokens: 8_000, display: "omitted"})

      adaptive_args = Options.to_args(adaptive)
      enabled_args = Options.to_args(enabled)

      adaptive_idx = Enum.find_index(adaptive_args, &(&1 == "--thinking-display"))
      enabled_idx = Enum.find_index(enabled_args, &(&1 == "--thinking-display"))

      assert Enum.at(adaptive_args, adaptive_idx + 1) == "summarized"
      assert Enum.at(enabled_args, enabled_idx + 1) == "omitted"
    end

    test "nil thinking falls back to max_thinking_tokens" do
      opts = new_options(thinking: nil, max_thinking_tokens: 10_000)
      args = Options.to_args(opts)
      idx = Enum.find_index(args, &(&1 == "--max-thinking-tokens"))
      assert Enum.at(args, idx + 1) == "10000"
    end

    test "nil thinking and nil max_thinking_tokens emits nothing" do
      opts = new_options(thinking: nil, max_thinking_tokens: nil)
      args = Options.to_args(opts)
      refute "--max-thinking-tokens" in args
    end
  end
end
