# Example: parent_tool_use_id Streaming Verification
#
# ============================================================================
# VERIFICATION: parent_tool_use_id field is preserved in Elixir SDK
# ============================================================================
#
# ## Background
#
# When Claude uses the Task tool to spawn a subagent, messages include a
# `parent_tool_use_id` field that identifies which tool call produced them.
# This is CRITICAL for:
#
#   1. Routing output to the correct UI component
#   2. Distinguishing main agent output from subagent output
#   3. Building hierarchical UIs (nested agent displays)
#
# ## Expected Behavior
#
# - Main agent events: parent_tool_use_id = nil
# - Subagent events: parent_tool_use_id = "toolu_xxx" (the Task tool call ID)
#
# ## Important: Where parent_tool_use_id Appears
#
# The CLI sends parent_tool_use_id on COMPLETE MESSAGES (UserMessage,
# AssistantMessage), NOT on streaming deltas (text_delta, etc.).
# This script runs through ALL turns to capture subagent messages.
#
# ## What This Script Verifies
#
# 1. The parent_tool_use_id field EXISTS on all events
# 2. Main agent events correctly have nil
# 3. Subagent messages have the Task tool ID (non-nil)
#
# Run with: mix run examples/streaming_tools/parent_tool_use_id_gap.exs
# ============================================================================

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Streaming, Options}
alias Examples.Support

