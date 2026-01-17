defmodule ClaudeAgentSDK.Streaming.EventParser do
  @moduledoc """
  Parses streaming events from Claude CLI's `--include-partial-messages` output.

  Handles all Server-Sent Events (SSE) types from the Anthropic Messages API:
  - `message_start` - Message initialization with metadata
  - `content_block_start` - Content block (text/tool_use/thinking) starts
  - `content_block_delta` - Incremental content updates (THE CORE STREAMING EVENT)
    - `text_delta` - Character-by-character text streaming
    - `input_json_delta` - Tool input JSON being built
    - `thinking_delta` - Extended thinking content (Sonnet 4.5+)
  - `content_block_stop` - Content block complete
  - `message_delta` - Message-level metadata updates
  - `message_stop` - Message complete

  ## References
  - https://docs.anthropic.com/en/api/messages-streaming
  """

  alias ClaudeAgentSDK.AssistantError

  @type event :: map()
  @type accumulated_text :: String.t()

  @doc """
  Parses a single streaming event from Claude CLI output.

  Returns `{:ok, [events], new_accumulated_text}` where:
  - `events` - List of parsed event maps (may be empty for unknown events)
  - `new_accumulated_text` - Updated accumulated text for current message

  ## Parameters
  - `raw_event` - Decoded JSON map from CLI stdout
  - `accumulated_text` - Current accumulated text for this message

  ## Event Types Returned

  ### Text Streaming (primary use case)
  - `%{type: :text_delta, text: "...", accumulated: "..."}` - Character chunk + full text so far

  ### Message Lifecycle
  - `%{type: :message_start, model: "..."}` - Message begins
  - `%{type: :message_stop, final_text: "..."}` - Message complete

  ### Content Blocks
  - `%{type: :text_block_start}` - Text content block starts
  - `%{type: :content_block_stop, final_text: "..."}` - Block complete
  - `%{type: :tool_use_start, name: "...", id: "..."}` - Tool call starts
  - `%{type: :thinking_start}` - Thinking block starts (Sonnet 4.5+)

  ### Tool & Thinking
  - `%{type: :tool_input_delta, json: "..."}` - Partial tool input JSON
  - `%{type: :thinking_delta, thinking: "..."}` - Thinking content chunk

  ### Metadata
  - `%{type: :message_delta, stop_reason: "...", stop_sequence: "..."}` - Final metadata

  ## Examples

      # Text delta (most common event)
      {:ok, [%{type: :text_delta, text: "Hello", accumulated: "Hello"}], "Hello"} =
        EventParser.parse_event(%{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => "Hello"}}, "")

      # Message start
      {:ok, [%{type: :message_start, model: "claude-sonnet-4-5"}], ""} =
        EventParser.parse_event(%{"type" => "message_start", "message" => %{"model" => "claude-sonnet-4-5"}}, "")

      # Unknown event (ignored gracefully)
      {:ok, [], "existing text"} =
        EventParser.parse_event(%{"type" => "unknown_event"}, "existing text")
  """
  @spec parse_event(map(), accumulated_text()) :: {:ok, [event()], accumulated_text()}
  def parse_event(%{"type" => "message_start"} = event, accumulated_text) do
    model = get_in(event, ["message", "model"])
    role = get_in(event, ["message", "role"])
    usage = get_in(event, ["message", "usage"])

    events = [
      %{
        type: :message_start,
        model: model,
        role: role,
        usage: usage
      }
    ]

    {:ok, events, accumulated_text}
  end

  def parse_event(%{"type" => "content_block_start", "content_block" => block}, accumulated_text) do
    event =
      case block["type"] do
        "text" ->
          %{type: :text_block_start}

        "tool_use" ->
          %{
            type: :tool_use_start,
            name: block["name"],
            id: block["id"]
          }

        "thinking" ->
          %{type: :thinking_start}

        unknown_type ->
          %{type: :unknown_block_start, block_type: unknown_type}
      end

    {:ok, [event], accumulated_text}
  end

  def parse_event(%{"type" => "content_block_delta", "delta" => delta}, accumulated_text) do
    # THE CORE STREAMING EVENT - incremental content updates
    case delta["type"] do
      "text_delta" ->
        # Character-by-character text streaming
        text = delta["text"] || ""
        new_accumulated = accumulated_text <> text

        events = [
          %{
            type: :text_delta,
            text: text,
            accumulated: new_accumulated
          }
        ]

        {:ok, events, new_accumulated}

      "input_json_delta" ->
        # Tool input being built incrementally
        json_part = delta["partial_json"] || ""

        events = [
          %{
            type: :tool_input_delta,
            json: json_part
          }
        ]

        {:ok, events, accumulated_text}

      "thinking_delta" ->
        # Extended thinking content (Sonnet 4.5+)
        thinking = delta["thinking"] || ""

        events = [
          %{
            type: :thinking_delta,
            thinking: thinking
          }
        ]

        {:ok, events, accumulated_text}

      _unknown_delta_type ->
        # Unknown delta type - ignore gracefully
        {:ok, [], accumulated_text}
    end
  end

  def parse_event(%{"type" => "content_block_stop"}, accumulated_text) do
    # Content block complete
    events = [
      %{
        type: :content_block_stop,
        final_text: accumulated_text
      }
    ]

    # Reset accumulated text for next block
    {:ok, events, ""}
  end

  def parse_event(%{"type" => "message_delta", "delta" => delta}, accumulated_text) do
    # Message-level metadata updates
    events = [
      %{
        type: :message_delta,
        stop_reason: delta["stop_reason"],
        stop_sequence: delta["stop_sequence"]
      }
    ]

    {:ok, events, accumulated_text}
  end

  def parse_event(%{"type" => "message_stop"} = event, accumulated_text) do
    # Message complete - final event
    structured_output =
      Map.get(event, "structured_output") || get_in(event, ["message", "structured_output"])

    error =
      event
      |> fetch_assistant_error()
      |> AssistantError.cast()

    message_stop_event =
      %{
        type: :message_stop,
        final_text: accumulated_text
      }
      |> maybe_put_structured_output(structured_output)
      |> maybe_put_error(error)

    events = [message_stop_event]

    # Reset for next message in session
    {:ok, events, ""}
  end

  def parse_event(%{"type" => "error"} = event, accumulated_text) do
    # Error event from Claude
    error_data = event["error"] || %{}

    events = [
      %{
        type: :error,
        error_type: error_data["type"],
        message: error_data["message"]
      }
    ]

    {:ok, events, accumulated_text}
  end

  def parse_event(_unknown_event, accumulated_text) do
    # Unknown event type - ignore gracefully
    # This allows forward compatibility with new event types
    {:ok, [], accumulated_text}
  end

  @doc """
  Parses a buffer of newline-delimited JSON and returns parsed events.

  Handles partial JSON lines by returning the unparsed remainder.

  ## Parameters
  - `buffer` - String buffer containing newline-delimited JSON
  - `accumulated_text` - Current accumulated text for the message

  ## Returns
  `{:ok, events, remaining_buffer, new_accumulated_text}`

  ## Examples

      buffer = ~s({"type":"message_start","message":{"model":"sonnet"}}\\n{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}\\npartial)
      {:ok, events, remaining, accumulated} = EventParser.parse_buffer(buffer, "")

      # events will contain both parsed events
      # remaining will be "partial" (incomplete JSON line)
      # accumulated will be "Hi" (from text_delta)
  """
  @spec parse_buffer(String.t(), accumulated_text()) ::
          {:ok, [event()], String.t(), accumulated_text()}
  def parse_buffer(buffer, accumulated_text) do
    # Split on newlines
    lines = String.split(buffer, "\n")

    # Last element might be incomplete
    {complete_lines, incomplete_lines} = Enum.split(lines, -1)
    remaining_buffer = List.first(incomplete_lines) || ""

    # Parse each complete line
    {events, new_accumulated} =
      Enum.reduce(complete_lines, {[], accumulated_text}, fn line, {events_acc, text_acc} ->
        parse_line(line, events_acc, text_acc)
      end)

    {:ok, events, remaining_buffer, new_accumulated}
  end

  defp parse_line(line, events_acc, text_acc) do
    trimmed = String.trim(line)

    if trimmed == "" do
      {events_acc, text_acc}
    else
      parse_json_line(line, events_acc, text_acc)
    end
  end

  defp parse_json_line(line, events_acc, text_acc) do
    case Jason.decode(line) do
      {:ok, json} ->
        {event_json, parent_tool_use_id} = unwrap_stream_event(json)
        {:ok, parsed_events, new_text_acc} = parse_event(event_json, text_acc)
        events_with_parent_id = inject_parent_tool_use_id(parsed_events, parent_tool_use_id)
        {events_acc ++ events_with_parent_id, new_text_acc}

      {:error, _reason} ->
        {events_acc, text_acc}
    end
  end

  # Inject parent_tool_use_id into all parsed events for subagent routing
  defp inject_parent_tool_use_id(events, parent_tool_use_id) do
    Enum.map(events, &Map.put(&1, :parent_tool_use_id, parent_tool_use_id))
  end

  # Unwrap stream_event wrapper from Claude CLI output, preserving parent_tool_use_id
  # The parent_tool_use_id field identifies which Task tool call produced the event,
  # enabling UIs to route subagent output to the correct panel.
  defp unwrap_stream_event(%{"type" => "stream_event", "event" => event} = wrapper) do
    parent_id = Map.get(wrapper, "parent_tool_use_id")
    {event, parent_id}
  end

  defp unwrap_stream_event(event), do: {event, nil}

  defp maybe_put_structured_output(event, nil), do: event

  defp maybe_put_structured_output(event, structured_output),
    do: Map.put(event, :structured_output, structured_output)

  defp maybe_put_error(event, nil), do: event
  defp maybe_put_error(event, error), do: Map.put(event, :error, error)

  defp fetch_assistant_error(event) do
    Map.get(event, "error") || get_in(event, ["message", "error"])
  end
end
