#!/usr/bin/env elixir

# Model Selection & Custom Models Example (LIVE)
# Usage: mix run examples/model_selection_live.exs
#
# Demonstrates:
#   - The current model aliases (sonnet -> Sonnet 5, opus -> Opus 4.8,
#     fable -> Fable 5, haiku -> Haiku 4.5) and the CLI args each produces
#   - :xhigh effort on Sonnet 5 / Fable 5 (catalog-driven gating)
#   - Using a model NOT in the registry: it passes through to --model verbatim
#   - Opting out of pass-through with allow_unknown_model: false
#   - A live query with the default model

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
    IO.puts("\n:xhigh effort (allowed on Sonnet 5 / Fable 5, dropped on Haiku):")

    for model <- ["sonnet", "fable", "haiku"] do
      args = Options.new(model: model, effort: :xhigh, max_turns: 1) |> Options.to_args()
      emitted = if "--effort" in args, do: "--effort xhigh", else: "(dropped)"
      IO.puts("  #{String.pad_trailing(model, 7)} -> #{emitted}")
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
    IO.puts("\nLive query with the default model:")

    options =
      Options.new(max_turns: 1, setting_sources: ["user"])
      |> Support.with_execution_surface()

    response =
      ClaudeAgentSDK.query("Reply with exactly: OK", options)
      |> Enum.to_list()
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")
      |> Support.assert_exact_text!("OK", "default-model response")

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
