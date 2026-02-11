defmodule ClaudeAgentSDK.ContentExtractor do
  @moduledoc """
  Content extraction helper for Claude Code SDK messages.

  This module provides utilities to extract text content from Claude messages,
  which can have various formats depending on the type of response. It handles
  simple text, structured content blocks, tool responses, and nested formats.

  ## Content Format Examples

  Claude messages can contain content in several formats:

  ### Simple Text
      %{"content" => "Hello, world!"}

  ### Text Blocks
      %{"content" => [
        %{"type" => "text", "text" => "Hello"},
        %{"type" => "text", "text" => "World"}
      ]}

  ### Tool Responses
      %{"content" => [
        %{"type" => "text", "text" => "I'll help you with that."},
        %{"type" => "tool_use", "name" => "bash", "input" => %{"command" => "ls"}},
        %{"type" => "tool_result", "content" => "file1.txt file2.txt"}
      ]}

  ## Basic Usage

      # Extract text from assistant messages
      content = ClaudeAgentSDK.ContentExtractor.extract_text(message)
      
      # Check if message has text content
      if ClaudeAgentSDK.ContentExtractor.has_text?(message) do
        IO.puts("Message contains: \#{ClaudeAgentSDK.ContentExtractor.extract_text(message)}")
      end

      # Extract all text from a stream of messages
      all_text = 
        stream
        |> Stream.filter(&ClaudeAgentSDK.ContentExtractor.has_text?/1)
        |> Stream.map(&ClaudeAgentSDK.ContentExtractor.extract_text/1)
        |> Enum.join("\\n")

  """

  alias ClaudeAgentSDK.Config.Buffers
  alias ClaudeAgentSDK.Message

  @doc """
  Extracts text content from a Claude message.

  Handles various message types and content formats, returning the readable
  text portion of the message. Tool responses are represented as placeholders.

  ## Parameters

  - `message` - A `ClaudeAgentSDK.Message` struct

  ## Returns

  - String containing the extracted text content
  - `nil` if the message doesn't contain extractable text

  ## Examples

      # Simple text content
      message = %ClaudeAgentSDK.Message{
        type: :assistant,
        data: %{message: %{"content" => "Hello, world!"}}
      }
      ClaudeAgentSDK.ContentExtractor.extract_text(message)
      # => "Hello, world!"
      
      # Array-based content with multiple text blocks
      message = %ClaudeAgentSDK.Message{
        type: :assistant,
        data: %{message: %{"content" => [
          %{"type" => "text", "text" => "Here's the answer:"},
          %{"type" => "text", "text" => "42"}
        ]}}
      }
      ClaudeAgentSDK.ContentExtractor.extract_text(message)
      # => "Here's the answer: 42"

      # Content with tool usage
      message = %ClaudeAgentSDK.Message{
        type: :assistant,
        data: %{message: %{"content" => [
          %{"type" => "text", "text" => "Let me check that file:"},
          %{"type" => "tool_use", "name" => "read_file", "input" => %{"path" => "data.txt"}},
          %{"type" => "text", "text" => "Done!"}
        ]}}
      }
      ClaudeAgentSDK.ContentExtractor.extract_text(message)
      # => "Let me check that file: [Tool: read_file] Done!"

  """
  @spec extract_text(Message.t() | map()) :: String.t() | nil
  def extract_text(%Message{type: :assistant, data: %{message: %{"content" => content}}}) do
    extract_content_text(content)
  end

  def extract_text(%Message{type: :assistant, data: %{message: message}}) when is_map(message) do
    # Handle other message formats
    case message do
      %{"text" => text} when is_binary(text) -> text
      %{"content" => content} -> extract_content_text(content)
      _ -> nil
    end
  end

  def extract_text(%Message{type: :user, data: %{message: %{"content" => content}}}) do
    extract_content_text(content)
  end

  def extract_text(%Message{type: :result, data: %{result: result}}) when is_binary(result) do
    result
  end

  def extract_text(%Message{
        type: :result,
        data: %{structured_output: structured_output}
      })
      when is_map(structured_output) do
    Jason.encode!(structured_output)
  end

  def extract_text(%Message{
        type: :result,
        data: %{structured_output: structured_output}
      })
      when not is_nil(structured_output) do
    inspect(structured_output)
  end

  def extract_text(%Message{type: :system, data: _data}) do
    # System messages don't contain extractable text content
    nil
  end

  # Handle direct content maps (for testing or direct usage)
  def extract_text(%{"content" => content}) do
    extract_content_text(content)
  end

  def extract_text(_message), do: nil

  @doc """
  Extracts text from various content formats.

  This function handles the actual content extraction from different
  Claude content formats, including simple strings, text block arrays,
  and mixed content with tool usage.

  ## Parameters

  - `content` - Content in various formats (string, list, map, etc.)

  ## Returns

  - String containing the extracted text

  ## Examples

      # Simple string
      ClaudeAgentSDK.ContentExtractor.extract_content_text("Hello")
      # => "Hello"

      # Text blocks
      ClaudeAgentSDK.ContentExtractor.extract_content_text([
        %{"type" => "text", "text" => "Hello"},
        %{"type" => "text", "text" => "World"}
      ])
      # => "Hello World"

      # Mixed content with tools
      ClaudeAgentSDK.ContentExtractor.extract_content_text([
        %{"type" => "text", "text" => "Let me help:"},
        %{"type" => "tool_use", "name" => "calculator", "input" => %{}},
        %{"type" => "text", "text" => "Done!"}
      ])
      # => "Let me help: [Tool: calculator] Done!"

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
  Checks if a message contains extractable text content.

  ## Parameters

  - `message` - A `ClaudeAgentSDK.Message` struct

  ## Returns

  - `true` if the message contains extractable text
  - `false` otherwise

  ## Examples

      message = %ClaudeAgentSDK.Message{
        type: :assistant, 
        data: %{message: %{"content" => "Hello"}}
      }
      ClaudeAgentSDK.ContentExtractor.has_text?(message)
      # => true

      message = %ClaudeAgentSDK.Message{
        type: :system, 
        data: %{session_id: "123"}
      }
      ClaudeAgentSDK.ContentExtractor.has_text?(message)
      # => true (system messages can have extractable info)

      message = %ClaudeAgentSDK.Message{
        type: :unknown, 
        data: %{}
      }
      ClaudeAgentSDK.ContentExtractor.has_text?(message)
      # => false

  """
  @spec has_text?(Message.t() | map()) :: boolean()
  def has_text?(message) do
    case extract_text(message) do
      nil -> false
      "" -> false
      _text -> true
    end
  end

  @doc """
  Extracts all text content from a stream of messages.

  Convenience function to extract and concatenate text from multiple
  messages in a stream. Filters out messages without text content.

  ## Parameters

  - `messages` - Stream or enumerable of `ClaudeAgentSDK.Message` structs
  - `separator` - String to join messages with (default: "\\n")

  ## Returns

  - String containing all extracted text, joined with separator

  ## Examples

      messages = [
        %ClaudeAgentSDK.Message{type: :assistant, data: %{message: %{"content" => "Hello"}}},
        %ClaudeAgentSDK.Message{type: :assistant, data: %{message: %{"content" => "World"}}},
        %ClaudeAgentSDK.Message{type: :system, data: %{}}  # No text content
      ]
      
      ClaudeAgentSDK.ContentExtractor.extract_all_text(messages)
      # => "Hello\\nWorld"
      
      ClaudeAgentSDK.ContentExtractor.extract_all_text(messages, " | ")
      # => "Hello | World"

  """
  @spec extract_all_text(Enumerable.t(), String.t()) :: String.t()
  def extract_all_text(messages, separator \\ "\n") do
    messages
    |> Stream.filter(&has_text?/1)
    |> Stream.map(&extract_text/1)
    |> Enum.join(separator)
  end

  @doc """
  Summarizes content from a message, truncating if too long.

  Useful for logging or displaying preview text without overwhelming output.

  ## Parameters

  - `message` - A `ClaudeAgentSDK.Message` struct
  - `max_length` - Maximum length of summary (default: 100)

  ## Returns

  - String containing truncated text with "..." if truncated, or full text if short enough

  ## Examples

      message = %ClaudeAgentSDK.Message{
        type: :assistant, 
        data: %{message: %{"content" => "This is a very long message that should be truncated"}}
      }
      
      ClaudeAgentSDK.ContentExtractor.summarize(message, 20)
      # => "This is a very long..."

  """
  @spec summarize(Message.t() | map(), pos_integer()) :: String.t()
  def summarize(message, max_length \\ Buffers.summary_max_length()) do
    case extract_text(message) do
      nil ->
        "[No text content]"

      text when byte_size(text) <= max_length ->
        text

      text ->
        truncated = String.slice(text, 0, max_length - 3)
        truncated <> "..."
    end
  end

  # Private functions

  defp extract_item_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_item_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text

  defp extract_item_text(%{"type" => "tool_use"} = tool) do
    name = tool["name"] || "unknown"
    input_summary = summarize_tool_input(tool["input"])
    "[Tool: #{name}#{input_summary}]"
  end

  defp extract_item_text(%{"type" => "tool_result"} = result) do
    tool_use_id = result["tool_use_id"] || "unknown"

    case result["content"] do
      content when is_binary(content) and byte_size(content) > 0 ->
        if byte_size(content) > 50 do
          content_preview = String.slice(content, 0, 47) <> "..."
          "[Tool Result #{tool_use_id}: #{content_preview}]"
        else
          "[Tool Result #{tool_use_id}: #{content}]"
        end

      _ ->
        "[Tool Result: #{tool_use_id}]"
    end
  end

  defp extract_item_text(other) when is_map(other) do
    # Try to extract any text field
    case Map.get(other, "text") do
      text when is_binary(text) -> text
      _ -> nil
    end
  end

  defp extract_item_text(_), do: nil

  defp summarize_tool_input(nil), do: ""
  defp summarize_tool_input(input) when is_map(input) and map_size(input) == 0, do: ""

  defp summarize_tool_input(input) when is_map(input) do
    # Show first key-value pair as summary
    case Enum.take(input, 1) do
      [{key, value}] when is_binary(value) and byte_size(value) < 20 ->
        " #{key}: #{value}"

      [{key, _value}] ->
        " #{key}: ..."

      _ ->
        ""
    end
  end

  defp summarize_tool_input(_), do: ""
end
