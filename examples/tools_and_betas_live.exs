#!/usr/bin/env elixir

# Run: mix run examples/tools_and_betas_live.exs
#
# Optional:
#   - Set `CLAUDE_CODE_BETAS` to a comma-separated list of beta flags to include.

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, Options}
alias Examples.Support

Support.ensure_live!()
Support.header!("Tools (and optional betas) Example (live)")

defmodule ToolsAndBetasLive do
  defp display_text(text) when is_binary(text) do
    if String.contains?(text, "\\n") and not String.contains?(text, "\n") do
      String.replace(text, "\\n", "\n")
    else
      text
    end
  end

  def run_case(label, %Options{} = options) do
    IO.puts("=== #{label} ===")
    IO.inspect(Options.to_args(options), label: "CLI args")

    ClaudeAgentSDK.query(
      "What tools do you have available? Just list them briefly.",
      options
    )
    |> Enum.reduce(nil, fn
      %{type: :system, subtype: :init, data: %{tools: tools}}, acc ->
        sample = Enum.take(tools, 10)
        IO.puts("System tools (#{length(tools)}): #{inspect(sample)}")
        acc

      %{type: :assistant} = message, acc ->
        text = ContentExtractor.extract_text(message)
        if text != "", do: IO.puts("Assistant:\n#{display_text(text)}")
        acc

      %{type: :result} = message, _acc ->
        IO.puts("Result: #{message.subtype}")

        if Map.has_key?(message.data, :total_cost_usd) do
          IO.puts("Cost: $#{message.data.total_cost_usd}")
        end

        message.subtype

      _message, acc ->
        acc
    end)
    |> case do
      :success ->
        :ok

      other ->
        raise "Tools example (#{label}) did not succeed (result subtype: #{inspect(other)})"
    end

    IO.puts("")
  end
end

betas =
  case System.get_env("CLAUDE_CODE_BETAS") do
    nil -> []
    "" -> []
    value -> String.split(value, ",", trim: true)
  end

base = %Options{
  model: "haiku",
  max_turns: 1,
  output_format: :stream_json,
  betas: betas
}

ToolsAndBetasLive.run_case("tools: explicit list", %{base | tools: ["Read", "Glob", "Grep"]})
ToolsAndBetasLive.run_case("tools: [] (disable built-ins)", %{base | tools: []})

ToolsAndBetasLive.run_case("tools: preset (:claude_code -> default)", %{
  base
  | tools: %{type: :preset, preset: :claude_code}
})

Support.halt_if_runner!()
