#!/usr/bin/env elixir

# Effort Gating Example (LIVE)
# Usage: mix run examples/effort_gating_live.exs
#
# Demonstrates:
#   - Supported models keeping `effort`
#   - Legacy Haiku omitting `effort` with a warning
#   - Invalid effort values raising `ArgumentError`

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, Options}
alias Examples.Support

Support.ensure_live!()

defmodule EffortGatingLive do
  def run do
    Support.header!("Effort Gating Example (live)")

    run_case(
      "Haiku 5.5 with low effort",
      Options.new(
        model: "claude-haiku-5-5",
        effort: :low,
        max_turns: 1,
        setting_sources: ["user"]
      )
      |> Support.with_execution_surface()
    )

    legacy = Options.new(model: "claude-haiku-4-5", effort: :low)
    IO.inspect(Options.to_args(legacy), label: "Legacy Haiku 4.5 CLI args")

    IO.puts("\nInvalid effort values fail fast:")

    try do
      Options.new(model: "opus", effort: :invalid_effort_level)
    rescue
      error in ArgumentError ->
        IO.puts("  #{Exception.message(error)}")
    end
  end

  defp run_case(label, options) do
    IO.puts("\n#{label}")
    IO.puts(String.duplicate("-", 72))
    IO.inspect(Options.to_args(options), label: "CLI args")

    response =
      ClaudeAgentSDK.query("Reply with exactly: OK", options)
      |> Enum.to_list()
      |> extract_response()
      |> Support.assert_exact_text!("OK", "#{label} response")

    IO.puts("Response: #{response}")
  end

  defp extract_response(messages) do
    messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end


end

EffortGatingLive.run()
Support.halt_if_runner!()
