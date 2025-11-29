defmodule StructuredOutputLiveExample do
  @moduledoc """
  Live example: request structured JSON validated by Claude Code CLI with --json-schema.

  Requires:
    * A CLI version that supports --json-schema (the Python 0.1.10 parity feature).
    * Authenticated `claude` (`CLAUDE_AGENT_OAUTH_TOKEN` or `claude login`).
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
    # Force live CLI even if the test config has mocks enabled
    Application.put_env(:claude_agent_sdk, :use_mock, false)

    prompt = """
    You are a release assistant. Return JSON that matches the provided schema: a one-sentence
    summary and exactly 3 next_steps (short bullet phrases). Do not use tools or read files;
    respond directly in validated JSON only.
    """

    options = %Options{
      output_format: %{type: :json_schema, schema: @schema},
      model: "sonnet",
      max_turns: 4,
      allowed_tools: []
    }

    IO.puts("\n🧪 Structured output demo (live CLI)…")
    IO.puts("Schema: #{Jason.encode!(@schema)}\n")

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
end

StructuredOutputLiveExample.run()
