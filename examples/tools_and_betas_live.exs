#!/usr/bin/env elixir

# Run: mix run examples/tools_and_betas_live.exs
#
# Optional:
#   - Set `CLAUDE_CODE_BETAS` to a comma-separated list of beta flags to include.

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, ContentExtractor, Options}
alias Examples.Support

Support.ensure_live!()
Support.header!("Tools (and optional betas) Example (live)")

defmodule ToolsAndBetasLive do
  @prompt "Reply with exactly: OK. Do not use any tools."

  defp display_text(nil), do: ""

  defp display_text(text) when is_binary(text) do
    if String.contains?(text, "\\n") and not String.contains?(text, "\n") do
      String.replace(text, "\\n", "\n")
    else
      text
    end
  end

  def run_case(label, %Options{} = options, expected_tools) do
    IO.puts("=== #{label} ===")
    IO.inspect(Options.to_args(options), label: "CLI args")

    {:ok, client} = Client.start_link(options)

    try do
      :ok = Client.await_initialized(client, 15_000)
      :ok = Client.query(client, @prompt)
      {:ok, messages} = Client.receive_response(client)

      init =
        Enum.find(messages, fn
          %{type: :system, subtype: :init} -> true
          _ -> false
        end)

      if is_nil(init) do
        raise "Tools example (#{label}) did not emit a system init message."
      end

      init_tools = init.data[:tools] || []
      validate_tools!(label, init_tools, expected_tools)

      sample = Enum.take(init_tools, 10)
      IO.puts("System tools (#{length(init_tools)}): #{inspect(sample)}")

      Enum.each(messages, fn
        %{type: :assistant} = message ->
          text = ContentExtractor.extract_text(message)

          if is_binary(text) and text != "" do
            IO.puts("Assistant:\n#{display_text(text)}")
          end

        _ ->
          :ok
      end)

      case Enum.find(messages, &(&1.type == :result)) do
        %{subtype: :success} = message ->
          print_result(message)

        %{subtype: other} = message ->
          if Support.ollama_backend?() do
            print_result(message)

            IO.puts(
              "Note: continuing under Ollama because this example validates tool exposure from init metadata."
            )
          else
            raise "Tools example (#{label}) did not succeed (result subtype: #{inspect(other)})"
          end

        nil ->
          raise "Tools example (#{label}) did not emit a result message."
      end

      IO.puts("")
    after
      if Process.alive?(client), do: Client.stop(client)
    end
  end

  defp print_result(message) do
    IO.puts("Result: #{message.subtype}")

    if Map.has_key?(message.data, :total_cost_usd) do
      IO.puts("Cost: $#{message.data.total_cost_usd}")
    end
  end

  defp validate_tools!(_label, actual, expected) when is_list(expected) do
    if Enum.sort(actual) != Enum.sort(expected) do
      raise "Expected tools #{inspect(expected)}, got #{inspect(actual)}"
    end
  end

  defp validate_tools!(_label, actual, :empty) do
    if actual != [] do
      raise "Expected no tools, got #{inspect(actual)}"
    end
  end

  defp validate_tools!(label, actual, :nonempty) do
    if actual == [] do
      raise "Tools example (#{label}) did not expose any tools."
    end
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

ToolsAndBetasLive.run_case(
  "tools: explicit list",
  %{base | tools: ["Read", "Glob", "Grep"]},
  ["Read", "Glob", "Grep"]
)

ToolsAndBetasLive.run_case("tools: [] (disable built-ins)", %{base | tools: []}, :empty)

ToolsAndBetasLive.run_case(
  "tools: preset (:claude_code -> default)",
  %{base | tools: %{type: :preset, preset: :claude_code}},
  :nonempty
)

Support.halt_if_runner!()
