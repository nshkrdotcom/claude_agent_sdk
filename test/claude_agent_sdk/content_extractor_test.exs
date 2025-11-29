defmodule ClaudeAgentSDK.ContentExtractorTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{ContentExtractor, Message}

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

  describe "structured outputs" do
    test "prefers result text when structured_output is also present" do
      message = %Message{
        type: :result,
        data: %{result: "plain result", structured_output: %{"foo" => "bar"}}
      }

      assert ContentExtractor.extract_text(message) == "plain result"
    end

    test "falls back to structured_output when result text missing" do
      message = %Message{
        type: :result,
        data: %{structured_output: %{"foo" => "bar"}}
      }

      assert ContentExtractor.extract_text(message) == ~s({"foo":"bar"})
    end

    test "has_text?/1 returns true for structured outputs" do
      message = %Message{
        type: :result,
        data: %{structured_output: %{"foo" => "bar"}}
      }

      assert ContentExtractor.has_text?(message)
    end
  end

  describe "extract_all_text/2" do
    test "extracts and joins text from multiple messages" do
      messages = [
        %Message{type: :assistant, data: %{message: %{"content" => "Hello"}}},
        %Message{type: :assistant, data: %{message: %{"content" => "World"}}},
        # No text content
        %Message{type: :system, data: %{}}
      ]

      result = ContentExtractor.extract_all_text(messages)
      assert result == "Hello\nWorld"
    end

    test "uses custom separator" do
      messages = [
        %Message{type: :assistant, data: %{message: %{"content" => "Hello"}}},
        %Message{type: :assistant, data: %{message: %{"content" => "World"}}}
      ]

      result = ContentExtractor.extract_all_text(messages, " | ")
      assert result == "Hello | World"
    end

    test "filters out messages without text" do
      messages = [
        %Message{type: :assistant, data: %{message: %{"content" => "Hello"}}},
        %Message{type: :system, data: %{session_id: "123"}},
        %Message{type: :assistant, data: %{message: %{"content" => "World"}}}
      ]

      result = ContentExtractor.extract_all_text(messages)
      assert result == "Hello\nWorld"
    end

    test "handles empty message list" do
      result = ContentExtractor.extract_all_text([])
      assert result == ""
    end
  end

  describe "summarize/2" do
    test "returns full text when within limit" do
      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => "Short text"}}
      }

      result = ContentExtractor.summarize(message, 100)
      assert result == "Short text"
    end

    test "truncates long text with ellipsis" do
      long_text = String.duplicate("a", 100)

      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => long_text}}
      }

      result = ContentExtractor.summarize(message, 20)
      assert String.length(result) == 20
      assert String.ends_with?(result, "...")
    end

    test "handles messages without text content" do
      message = %Message{
        type: :system,
        data: %{session_id: "123"}
      }

      result = ContentExtractor.summarize(message, 100)
      assert result == "[No text content]"
    end

    test "uses default max length of 100" do
      long_text = String.duplicate("a", 200)

      message = %Message{
        type: :assistant,
        data: %{message: %{"content" => long_text}}
      }

      result = ContentExtractor.summarize(message)
      assert String.length(result) == 100
      assert String.ends_with?(result, "...")
    end
  end

  describe "enhanced tool handling" do
    test "formats tool use with input summary" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"type" => "text", "text" => "Let me help:"},
              %{"type" => "tool_use", "name" => "bash", "input" => %{"command" => "ls"}},
              %{"type" => "text", "text" => "Done!"}
            ]
          }
        }
      }

      result = ContentExtractor.extract_text(message)
      assert result == "Let me help: [Tool: bash command: ls] Done!"
    end

    test "handles tool use with complex input" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{
                "type" => "tool_use",
                "name" => "read_file",
                "input" => %{"path" => "/very/long/path/to/file.txt", "encoding" => "utf-8"}
              }
            ]
          }
        }
      }

      result = ContentExtractor.extract_text(message)
      assert String.contains?(result, "[Tool: read_file")
      assert String.contains?(result, "path:") or String.contains?(result, "encoding:")
    end

    test "handles tool use with empty input" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"type" => "tool_use", "name" => "get_time", "input" => %{}}
            ]
          }
        }
      }

      result = ContentExtractor.extract_text(message)
      assert result == "[Tool: get_time]"
    end

    test "handles tool result with content" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => "calc_123",
                "content" => "The result is 42"
              },
              %{"type" => "text", "text" => "The calculation is complete."}
            ]
          }
        }
      }

      result = ContentExtractor.extract_text(message)
      assert result == "[Tool Result calc_123: The result is 42] The calculation is complete."
    end

    test "handles tool result with long content" do
      long_content = String.duplicate("x", 100)

      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"type" => "tool_result", "tool_use_id" => "test_456", "content" => long_content}
            ]
          }
        }
      }

      result = ContentExtractor.extract_text(message)
      assert String.contains?(result, "[Tool Result test_456:")
      assert String.contains?(result, "...")
      assert String.length(result) < String.length(long_content) + 50
    end

    test "handles tool result without content" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"type" => "tool_result", "tool_use_id" => "calc_123"}
            ]
          }
        }
      }

      result = ContentExtractor.extract_text(message)
      assert result == "[Tool Result: calc_123]"
    end
  end

  describe "edge cases and robustness" do
    test "handles malformed tool objects gracefully" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              # Missing name
              %{"type" => "tool_use"},
              # Missing tool_use_id
              %{"type" => "tool_result", "content" => "result"},
              %{"type" => "unknown_type", "text" => "fallback"}
            ]
          }
        }
      }

      result = ContentExtractor.extract_text(message)
      assert String.contains?(result, "[Tool: unknown")
      assert String.contains?(result, "[Tool Result unknown:")
      assert String.contains?(result, "fallback")
    end

    test "handles mixed content types" do
      message = %Message{
        type: :assistant,
        data: %{
          message: %{
            "content" => [
              %{"type" => "text", "text" => "Start"},
              %{"unknown_field" => "ignored"},
              %{"type" => "tool_use", "name" => "test"},
              # Alternative format
              %{"text" => "direct text"},
              %{"type" => "text", "text" => "End"}
            ]
          }
        }
      }

      result = ContentExtractor.extract_text(message)
      assert String.contains?(result, "Start")
      assert String.contains?(result, "[Tool: test]")
      assert String.contains?(result, "direct text")
      assert String.contains?(result, "End")
    end

    test "handles nested content structures" do
      complex_content = [
        %{"type" => "text", "text" => "Processing:"},
        %{
          "type" => "tool_use",
          "name" => "complex_tool",
          "input" => %{
            "nested" => %{"deep" => "value"},
            "array" => [1, 2, 3],
            "simple" => "test"
          }
        }
      ]

      result = ContentExtractor.extract_content_text(complex_content)
      assert String.contains?(result, "Processing:")
      assert String.contains?(result, "[Tool: complex_tool")
    end

    test "handles user message content" do
      message = %Message{
        type: :user,
        data: %{message: %{"content" => "User input here"}}
      }

      result = ContentExtractor.extract_text(message)
      assert result == "User input here"
    end

    test "handles result message content" do
      message = %Message{
        type: :result,
        data: %{result: "Final result text"}
      }

      result = ContentExtractor.extract_text(message)
      assert result == "Final result text"
    end

    test "handles direct content maps" do
      content_map = %{"content" => "Direct content"}

      result = ContentExtractor.extract_text(content_map)
      assert result == "Direct content"
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
