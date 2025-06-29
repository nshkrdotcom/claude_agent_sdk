defmodule ClaudeCodeSDK.ContentExtractorTest do
  use ExUnit.Case

  alias ClaudeCodeSDK.{ContentExtractor, Message}

  describe "extract_text/1" do
    test "extracts simple string content from assistant message" do
      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => "Hello, world!"}}
      }

      assert ContentExtractor.extract_text(message) == "Hello, world!"
    end

    test "extracts text from array-based content" do
      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => [%{"text" => "Hello!"}, %{"text" => "World!"}]}}
      }

      assert ContentExtractor.extract_text(message) == "Hello! World!"
    end

    test "extracts text with type field" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"type" => "text", "text" => "First part"},
              %{"type" => "text", "text" => "Second part"}
            ]
          }
        }
      }

      assert ContentExtractor.extract_text(message) == "First part Second part"
    end

    test "handles tool use in content" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"type" => "text", "text" => "Let me help you."},
              %{"type" => "tool_use", "name" => "calculator", "input" => %{}},
              %{"type" => "text", "text" => "Done!"}
            ]
          }
        }
      }

      assert ContentExtractor.extract_text(message) == "Let me help you. [Tool: calculator] Done!"
    end

    test "handles tool result in content" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"type" => "tool_result", "tool_use_id" => "calc_123"},
              %{"type" => "text", "text" => "The result is 42"}
            ]
          }
        }
      }

      assert ContentExtractor.extract_text(message) == "[Tool Result: calc_123] The result is 42"
    end

    test "extracts text from user message" do
      message = %Message{
        type: :user,
        data: %{message: %{"content" => "User input here"}}
      }

      assert ContentExtractor.extract_text(message) == "User input here"
    end

    test "extracts text from result message" do
      message = %Message{
        type: :result,
        data: %{result: "Final result text"}
      }

      assert ContentExtractor.extract_text(message) == "Final result text"
    end

    test "returns nil for non-text messages" do
      message = %Message{
        type: :system,
        data: %{session_id: "123"}
      }

      assert ContentExtractor.extract_text(message) == nil
    end

    test "handles malformed content gracefully" do
      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => %{"unexpected" => "format"}}}
      }

      assert ContentExtractor.extract_text(message) == ~s(%{"unexpected" => "format"})
    end

    test "handles missing content field" do
      message = %Message{
        type: :assistant,
        data: %{message: %{"text" => "Alternative format"}}
      }

      assert ContentExtractor.extract_text(message) == "Alternative format"
    end

    test "filters out nil values from content arrays" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"text" => "Valid"},
              %{"unknown" => "field"},
              %{"text" => "Also valid"}
            ]
          }
        }
      }

      assert ContentExtractor.extract_text(message) == "Valid Also valid"
    end
  end

  describe "has_text?/1" do
    test "returns true for messages with text" do
      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => "Some text"}}
      }

      assert ContentExtractor.has_text?(message) == true
    end

    test "returns false for messages without text" do
      message = %Message{
        type: :system,
        data: %{session_id: "123"}
      }

      assert ContentExtractor.has_text?(message) == false
    end
  end

  describe "extract_content_text/1" do
    test "handles deeply nested content" do
      content = [
        %{"type" => "text", "text" => "Start"},
        %{"type" => "tool_use", "name" => "search"},
        %{"type" => "text", "text" => "End"}
      ]

      result = ContentExtractor.extract_content_text(content)
      assert result == "Start [Tool: search] End"
    end

    test "handles single text item in array" do
      content = [%{"text" => "Single item"}]
      assert ContentExtractor.extract_content_text(content) == "Single item"
    end

    test "handles empty array" do
      assert ContentExtractor.extract_content_text([]) == ""
    end

    test "handles non-standard formats" do
      content = %{"some" => "object"}
      assert ContentExtractor.extract_content_text(content) == ~s(%{"some" => "object"})
    end
  end
end
