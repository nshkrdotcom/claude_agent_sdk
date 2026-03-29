#!/usr/bin/env elixir
# Web Tools Example (LIVE)
# Demonstrates WebSearch and WebFetch tools for web access.
# This mirrors patterns from the official SDK demos that use web tools.
#
# Run: mix run examples/advanced_features/web_tools_live.exs
#
# NOTE: Web search requires an API key with web search enabled.
# This example fails if the WebSearch tool is not available.

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Options, ContentExtractor}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias Examples.Support

Support.ensure_live!()

Support.maybe_skip_for_ollama!(
  "Web Tools Example",
  "WebSearch/WebFetch are not executed reliably under the Ollama-backed Claude path."
)

Support.header!("Web Tools Example (live)")

IO.puts("""
This example demonstrates web access tools working together:
  - WebSearch: find a current answer
  - WebFetch: confirm it from a fetched page

These tools enable Claude to access real-time information beyond its training data.
""")

# Track web tool usage via hooks
# Use :bag type to handle concurrent inserts properly
:ets.new(:web_tracker, [:named_table, :public, :bag])

# Hook to track web tool usage
track_web_tools = fn input, _tool_use_id, _context ->
  case input do
    %{"tool_name" => tool_name, "tool_input" => tool_input}
    when tool_name in ["WebSearch", "WebFetch"] ->
      details =
        case tool_name do
          "WebSearch" -> %{type: :search, query: tool_input["query"] || "unknown"}
          "WebFetch" -> %{type: :fetch, url: tool_input["url"] || "unknown"}
        end

      :ets.insert(
        :web_tracker,
        {:web_call,
         %{
           tool: tool_name,
           details: details,
           timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
         }}
      )

      detail_str =
        case details.type do
          :search -> "Query: #{details.query}"
          :fetch -> "URL: #{details.url}"
        end

      IO.puts("\n  [hook] #{tool_name} called")
      IO.puts("         #{detail_str}")

    _ ->
      :ok
  end

  Output.allow()
end

options =
  Options.new(
    model: "haiku",
    max_turns: 5,
    # Enable web tools
    allowed_tools: ["WebSearch", "WebFetch"],
    permission_mode: :bypass_permissions,
    hooks: %{
      pre_tool_use: [Matcher.new("*", [track_web_tools])]
    }
  )
  |> Support.with_execution_surface()

# Prompt that explicitly requires both web tools
prompt = """
Use both web tools for this task:
1. Use WebSearch to find the latest stable version of Elixir.
2. Use WebFetch on an official source, such as https://github.com/elixir-lang/elixir/releases
   or an elixir-lang.org release page, to confirm the version number and release date.
3. Reply in 1-2 sentences with the version number, release date, and the URL you fetched.
"""

IO.puts("Prompt: #{String.trim(prompt)}\n")
IO.puts("Streaming response:")
IO.puts(String.duplicate("-", 60))

messages =
  ClaudeAgentSDK.query(prompt, options)
  |> Enum.to_list()

IO.puts(String.duplicate("-", 60))

# Extract and display the response
text =
  messages
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.join("\n")

if text != "" do
  IO.puts("\nAssistant's Response:")
  IO.puts(String.duplicate("-", 60))
  IO.puts(String.slice(text, 0..600))
  if String.length(text) > 600, do: IO.puts("... (truncated)")
  IO.puts(String.duplicate("-", 60))
end

# Check result
case Enum.find(messages, &(&1.type == :result)) do
  %{subtype: :success, data: %{total_cost_usd: cost}} when is_number(cost) ->
    IO.puts("\n[ok] Query completed (cost: $#{Support.format_cost(cost)})")

  %{subtype: :success} ->
    IO.puts("\n[ok] Query completed successfully")

  %{subtype: subtype} ->
    raise "Query completed with status: #{inspect(subtype)}"

  nil ->
    raise "No result message found"
end

# Display web tool tracking summary
web_calls =
  :ets.lookup(:web_tracker, :web_call)
  |> Enum.map(fn {:web_call, data} -> data end)

IO.puts("\nWeb Tools Usage Summary:")
IO.puts(String.duplicate("-", 60))

if length(web_calls) == 0 do
  raise "No web tool calls were made."
end

search_count = Enum.count(web_calls, &(&1.tool == "WebSearch"))
fetch_count = Enum.count(web_calls, &(&1.tool == "WebFetch"))

if search_count < 1 do
  raise "Expected at least one WebSearch call, observed none."
end

if fetch_count < 1 do
  raise "Expected at least one WebFetch call, observed none."
end

IO.puts("Total web tool calls: #{length(web_calls)}")
IO.puts("  - WebSearch calls: #{search_count}")
IO.puts("  - WebFetch calls: #{fetch_count}")
IO.puts("")

Enum.each(web_calls, fn call ->
  detail =
    case call.details.type do
      :search -> call.details.query
      :fetch -> call.details.url
    end

  IO.puts("  #{call.tool}: #{String.slice(detail, 0..60)}")
end)

IO.puts("\n[ok] Successfully demonstrated web tools!")

IO.puts(String.duplicate("-", 60))

IO.puts("\nWhat this example demonstrates:")
IO.puts("  1. WebSearch - Find a current answer")
IO.puts("  2. WebFetch - Confirm it from a fetched page")
IO.puts("  3. Hook-based tracking of web tool usage")
IO.puts("\nUse cases:")
IO.puts("  - Research agents that gather current data")
IO.puts("  - Fact-checking with real-time sources")
IO.puts("  - Documentation lookups from official sources")

:ets.delete(:web_tracker)

Support.halt_if_runner!()
