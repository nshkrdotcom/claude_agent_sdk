#!/usr/bin/env elixir
# Web Tools Example (LIVE)
# Demonstrates WebSearch and WebFetch tools for web access.
# This mirrors patterns from the official SDK demos that use web tools.
#
# Run: mix run examples/advanced_features/web_tools_live.exs
#
# NOTE: Web search requires an API key with web search enabled.
# If web search is not available, Claude will indicate this in the response.

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Options, ContentExtractor}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias Examples.Support

Support.ensure_live!()

Support.header!("Web Tools Example (live)")

IO.puts("""
This example demonstrates web access tools:
  - WebSearch: Search the web for current information
  - WebFetch: Fetch and process content from URLs

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

# Prompt that requests web search - focused on getting useful info
prompt = """
Use WebSearch to find the latest stable version of Elixir.
Tell me the version number and release date. Keep it brief (1-2 sentences).
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
    IO.puts("\n[ok] Query completed (cost: $#{:erlang.float_to_binary(cost, decimals: 6)})")

  %{subtype: :success} ->
    IO.puts("\n[ok] Query completed successfully")

  %{subtype: subtype} ->
    IO.puts("\n[warn] Query completed with status: #{inspect(subtype)}")

  nil ->
    IO.puts("\n[warn] No result message found")
end

# Display web tool tracking summary
web_calls =
  :ets.lookup(:web_tracker, :web_call)
  |> Enum.map(fn {:web_call, data} -> data end)

IO.puts("\nWeb Tools Usage Summary:")
IO.puts(String.duplicate("-", 60))

if length(web_calls) > 0 do
  search_count = Enum.count(web_calls, &(&1.tool == "WebSearch"))
  fetch_count = Enum.count(web_calls, &(&1.tool == "WebFetch"))

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
else
  IO.puts("No web tool calls were made.")
  IO.puts("Possible reasons:")
  IO.puts("  - Web search may not be enabled for your API key")
  IO.puts("  - Claude may have answered from training data")
  IO.puts("  - The tools may require specific API permissions")
  IO.puts("\nTo enable web search, ensure your API key has web search access.")
end

IO.puts(String.duplicate("-", 60))

IO.puts("\nWhat this example demonstrates:")
IO.puts("  1. WebSearch - Query the web for current information")
IO.puts("  2. Hook-based tracking of web tool usage")
IO.puts("\nUse cases:")
IO.puts("  - Research agents that gather current data")
IO.puts("  - Fact-checking with real-time sources")
IO.puts("  - Documentation lookups from official sources")

:ets.delete(:web_tracker)

Support.halt_if_runner!()
