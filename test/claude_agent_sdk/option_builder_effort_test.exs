defmodule ClaudeAgentSDK.OptionBuilder.EffortThinkingTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.OptionBuilder

  describe "with_effort/2" do
    test "adds effort to existing options" do
      opts =
        OptionBuilder.build_development_options()
        |> OptionBuilder.with_effort(:high)

      assert opts.effort == :high
    end

    test "works in pipeline" do
      opts =
        OptionBuilder.with_opus()
        |> OptionBuilder.with_effort(:max)
        |> OptionBuilder.with_turn_limit(10)

      assert opts.effort == :max
      assert opts.max_turns == 10
    end
  end

  describe "with_thinking/2" do
    test "adds adaptive thinking config" do
      opts =
        OptionBuilder.build_development_options()
        |> OptionBuilder.with_thinking(%{type: :adaptive})

      assert opts.thinking == %{type: :adaptive}
    end

    test "adds enabled thinking with budget" do
      opts =
        OptionBuilder.build_development_options()
        |> OptionBuilder.with_thinking(%{type: :enabled, budget_tokens: 16_000})

      assert opts.thinking == %{type: :enabled, budget_tokens: 16_000}
    end

    test "adds disabled thinking" do
      opts =
        OptionBuilder.build_development_options()
        |> OptionBuilder.with_thinking(%{type: :disabled})

      assert opts.thinking == %{type: :disabled}
    end
  end
end
