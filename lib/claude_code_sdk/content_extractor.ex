defmodule ClaudeCodeSDK.ContentExtractor do
  @moduledoc """
  Helper module for extracting text content from Claude messages.

  Handles various content formats including:
  - Simple string content
  - Array-based content with text blocks
  - Tool use responses
  - Nested content structures
  """

  alias ClaudeCodeSDK.Message

  @doc """
  Extracts text content from a Claude message.

  ## Parameters

    - `message` - A ClaudeCodeSDK.Message struct

  ## Returns

    - String containing the extracted text content
    - `nil` if the message doesn't contain extractable text

  ## Examples

      iex> message = %ClaudeCodeSDK.Message{
      ...>   type: :assistant,
      ...>   data: %{message: %{"content" => "Hello, world!"}}
      ...> }
      iex> ClaudeCodeSDK.ContentExtractor.extract_text(message)
      "Hello, world!"
      
      iex> message = %ClaudeCodeSDK.Message{
      ...>   type: :assistant,
      ...>   data: %{message: %{"content" => [%{"text" => "Hello!"}, %{"text" => "World!"}]}}
      ...> }
      iex> ClaudeCodeSDK.ContentExtractor.extract_text(message)
      "Hello! World!"
  """
  @spec extract_text(Message.t()) :: String.t() | nil
  def extract_text(%Message{type: :assistant, data: %{message: %{"content" => content}}}) do
    extract_content_text(content)
  end

  def extract_text(%Message{type: :assistant, data: %{message: message}}) when is_map(message) do
    # Handle other message formats
    case message do
      %{"text" => text} when is_binary(text) -> text
      _ -> inspect(message)
    end
  end

  def extract_text(%Message{type: :user, data: %{message: %{"content" => content}}}) do
    extract_content_text(content)
  end

  def extract_text(%Message{type: :result, data: %{result: result}}) when is_binary(result) do
    result
  end

  def extract_text(_message), do: nil

  @doc """
  Extracts text from various content formats.

  ## Parameters

    - `content` - Content in various formats (string, list, etc.)

  ## Returns

    - String containing the extracted text
  """
  @spec extract_content_text(any()) :: String.t()
  def extract_content_text(content) when is_binary(content), do: content

  def extract_content_text([%{"text" => text}]) when is_binary(text), do: text

  def extract_content_text(content_list) when is_list(content_list) do
    content_list
    |> Enum.map(&extract_item_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def extract_content_text(other), do: inspect(other)

  @doc """
  Checks if a message contains text content.

  ## Parameters

    - `message` - A ClaudeCodeSDK.Message struct

  ## Returns

    - `true` if the message contains extractable text
    - `false` otherwise

  ## Examples

      iex> message = %ClaudeCodeSDK.Message{type: :assistant, data: %{message: %{"content" => "Hello"}}}
      iex> ClaudeCodeSDK.ContentExtractor.has_text?(message)
      true
  """
  @spec has_text?(Message.t()) :: boolean()
  def has_text?(message) do
    extract_text(message) != nil
  end

  # Private functions

  defp extract_item_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_item_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text

  defp extract_item_text(%{"type" => "tool_use"} = tool) do
    name = tool["name"] || "unknown"
    "[Tool: #{name}]"
  end

  defp extract_item_text(%{"type" => "tool_result"} = result) do
    tool_name = result["tool_use_id"] || "unknown"
    "[Tool Result: #{tool_name}]"
  end

  defp extract_item_text(other) when is_map(other) do
    # Try to extract any text field
    case Map.get(other, "text") do
      text when is_binary(text) -> text
      _ -> nil
    end
  end

  defp extract_item_text(_), do: nil
end
