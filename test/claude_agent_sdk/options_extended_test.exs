defmodule ClaudeAgentSDK.OptionsExtendedTest do
  @moduledoc """
  TDD coverage for the newly added option fields that must mirror the Python SDK surface area.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Options

  describe "budget and session flags" do
    test "max_budget_usd sets --max-budget-usd" do
      options = %Options{max_budget_usd: 12.34}
      args = Options.to_args(options)
      assert flag_with_value?(args, "--max-budget-usd", "12.34")
    end

    test "continue_conversation adds --continue" do
      options = %Options{continue_conversation: true}
      args = Options.to_args(options)
      assert "--continue" in args
    end

    test "resume adds --resume value" do
      options = %Options{resume: "session-123"}
      args = Options.to_args(options)
      assert flag_with_value?(args, "--resume", "session-123")
    end
  end

  describe "settings controls" do
    test "settings path maps to --settings" do
      options = %Options{settings: "/tmp/settings.json"}
      args = Options.to_args(options)
      assert flag_with_value?(args, "--settings", "/tmp/settings.json")
    end

    test "setting_sources join into comma list" do
      options = %Options{setting_sources: ["user", :project, "local"]}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--setting-sources", "user,project,local")
    end
  end

  describe "plugins and extra args" do
    test "local plugin entries become --plugin-dir flags" do
      options = %Options{
        plugins: [
          %{type: :local, path: "/plugins/git"},
          %{type: "local", path: "/plugins/lint"}
        ]
      }

      args = Options.to_args(options)
      plugin_dirs = collect_flag_values(args, "--plugin-dir")
      assert plugin_dirs == ["/plugins/git", "/plugins/lint"]
    end

    test "extra_args map turns into raw CLI flags" do
      options = %Options{extra_args: %{"debug-to-stderr" => nil, "foo" => "bar"}}
      args = Options.to_args(options)

      assert "--debug-to-stderr" in args
      assert flag_with_value?(args, "--foo", "bar")
    end
  end

  describe "thinking tokens" do
    test "max_thinking_tokens emits --max-thinking-tokens" do
      options = %Options{max_thinking_tokens: 1024}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--max-thinking-tokens", "1024")
    end
  end

  defp collect_flag_values(args, flag) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce([], fn
      [^flag, value], acc -> acc ++ [value]
      _, acc -> acc
    end)
  end

  defp flag_with_value?(args, flag, expected_value) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> false
      idx -> Enum.at(args, idx + 1) == expected_value
    end
  end
end
