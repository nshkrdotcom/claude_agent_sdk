#!/usr/bin/env elixir
# Subagent Spawning Example (LIVE)
# Demonstrates using the Task tool to spawn parallel subagents.
# This mirrors the research-agent pattern from the official SDK demos.
#
# Run: mix run examples/advanced_features/subagent_spawning_live.exs
#
# The Task tool enables multi-agent coordination where a lead agent
# can spawn specialized subagents to work on different aspects of a problem.

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Options, ContentExtractor}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias Examples.Support

Support.ensure_live!()

Support.header!("Subagent Spawning Example (live)")

IO.puts("""
This example demonstrates multi-agent coordination using the Task tool.
A lead agent will spawn subagents to handle different aspects of a research task.
""")

# Track subagent spawning via hooks
# Use :bag type to handle concurrent inserts properly (avoids race conditions)
:ets.new(:subagent_tracker, [:named_table, :public, :bag])

# Use an Agent to serialize IO output and avoid interleaving
{:ok, output_agent} = Agent.start_link(fn -> [] end)

log_output = fn message ->
  Agent.update(output_agent, fn logs -> logs ++ [message] end)
end

# Pre-tool hook to track Task tool usage
track_task = fn input, _tool_use_id, _context ->
  case input do
    %{"tool_name" => "Task", "tool_input" => tool_input} ->
      description = tool_input["description"] || "unknown"
      subagent_type = tool_input["subagent_type"] || "general-purpose"

      # Insert into bag table - each insert adds a new entry (no race condition)
      :ets.insert(
        :subagent_tracker,
        {:task_call,
         %{
           description: description,
           subagent_type: subagent_type,
           timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
         }}
      )

      # Buffer output to avoid interleaving
      log_output.("  [hook] Task spawned: #{description} (#{subagent_type})")

    _ ->
      :ok
  end

  Output.allow()
end

# Post-tool hook to track completion
track_completion = fn result, _tool_use_id, _context ->
  case result do
    %{"tool_name" => "Task"} ->
      :ets.insert(:subagent_tracker, {:task_complete, DateTime.utc_now()})
      log_output.("  [hook] Task subagent completed")

    _ ->
      :ok
  end

  %{}
end

options =
  Options.new(
    model: "haiku",
    max_turns: 8,
    # Enable Task tool for subagent spawning
    allowed_tools: ["Task", "Read", "Glob", "Grep"],
    permission_mode: :bypass_permissions,
    hooks: %{
      pre_tool_use: [Matcher.new("*", [track_task])],
      post_tool_use: [Matcher.new("*", [track_completion])]
    }
  )

# The prompt asks Claude to use the Task tool to spawn subagents
# This demonstrates the multi-agent coordination pattern
prompt = """
I need you to demonstrate subagent spawning. Use the Task tool to spawn
TWO subagents in parallel:

1. First subagent: Use subagent_type="Explore" with a quick task to find
   any .exs files in the examples directory

2. Second subagent: Use subagent_type="Explore" with a quick task to
   count how many test files exist

For each Task call, set run_in_background=false so we see the results.
After spawning both, summarize what each subagent found.

Keep responses brief - this is a demonstration of the Task tool.
"""

IO.puts("Prompt: #{String.slice(prompt, 0..200)}...\n")
IO.puts("Streaming response:")
IO.puts(String.duplicate("-", 60))

messages =
  ClaudeAgentSDK.query(prompt, options)
  |> Enum.to_list()

IO.puts(String.duplicate("-", 60))

# Print buffered hook output
IO.puts("\nHook Activity Log:")

Agent.get(output_agent, & &1)
|> Enum.each(&IO.puts/1)

Agent.stop(output_agent)

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
  IO.puts(String.slice(text, 0..800))
  if String.length(text) > 800, do: IO.puts("... (truncated)")
  IO.puts(String.duplicate("-", 60))
end

# Check result
case Enum.find(messages, &(&1.type == :result)) do
  %{subtype: :success} ->
    IO.puts("\n[ok] Query completed successfully")

  %{subtype: subtype} ->
    raise "Query completed with status: #{inspect(subtype)}"

  nil ->
    raise "No result message found"
end

# Display subagent tracking summary
# Retrieve all :task_call entries from the bag table
task_calls =
  :ets.lookup(:subagent_tracker, :task_call)
  |> Enum.map(fn {:task_call, data} -> data end)

task_completions = :ets.lookup(:subagent_tracker, :task_complete) |> length()

IO.puts("\nSubagent Spawning Summary:")
IO.puts(String.duplicate("-", 60))

if length(task_calls) < 2 do
  raise "Expected at least 2 Task tool calls, observed #{length(task_calls)}."
end

if task_completions < 2 do
  raise "Expected at least 2 Task completions, observed #{task_completions}."
end

IO.puts("Total Task tool calls: #{length(task_calls)}")
IO.puts("Task completions: #{task_completions}")

Enum.each(task_calls, fn call ->
  IO.puts("  - #{call.description} (#{call.subagent_type})")
end)

IO.puts("\n[ok] Successfully demonstrated subagent spawning!")

IO.puts(String.duplicate("-", 60))

IO.puts("\nWhat happened:")
IO.puts("  1. Configured allowed_tools to include Task")
IO.puts("  2. Set up hooks to track Task tool usage")
IO.puts("  3. Asked Claude to spawn subagents for parallel work")
IO.puts("  4. Tracked subagent spawning via pre_tool_use hooks")
IO.puts("  5. Summarized the multi-agent coordination")
IO.puts("\nThis pattern enables:")
IO.puts("  - Research agents that spawn specialized researchers")
IO.puts("  - Code analysis with parallel file scanning")
IO.puts("  - Complex workflows with task decomposition")

:ets.delete(:subagent_tracker)

Support.halt_if_runner!()
