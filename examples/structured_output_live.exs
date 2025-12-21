#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias Examples.Support

defmodule StructuredOutputLiveExample do
  @moduledoc """
  Live example: request structured JSON validated by Claude Code CLI with --json-schema.

  Requires:
    * A CLI version that supports --json-schema (the Python 0.1.10 parity feature).
    * Authenticated `claude` (`CLAUDE_AGENT_OAUTH_TOKEN` or `claude login`).
    * Optional: set `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (ms) if MCP/server startup is slow.
  """

  alias ClaudeAgentSDK.Options

  @schema %{
    "type" => "object",
    "properties" => %{
      "summary" => %{"type" => "string"},
      "next_steps" => %{
        "type" => "array",
        "items" => %{"type" => "string"}
      }
    },
    "required" => ["summary", "next_steps"]
  }

  def run do
    prompt = """
    You are a release assistant. Return JSON that matches the provided schema: a one-sentence
    summary and exactly 3 next_steps (short bullet phrases). Do not use tools or read files;
    respond directly in validated JSON only.
    """

    options = %Options{
      output_format: %{type: :json_schema, schema: @schema},
      model: "haiku",
      max_turns: 5,
      tools: []
    }

    IO.puts("\n🧪 Structured output demo (live CLI)…")
    IO.puts("Schema: #{Jason.encode!(@schema)}\n")

    IO.puts(
      "Init timeout: #{timeout_env_value()} (set CLAUDE_CODE_STREAM_CLOSE_TIMEOUT to extend for slow MCP/server startup)\n"
    )

    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

    case find_structured_output(messages) do
      nil ->
        IO.puts("⚠️  No structured_output returned. Check CLI version/support.")

      structured ->
        IO.puts("✨ Structured output:")
        IO.puts(Jason.encode!(structured, pretty: true))
    end
  end

  defp find_structured_output(messages) do
    messages
    |> Enum.find_value(fn
      %{type: :result, data: %{structured_output: so}} when is_map(so) ->
        so

      %{type: :assistant, data: %{message: %{"content" => content}}} when is_list(content) ->
        Enum.find_value(content, fn
          %{"type" => "tool_use", "name" => "StructuredOutput", "input" => input} -> input
          _ -> nil
        end)

      _ ->
        nil
    end)
  end

  defp timeout_env_value do
    case System.get_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT") do
      nil -> "default 60000ms (60s floor)"
      value -> "#{value}ms"
    end
  end
end

Support.ensure_live!()
Support.header!("Structured Output Example (live)")
StructuredOutputLiveExample.run()
Support.halt_if_runner!()
