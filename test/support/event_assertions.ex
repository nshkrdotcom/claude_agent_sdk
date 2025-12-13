defmodule ClaudeAgentSDK.TestSupport.EventAssertions do
  @moduledoc """
  Custom assertions for streaming event testing.

  Provides expressive assertions for validating event streams,
  including event ordering, content matching, and timing.
  """

  import ExUnit.Assertions

  @doc """
  Asserts that an event stream contains a specific event type.

  ## Examples

      assert_event_present(events, :text_delta)
      assert_event_present(events, :tool_use_start, name: "Bash")
  """
  def assert_event_present(events, event_type, filters \\ []) do
    matching = find_events(events, event_type, filters)

    refute Enum.empty?(matching),
           "Expected to find #{event_type} event#{format_filters(filters)}, but none found.\n" <>
             "Available events: #{inspect(Enum.map(events, & &1.type))}"

    matching
  end

  @doc """
  Asserts that an event stream does NOT contain a specific event type.
  """
  def refute_event_present(events, event_type, filters \\ []) do
    matching = find_events(events, event_type, filters)

    assert Enum.empty?(matching),
           "Expected NO #{event_type} events#{format_filters(filters)}, but found #{length(matching)}:\n" <>
             inspect(matching)
  end

  @doc """
  Asserts event count matches expectation.

  ## Examples

      assert_event_count(events, :text_delta, 5)
      assert_event_count(events, :tool_use_start, 2, name: "Bash")
  """
  def assert_event_count(events, event_type, expected_count, filters \\ []) do
    matching = find_events(events, event_type, filters)
    actual_count = length(matching)

    assert actual_count == expected_count,
           "Expected #{expected_count} #{event_type} events#{format_filters(filters)}, " <>
             "but found #{actual_count}"

    matching
  end

  @doc """
  Asserts events appear in the specified order.

  ## Examples

      assert_event_order(events, [
        {:text_delta, _},
        {:tool_use_start, name: "Bash"},
        {:text_delta, _}
      ])
  """
  def assert_event_order(events, expected_sequence) do
    event_types = Enum.map(events, & &1.type)

    result = match_sequence(events, expected_sequence, 0, [])

    case result do
      {:ok, _matched} ->
        :ok

      {:error, {:not_found, pattern, index}} ->
        flunk(
          "Event sequence mismatch at position #{index}.\n" <>
            "Expected pattern: #{inspect(pattern)}\n" <>
            "Actual event types: #{inspect(event_types)}"
        )

      {:error, {:out_of_events, pattern, index}} ->
        flunk(
          "Event stream ended before completing expected sequence at position #{index}.\n" <>
            "Expected pattern: #{inspect(pattern)}\n" <>
            "Event count: #{length(events)}"
        )
    end
  end

  @doc """
  Asserts accumulated text from text_delta events matches expected.

  ## Examples

      assert_accumulated_text(events, "Hello World")
  """
  def assert_accumulated_text(events, expected_text) do
    actual_text =
      events
      |> Enum.filter(&(&1.type == :text_delta))
      |> Enum.map_join("", & &1.text)

    assert actual_text == expected_text,
           "Expected accumulated text: #{inspect(expected_text)}\n" <>
             "Got: #{inspect(actual_text)}"
  end

  @doc """
  Asserts a text_delta event contains specific text.
  """
  def assert_text_contains(events, substring) do
    matching =
      events
      |> Enum.filter(&(&1.type == :text_delta and String.contains?(&1.text, substring)))

    refute Enum.empty?(matching),
           "Expected to find text_delta containing #{inspect(substring)}, " <>
             "but none found in #{length(events)} events"
  end

  @doc """
  Asserts message_start and message_stop events bracket the stream.
  """
  def assert_message_lifecycle(events) do
    first = List.first(events)
    last = List.last(events)

    assert first.type == :message_start,
           "Expected first event to be :message_start, got #{inspect(first.type)}"

    assert last.type == :message_stop,
           "Expected last event to be :message_stop, got #{inspect(last.type)}"
  end

  @doc """
  Asserts tool events are properly structured.
  """
  def assert_tool_execution(events, tool_name) do
    tool_start =
      events
      |> Enum.find(&(&1.type == :tool_use_start and &1[:name] == tool_name))

    assert tool_start != nil,
           "Expected to find tool_use_start for #{tool_name}"

    # Could add more validation: input_delta events, tool_result, etc.
    tool_start
  end

  @doc """
  Collects all events of a specific type.
  """
  def collect_events(events, event_type) do
    Enum.filter(events, &(&1.type == event_type))
  end

  @doc """
  Prints event stream summary for debugging.
  """
  def summarize_events(events) do
    IO.puts("\n=== Event Stream Summary ===")
    IO.puts("Total events: #{length(events)}")

    events
    |> Enum.group_by(& &1.type)
    |> Enum.each(fn {type, group} ->
      IO.puts("  #{type}: #{length(group)}")
    end)

    IO.puts("Event sequence: #{inspect(Enum.map(events, & &1.type))}")
    IO.puts("============================\n")
  end

  ## Private helpers

  defp find_events(events, event_type, filters) do
    events
    |> Enum.filter(fn event ->
      event.type == event_type and
        Enum.all?(filters, fn {key, value} ->
          Map.get(event, key) == value
        end)
    end)
  end

  defp format_filters([]), do: ""

  defp format_filters(filters) do
    " with " <> (filters |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end))
  end

  defp match_sequence(_events, [], _index, matched) do
    {:ok, Enum.reverse(matched)}
  end

  defp match_sequence([], [pattern | _rest], index, _matched) do
    {:error, {:out_of_events, pattern, index}}
  end

  defp match_sequence([event | rest_events], [pattern | rest_patterns], index, matched) do
    if matches_pattern?(event, pattern) do
      match_sequence(rest_events, rest_patterns, index + 1, [event | matched])
    else
      # Try next event (patterns can skip events)
      match_sequence(rest_events, [pattern | rest_patterns], index, matched)
    end
  end

  defp matches_pattern?(event, {expected_type, filters}) when is_list(filters) do
    event.type == expected_type and
      Enum.all?(filters, fn {key, value} ->
        Map.get(event, key) == value
      end)
  end

  defp matches_pattern?(event, {expected_type, _}) do
    event.type == expected_type
  end

  defp matches_pattern?(event, expected_type) when is_atom(expected_type) do
    event.type == expected_type
  end
end