defmodule ParentToolUseIdVerification do
  @moduledoc """
  Verifies that parent_tool_use_id is correctly preserved on all events.

  This example:
  1. Sends a prompt that triggers Task tool usage (spawns subagent)
  2. Runs through ALL turns (not just the first message_stop)
  3. Checks that parent_tool_use_id field EXISTS on all events
  4. Categorizes events as main agent (nil) vs subagent (non-nil)

  Note: parent_tool_use_id appears on complete messages (UserMessage,
  AssistantMessage) from subagents, not on streaming deltas.
  """

  def run do
    Support.ensure_live!()

    print_header()

    # Configure streaming with Task tool enabled
    options = %Options{
      # Fast model for demo
      model: "haiku",
      # Allow subagent execution
      max_turns: 3,
      # Enable Task tool for subagents
      tools: ["Task"],
      preferred_transport: :control
    }

    IO.puts("\n[CONFIG] Starting streaming session with Task tool enabled...")
    IO.puts("[CONFIG] Model: haiku, Max turns: 3, Tools: [Task]\n")

    {:ok, session} = Streaming.start_session(options)

    if not match?({:control_client, _pid}, session) do
      raise "Expected control client session, got: #{inspect(session)}"
    end

    try do
      IO.puts("=" |> String.duplicate(72))
      IO.puts("PHASE 1: Triggering Task Tool (Subagent Spawn)")
      IO.puts("=" |> String.duplicate(72))
      IO.puts("")

      # This prompt should trigger the Task tool to spawn a subagent
      prompt = """
      Use the Task tool to delegate this to a subagent:
      Have the subagent count from 1 to 5, saying each number on a new line.
      The subagent should respond with ONLY the numbers, nothing else.
      """

      IO.puts("[PROMPT] #{String.trim(prompt)}\n")
      IO.puts("-" |> String.duplicate(72))
      IO.puts("STREAMING EVENTS (checking parent_tool_use_id):")
      IO.puts("-" |> String.duplicate(72))
      IO.puts("")

      # Track events for analysis
      events_received = %{
        total: 0,
        field_exists: 0,
        field_missing: 0,
        # nil parent_tool_use_id
        main_agent_events: 0,
        # non-nil parent_tool_use_id
        subagent_events: 0,
        tool_use_starts: [],
        subagent_ids: MapSet.new()
      }

      # Process ALL events through all turns - don't halt on message_stop!
      # The parent_tool_use_id appears on complete messages from subagents,
      # which arrive in turns 2+ after the main agent calls the Task tool.
      result =
        Streaming.send_message(session, prompt)
        |> Enum.reduce(events_received, fn event, acc ->
          acc = log_event_details(event, acc)

          case event do
            %{type: :error, message: reason} ->
              IO.puts("\n[ERROR] #{inspect(reason)}")
              acc

            _ ->
              acc
          end
        end)

      print_analysis(result)
    after
      Streaming.close_session(session)
      IO.puts("\n[CLEANUP] Session closed")
    end

    print_footer()
  end

  defp log_event_details(event, acc) do
    acc = Map.update!(acc, :total, &(&1 + 1))

    # Check if field EXISTS (this is what we fixed!)
    field_exists = Map.has_key?(event, :parent_tool_use_id)

    acc =
      if field_exists do
        Map.update!(acc, :field_exists, &(&1 + 1))
      else
        Map.update!(acc, :field_missing, &(&1 + 1))
      end

    # Categorize by value
    {label, acc} =
      cond do
        not field_exists ->
          {"[BUG!]", acc}

        is_nil(event.parent_tool_use_id) ->
          {"[MAIN]", Map.update!(acc, :main_agent_events, &(&1 + 1))}

        true ->
          acc =
            acc
            |> Map.update!(:subagent_events, &(&1 + 1))
            |> Map.update!(:subagent_ids, &MapSet.put(&1, event.parent_tool_use_id))

          {"[SUB]", acc}
      end

    # Log based on event type
    acc =
      case event do
        %{type: :tool_use_start, name: name, id: id} ->
          IO.puts("#{label} [EVENT #{acc.total}] tool_use_start")
          IO.puts("       name: #{inspect(name)}")
          IO.puts("       id: #{inspect(id)}")
          IO.puts("       parent_tool_use_id: #{format_parent_id(event, field_exists)}")
          IO.puts("")
          Map.update!(acc, :tool_use_starts, &[%{name: name, id: id} | &1])

        %{type: :text_delta, text: text} ->
          truncated =
            if String.length(text) > 40 do
              String.slice(text, 0, 40) <> "..."
            else
              text
            end

          IO.puts("#{label} [EVENT #{acc.total}] text_delta")
          IO.puts("       text: #{inspect(truncated)}")
          IO.puts("       parent_tool_use_id: #{format_parent_id(event, field_exists)}")
          IO.puts("")
          acc

        %{type: :message_start} ->
          IO.puts("#{label} [EVENT #{acc.total}] message_start")
          IO.puts("       model: #{inspect(event[:model])}")
          IO.puts("       parent_tool_use_id: #{format_parent_id(event, field_exists)}")
          IO.puts("")
          acc

        %{type: :message_stop} ->
          IO.puts("#{label} [EVENT #{acc.total}] message_stop")
          IO.puts("       parent_tool_use_id: #{format_parent_id(event, field_exists)}")
          IO.puts("")
          acc

        %{type: :content_block_stop} ->
          IO.puts("#{label} [EVENT #{acc.total}] content_block_stop")
          IO.puts("       parent_tool_use_id: #{format_parent_id(event, field_exists)}")
          IO.puts("")
          acc

        %{type: type} ->
          IO.puts("#{label} [EVENT #{acc.total}] #{type}")
          IO.puts("       parent_tool_use_id: #{format_parent_id(event, field_exists)}")
          IO.puts("")
          acc

        _ ->
          IO.puts("#{label} [EVENT #{acc.total}] unknown: #{inspect(event)}")
          IO.puts("")
          acc
      end

    acc
  end

  defp format_parent_id(event, field_exists) do
    cond do
      not field_exists ->
        "MISSING (BUG - field does not exist!)"

      is_nil(event.parent_tool_use_id) ->
        "nil (correct for main agent)"

      true ->
        "#{inspect(event.parent_tool_use_id)} (subagent event)"
    end
  end

  defp print_analysis(result) do
    IO.puts("")
    IO.puts("=" |> String.duplicate(72))
    IO.puts("ANALYSIS")
    IO.puts("=" |> String.duplicate(72))
    IO.puts("")
    IO.puts("Total events received:     #{result.total}")
    IO.puts("Field exists on events:    #{result.field_exists}")
    IO.puts("Field MISSING on events:   #{result.field_missing}")
    IO.puts("")
    IO.puts("Main agent events (nil):   #{result.main_agent_events}")
    IO.puts("Subagent events (non-nil): #{result.subagent_events}")
    IO.puts("")

    cond do
      result.field_missing > 0 ->
        IO.puts("[BUG!] #{result.field_missing} events are missing parent_tool_use_id field!")
        IO.puts("")
        IO.puts("This indicates the fix is NOT working. The field should exist")
        IO.puts("on ALL events (with nil for main agent, non-nil for subagent).")

      result.field_exists == result.total ->
        IO.puts("[OK] All #{result.total} events have parent_tool_use_id field!")
        IO.puts("")

        if result.subagent_events > 0 do
          IO.puts("[SUCCESS] Detected #{result.subagent_events} subagent events with IDs:")

          for id <- result.subagent_ids do
            IO.puts("     - #{id}")
          end

          IO.puts("")
          IO.puts("This confirms parent_tool_use_id is correctly preserved!")
        else
          IO.puts("[INFO] All events are from main agent (parent_tool_use_id: nil)")
          IO.puts("       The Task tool may not have spawned a subagent, or")
          IO.puts("       the subagent completed without streaming messages.")
        end

      true ->
        IO.puts("[PARTIAL] Some events have the field, some don't.")
        IO.puts("          This shouldn't happen - investigate further.")
    end

    if length(result.tool_use_starts) > 0 do
      IO.puts("")
      IO.puts("Tool calls observed:")

      for tool <- Enum.reverse(result.tool_use_starts) do
        IO.puts("  - #{tool.name} (id: #{tool.id})")
      end
    end
  end

  defp print_header do
    IO.puts("")
    IO.puts("=" |> String.duplicate(72))
    IO.puts("PARENT_TOOL_USE_ID VERIFICATION")
    IO.puts("=" |> String.duplicate(72))
    IO.puts("")
    IO.puts("Purpose: Verify parent_tool_use_id is preserved through all turns")
    IO.puts("")
    IO.puts("Expected results:")
    IO.puts("  - All events should have the parent_tool_use_id field")
    IO.puts("  - Main agent events: parent_tool_use_id = nil")
    IO.puts("  - Subagent messages: parent_tool_use_id = 'toolu_xxx'")
    IO.puts("")
    IO.puts("Note: parent_tool_use_id appears on complete messages from subagents,")
    IO.puts("      not on streaming deltas. This test runs through ALL turns.")
    IO.puts("")
  end

  defp print_footer do
    IO.puts("")
    IO.puts("=" |> String.duplicate(72))
    IO.puts("VERIFICATION COMPLETE")
    IO.puts("=" |> String.duplicate(72))
    IO.puts("")
    IO.puts("The parent_tool_use_id field enables routing streaming output:")
    IO.puts("")
    IO.puts("  case event.parent_tool_use_id do")
    IO.puts("    nil -> render_in_main_panel(event)")
    IO.puts("    id  -> render_in_subagent_panel(id, event)")
    IO.puts("  end")
    IO.puts("")
    IO.puts("See examples/streaming_tools/subagent_streaming.exs for usage.")
    IO.puts("")
  end
end

# Auto-run when executed with mix run
ParentToolUseIdVerification.run()
Support.halt_if_runner!()
