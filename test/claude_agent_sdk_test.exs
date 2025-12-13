defmodule ClaudeAgentSDKTest do
  use ExUnit.Case
  doctest ClaudeAgentSDK

  @moduletag :mock

  alias ClaudeAgentSDK.{Mock, Options}

  setup do
    # Clear any previous mock responses before each test
    Mock.clear_responses()
    :ok
  end

  describe "query/2" do
    test "returns a stream with mocked responses" do
      # Set up a specific mock response
      Mock.set_response("test prompt", [
        %{
          "type" => "system",
          "subtype" => "init",
          "session_id" => "test-123",
          "model" => "claude-test",
          "tools" => [],
          "cwd" => "/test",
          "permissionMode" => "default",
          "apiKeySource" => "test"
        },
        %{
          "type" => "assistant",
          "message" => %{
            "role" => "assistant",
            "content" => "Test response"
          },
          "session_id" => "test-123"
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "test-123",
          "total_cost_usd" => 0.001,
          "duration_ms" => 100,
          "duration_api_ms" => 50,
          "num_turns" => 1,
          "is_error" => false
        }
      ])

      messages = ClaudeAgentSDK.query("test prompt") |> Enum.to_list()

      assert length(messages) == 3
      assert Enum.at(messages, 0).type == :system
      assert Enum.at(messages, 1).type == :assistant
      assert Enum.at(messages, 2).type == :result

      # Check assistant message content
      assistant_msg = Enum.at(messages, 1)
      assert assistant_msg.data.message["content"] == "Test response"
    end

    test "accepts options" do
      opts = %Options{max_turns: 3, output_format: :json}
      messages = ClaudeAgentSDK.query("test prompt", opts) |> Enum.to_list()

      assert length(messages) > 0
      assert Enum.any?(messages, &(&1.type == :assistant))
    end
  end

  describe "continue/2" do
    test "continues without prompt" do
      result = ClaudeAgentSDK.continue()
      assert is_function(result, 2)
    end

    test "continues with prompt" do
      result = ClaudeAgentSDK.continue("additional prompt")
      assert is_function(result, 2)
    end
  end

  describe "resume/3" do
    test "resumes with session ID" do
      result = ClaudeAgentSDK.resume("test-session-id")
      assert is_function(result, 2)
    end

    test "resumes with session ID and prompt" do
      result = ClaudeAgentSDK.resume("test-session-id", "additional prompt")
      assert is_function(result, 2)
    end
  end
end
