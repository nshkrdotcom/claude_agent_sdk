#!/usr/bin/env elixir

# Model Selection & Custom Models Example (LIVE)
# Usage: mix run examples/model_selection_live.exs
#
# Demonstrates:
#   - The current model aliases (sonnet -> Sonnet 5.5, opus -> Opus 5.5,
#     fable -> Fable 5.2, haiku -> Haiku 5.5) and the CLI args each produces
#   - :low effort on current models and legacy Haiku gating
#   - Using a model NOT in the registry: it passes through to --model verbatim
#   - Opting out of pass-through with allow_unknown_model: false
#   - A live query with Haiku 5.5

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, Model, Options}
alias Examples.Support

Support.ensure_live!()

defmodule ModelSelectionLive do
  def run do
    Support.header!("Model Selection & Custom Models (live)")

    show_registry()
    show_alias_args()
    show_effort_gating()
    show_custom_model()
    show_strict_opt_out()
    live_query()
  end

  defp show_registry do
    IO.puts("\nRegistered short forms: #{inspect(Model.short_forms())}")
    IO.puts("Default model: #{inspect(Model.default_model())}")
  end

  defp show_alias_args do
    IO.puts("\nCLI args produced by each alias:")

    for alias_name <- ["sonnet", "opus", "fable", "haiku"] do
      args = Options.new(model: alias_name, max_turns: 1) |> Options.to_args()
      IO.puts("  #{String.pad_trailing(alias_name, 7)} -> #{inspect(model_flag(args))}")
    end
  end

  defp show_effort_gating do
    IO.puts("\n:low effort across current and legacy models:")

    for model <- ["sonnet", "fable", "haiku", "claude-haiku-4-5"] do
      args = Options.new(model: model, effort: :low, max_turns: 1) |> Options.to_args()
      emitted = if "--effort" in args, do: "--effort low", else: "(dropped)"
      IO.puts("  #{String.pad_trailing(model, 18)} -> #{emitted}")
    end
  end

  defp show_custom_model do
    IO.puts("\nUsing a model newer than the registry (passes through with a warning):")
    options = Options.new(model: "claude-brand-new-2027", max_turns: 1)
    IO.puts("  emitted -> #{inspect(model_flag(Options.to_args(options)))}")
  end

  defp show_strict_opt_out do
    IO.puts("\nStrict opt-out (allow_unknown_model: false) rejects unknown models:")

    try do
      Options.new(model: "claude-brand-new-2027", allow_unknown_model: false)
    rescue
      error in ArgumentError -> IO.puts("  raised: #{Exception.message(error)}")
    end
  end

  defp live_query do
    # Use Haiku 5.5 for the actual inference call — the
    # aliases and custom-model handling above are demonstrated via CLI-arg
    # building and need no inference.
    IO.puts("\nLive query (Haiku 5.5):")

    options =
      Options.new(model: "claude-haiku-5-5", effort: :low, max_turns: 1, setting_sources: ["user"])
      |> Support.with_execution_surface()

    response =
      ClaudeAgentSDK.query("Reply with exactly: OK", options)
      |> Enum.to_list()
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")
      |> Support.assert_exact_text!("OK", "Haiku response")

    IO.puts("  Response: #{response}")
  end

  defp model_flag(args) do
    case Enum.find_index(args, &(&1 == "--model")) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end
end

ModelSelectionLive.run()
Support.halt_if_runner!()
