#!/usr/bin/env elixir

# SDK-direct Claude promotion-path verifier.
#
# Usage:
#   mix run examples/promotion_path/sdk_direct_claude.exs -- \
#     --model haiku \
#     --prompt "Reply with exactly: claude sdk direct ok"
#
# Optional:
#   --cwd /path/to/workdir

Mix.Task.run("app.start")

defmodule ClaudePromotionPath.Direct do
  @moduledoc false

  alias ClaudeAgentSDK.{ContentExtractor, Options}

  @switches [
    cwd: :string,
    model: :string,
    prompt: :string
  ]

  def main(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches)
    reject_invalid!(invalid)

    model = required!(opts, :model)
    prompt = Keyword.get(opts, :prompt) || Enum.join(args, " ")
    prompt = if String.trim(prompt) == "", do: "Reply with exactly: claude sdk direct ok", else: prompt

    options =
      Options.new(
        model: model,
        max_turns: 1,
        output_format: :stream_json,
        tools: [],
        allowed_tools: [],
        cwd: Keyword.get(opts, :cwd),
        execution_surface: [
          surface_kind: :local_subprocess,
          observability: %{suite: :promotion_path, lane: :sdk_direct, provider: :claude}
        ]
      )

    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()
    text = ContentExtractor.extract_all_text(messages)

    if String.trim(text) == "" do
      IO.puts(:stderr, "Claude SDK-direct example returned no assistant text.")
      System.halt(1)
    else
      IO.puts(text)
    end
  end

  defp reject_invalid!([]), do: :ok

  defp reject_invalid!(invalid) do
    raise ArgumentError, "invalid options: #{inspect(invalid)}"
  end

  defp required!(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          missing_required!(key)
        else
          value
        end

      _ ->
        missing_required!(key)
    end
  end

  defp missing_required!(key) do
    IO.puts(:stderr, "Missing required --#{String.replace(to_string(key), "_", "-")}.")
    System.halt(64)
  end
end

ClaudePromotionPath.Direct.main(System.argv())
