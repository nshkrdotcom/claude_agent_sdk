defmodule ClaudeAgentSDK.Streaming.EventAdapter do
  @moduledoc """
  Utilities for working with heterogeneous streaming event/message streams.

  When using streaming with control features (hooks, SDK MCP, permissions),
  the stream may contain both streaming events (from EventParser) and Message
  structs (from control protocol). These helpers normalize and filter such
  mixed streams.

  ## Examples

      # Normalize mixed stream to consistent event maps
      stream
      |> EventAdapter.to_events()
      |> Stream.each(fn %{type: type} ->
        # All items now have :type key
      end)

      # Extract only text content
      final_text = stream
        |> EventAdapter.text_only()
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()
        |> List.last()

      # Filter to tool events only
      stream
      |> EventAdapter.tools_only()
      |> Stream.each(fn tool_event ->
        # Handle tool calls
      end)

  ## Event vs Message

  - **Events**: Maps with `:type` key (from EventParser)
    - `%{type: :text_delta, text: "..."}`
    - `%{type: :tool_use_start, name: "bash"}`

  - **Messages**: Structs (from Message module)
    - `%Message{type: :assistant, data: %{...}}`
    - `%Message{type: :result, subtype: :success}`

  This module normalizes both into a consistent event map format.
  """

  alias ClaudeAgentSDK.Message

  @doc """
  Normalizes a mixed stream to consistent event maps.

  Converts Message structs to event maps while passing through existing
  event maps unchanged. This creates a uniform stream interface.

  ## Parameters

  - `stream` - Stream containing events and/or Message structs

  ## Returns

  Stream of event maps with `:type` key

  ## Examples

      # Events pass through unchanged
      [%{type: :text_delta, text: "Hi"}]
      |> Stream.into([])
      |> EventAdapter.to_events()
      |> Enum.to_list()
      # => [%{type: :text_delta, text: "Hi"}]

      # Messages get normalized
      [%Message{type: :assistant, data: %{...}}]
      |> Stream.into([])
      |> EventAdapter.to_events()
      |> Enum.to_list()
      # => [%{type: :message, data: %{...}, timestamp: ~U[...]}]
  """
  @spec to_events(Enumerable.t()) :: Enumerable.t()
  def to_events(stream) do
    Stream.map(stream, &normalize/1)
  end

  @doc """
  Filters stream to only text-related events.

  Includes:
  - `:text_delta` - Text content chunks
  - `:text_block_start` - Text block initialization

  ## Parameters

  - `stream` - Stream of events

  ## Returns

  Stream containing only text events

  ## Examples

      stream
      |> EventAdapter.text_only()
      |> Stream.each(fn %{type: :text_delta, text: text} ->
        IO.write(text)
      end)
      |> Stream.run()
  """
  @spec text_only(Enumerable.t()) :: Enumerable.t()
  def text_only(stream) do
    Stream.filter(stream, &text_event?/1)
  end

  @doc """
  Filters stream to only tool-related events.

  Includes:
  - `:tool_use_start` - Tool call initialization
  - `:tool_input_delta` - Tool input JSON chunks

  ## Parameters

  - `stream` - Stream of events

  ## Returns

  Stream containing only tool events

  ## Examples

      stream
      |> EventAdapter.tools_only()
      |> Stream.each(fn
        %{type: :tool_use_start, name: name} ->
          IO.puts("Tool: \#{name}")
        %{type: :tool_input_delta, json: json} ->
          IO.write(json)
      end)
      |> Stream.run()
  """
  @spec tools_only(Enumerable.t()) :: Enumerable.t()
  def tools_only(stream) do
    Stream.filter(stream, &tool_event?/1)
  end

  @doc """
  Accumulates text from stream into progressively built strings.

  Takes text_delta events and builds up the complete text incrementally.
  Each element in the output stream contains the accumulated text up to
  that point.

  ## Parameters

  - `stream` - Stream of events

  ## Returns

  Stream of accumulated text strings (one per event, building up)

  ## Examples

      # Get final complete text
      final_text = stream
        |> EventAdapter.accumulate_text()
        |> Enum.to_list()
        |> List.last()

      # Watch text build up in real-time
      stream
      |> EventAdapter.accumulate_text()
      |> Stream.each(fn accumulated ->
        IO.write("\\r\#{accumulated}")
      end)
      |> Stream.run()
  """
  @spec accumulate_text(Enumerable.t()) :: Enumerable.t()
  def accumulate_text(stream) do
    Stream.scan(stream, "", fn event, acc ->
      case event do
        %{type: :text_delta, text: text} ->
          acc <> text

        %{accumulated: text} when is_binary(text) ->
          text

        _ ->
          acc
      end
    end)
  end

  # ============================================================================
  # Private Functions - Normalization
  # ============================================================================

  # Message structs get converted to event maps (check these first!)
  defp normalize(%Message{type: :assistant} = msg) do
    %{
      type: :assistant,
      data: msg.data,
      timestamp: DateTime.utc_now()
    }
  end

  defp normalize(%Message{type: :result} = msg) do
    %{
      type: :result,
      subtype: msg.subtype,
      data: msg.data,
      timestamp: DateTime.utc_now()
    }
  end

  defp normalize(%Message{type: :user} = msg) do
    %{
      type: :user,
      data: msg.data,
      timestamp: DateTime.utc_now()
    }
  end

  defp normalize(%Message{type: :system} = msg) do
    %{
      type: :system,
      subtype: msg.subtype,
      data: msg.data,
      timestamp: DateTime.utc_now()
    }
  end

  # Event maps pass through unchanged
  defp normalize(%{type: _} = event), do: event

  # Unknown types
  defp normalize(other) do
    %{type: :unknown, data: other}
  end

  # ============================================================================
  # Private Functions - Type Guards
  # ============================================================================

  defp text_event?(%{type: :text_delta}), do: true
  defp text_event?(%{type: :text_block_start}), do: true
  defp text_event?(_), do: false

  defp tool_event?(%{type: :tool_use_start}), do: true
  defp tool_event?(%{type: :tool_input_delta}), do: true
  defp tool_event?(_), do: false
end
