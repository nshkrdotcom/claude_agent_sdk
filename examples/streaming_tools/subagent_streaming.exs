#!/usr/bin/env elixir
# Subagent Streaming Example (LIVE)
#
# Demonstrates the parent_tool_use_id field for identifying subagent output.
# The field identifies which Task tool call produced each message,
# enabling UIs to route output to the correct panel.
#
# Run: mix run examples/streaming_tools/subagent_streaming.exs
#
# Key concepts:
#   - Main agent events have parent_tool_use_id: nil
#   - Subagent messages have parent_tool_use_id: "toolu_XXX" (the Task tool call ID)
#   - parent_tool_use_id appears on complete messages, not streaming deltas
#   - This test runs through ALL turns to capture subagent messages

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Streaming, Options}
alias Examples.Support

Support.ensure_live!()

defmodule SubagentStreamingDemo do
  @moduledoc """
  Demonstrates parent_tool_use_id for distinguishing main vs subagent output.
  """

  def run do
    print_header()

    # Configure streaming with Task tool enabled
    # Use control client transport to exercise that code path
    options = %Options{
      model: "haiku",
      max_turns: 3,
      allowed_tools: ["Task", "Glob"],
      permission_mode: :bypass_permissions,
      preferred_transport: :control
    }

    IO.puts("[CONFIG] Model: haiku, Max turns: 3, Tools: [Task, Glob]\n")

    {:ok, session} = Streaming.start_session(options)

    try do
      # This prompt triggers Task tool to spawn a subagent
      prompt = """
      Use the Task tool with subagent_type="Explore" to find any .exs files
      in the current directory. Keep it brief - just list up to 3 files found.
      """

      IO.puts("[PROMPT] #{String.trim(prompt)}\n")
      IO.puts(String.duplicate("-", 60))
      IO.puts("STREAMING OUTPUT (with parent_tool_use_id):")
      IO.puts(String.duplicate("-", 60))
      IO.puts("")

      # Track events by parent_tool_use_id
      stats = %{
        main_agent_events: 0,
        subagent_events: 0,
        parent_ids_seen: MapSet.new()
      }

      # Process ALL events through all turns - don't halt on message_stop!
      # The parent_tool_use_id appears on complete messages from subagents,
      # which arrive in turns 2+ after the main agent calls the Task tool.
      result =
        Streaming.send_message(session, prompt)
        |> Enum.reduce(stats, fn event, acc ->
          process_event(event, acc)
        end)

      print_summary(result)
    after
      Streaming.close_session(session)
    end
  end

  defp process_event(event, acc) do
    # Check parent_tool_use_id to determine if from main agent or subagent
    parent_id = Map.get(event, :parent_tool_use_id)

    {label, acc} =
      case parent_id do
        nil ->
          {"[MAIN]", %{acc | main_agent_events: acc.main_agent_events + 1}}

        id when is_binary(id) ->
          short_id = String.slice(id, 0, 12) <> "..."

          acc = %{
            acc
            | subagent_events: acc.subagent_events + 1,
              parent_ids_seen: MapSet.put(acc.parent_ids_seen, id)
          }

          {"[SUB:#{short_id}]", acc}
      end

    # Print event with its source indicator
    case event do
      %{type: :text_delta, text: text} ->
        IO.write("#{label} #{inspect(text)}\n")

      %{type: :tool_use_start, name: name, id: id} ->
        IO.puts("#{label} Tool: #{name} (id: #{String.slice(id, 0, 15)}...)")

      %{type: :message_start, model: model} ->
        IO.puts("#{label} Message start (model: #{model})")

      %{type: :message_stop} ->
        IO.puts("#{label} Message complete")

      %{type: type} ->
        IO.puts("#{label} #{type}")
    end

    acc
  end

  defp print_header do
    IO.puts("")
    IO.puts(String.duplicate("=", 60))
    IO.puts("SUBAGENT STREAMING EXAMPLE")
    IO.puts(String.duplicate("=", 60))
    IO.puts("")
    IO.puts("This example demonstrates parent_tool_use_id for routing")
    IO.puts("output from subagents spawned via the Task tool.")
    IO.puts("")
    IO.puts("Note: parent_tool_use_id appears on complete messages from")
    IO.puts("subagents, not on streaming deltas. Runs through ALL turns.")
    IO.puts("")
  end

  defp print_summary(stats) do
    IO.puts("")
    IO.puts(String.duplicate("=", 60))
    IO.puts("SUMMARY")
    IO.puts(String.duplicate("=", 60))
    IO.puts("")
    IO.puts("Main agent events:    #{stats.main_agent_events}")
    IO.puts("Subagent events:      #{stats.subagent_events}")
    IO.puts("Unique parent IDs:    #{MapSet.size(stats.parent_ids_seen)}")
    IO.puts("")

    if stats.subagent_events > 0 do
      IO.puts("[SUCCESS] Detected #{stats.subagent_events} subagent events!")
      IO.puts("")
      IO.puts("Parent tool use IDs seen:")

      for id <- stats.parent_ids_seen do
        IO.puts("  - #{id}")
      end

      IO.puts("")
      IO.puts("This confirms parent_tool_use_id is correctly preserved!")
    else
      IO.puts("[INFO] No subagent events detected (all parent_tool_use_id: nil)")
      IO.puts("       The Task tool may not have spawned a subagent, or")
      IO.puts("       the subagent completed without streaming messages.")
    end

    IO.puts("")
    IO.puts(String.duplicate("-", 60))
    IO.puts("Use case: Build hierarchical streaming UIs where main agent")
    IO.puts("output appears in one panel and subagent output in another.")
    IO.puts(String.duplicate("-", 60))
  end
end

SubagentStreamingDemo.run()
Support.halt_if_runner!()
