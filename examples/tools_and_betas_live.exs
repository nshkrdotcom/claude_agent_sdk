alias ClaudeAgentSDK.{CLI, ContentExtractor, Options}

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
    |> Enum.each(fn
      %{type: :system, subtype: :init, data: %{tools: tools}} ->
        sample = Enum.take(tools, 10)
        IO.puts("System tools (#{length(tools)}): #{inspect(sample)}")

      %{type: :assistant} = message ->
        text = ContentExtractor.extract_text(message)
        if text != "", do: IO.puts("Assistant:\n#{display_text(text)}")

      %{type: :result} = message ->
        IO.puts("Result: #{message.subtype}")

        if Map.has_key?(message.data, :total_cost_usd) do
          IO.puts("Cost: $#{message.data.total_cost_usd}")
        end

      _ ->
        :ok
    end)

    IO.puts("")
  end
end

base =
  IO.inspect(CLI.find_executable(), label: "Claude CLI (resolved)")

IO.inspect(CLI.version(), label: "Claude CLI (version)")
IO.puts("")

%Options{
  max_turns: 1,
  output_format: :stream_json,
  betas: ["context-1m-2025-08-07"]
}

ToolsAndBetasLive.run_case("tools: list", %{base | tools: ["Read", "Glob", "Grep"]})
ToolsAndBetasLive.run_case("tools: [] (disable built-ins)", %{base | tools: []})

ToolsAndBetasLive.run_case("tools: preset (:claude_code -> default)", %{
  base
  | tools: %{type: :preset, preset: :claude_code}
})
