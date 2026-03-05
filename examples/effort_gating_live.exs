#!/usr/bin/env elixir

# Effort Gating Example (LIVE)
# Usage: mix run examples/effort_gating_live.exs
#
# Demonstrates:
#   - Supported models keeping `effort`
#   - Haiku omitting `effort` with a warning
#   - Invalid effort values raising `ArgumentError`

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, Options}
alias Examples.Support

Support.ensure_live!()

defmodule EffortGatingLive do
  def run do
    Support.header!("Effort Gating Example (live)")

    run_case(
      "Supported model keeps effort",
      Options.new(
        model: "sonnet",
        effort: :high,
        max_turns: 1,
        setting_sources: ["user"]
      )
    )

    run_case(
      "Haiku omits effort with warning",
      Options.new(
        model: "haiku",
        effort: :high,
        max_turns: 1,
        setting_sources: ["user"]
      )
    )

    IO.puts("\nInvalid effort values fail fast:")

    try do
      Options.new(model: "opus", effort: :max)
    rescue
      error in ArgumentError ->
        IO.puts("  #{Exception.message(error)}")
    end
  end

  defp run_case(label, options) do
    IO.puts("\n#{label}")
    IO.puts(String.duplicate("-", 72))
    IO.inspect(preview_args(options), label: "CLI args")

    response =
      ClaudeAgentSDK.query("Reply with exactly: OK", options)
      |> Enum.to_list()
      |> extract_response()

    IO.puts("Response: #{response}")
  end

  defp extract_response(messages) do
    messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp preview_args(%Options{model: model, effort: effort} = options)
       when is_binary(model) and not is_nil(effort) do
    if String.contains?(String.downcase(model), "haiku") do
      Options.to_args(%{options | effort: nil})
    else
      Options.to_args(options)
    end
  end

  defp preview_args(options), do: Options.to_args(options)
end

EffortGatingLive.run()
Support.halt_if_runner!()
