defmodule ClaudeCodeSDKTest do
  use ExUnit.Case
  doctest ClaudeCodeSDK

  alias ClaudeCodeSDK.{Options, Message}

  describe "query/2" do
    test "returns a stream" do
      # This test would require mocking the CLI process
      # For now, we'll test that it returns an enumerable
      result = ClaudeCodeSDK.query("test prompt")
      assert is_function(result, 2)
    end

    test "accepts options" do
      opts = %Options{max_turns: 3, output_format: :json}
      result = ClaudeCodeSDK.query("test prompt", opts)
      assert is_function(result, 2)
    end
  end

  describe "continue/2" do
    test "continues without prompt" do
      result = ClaudeCodeSDK.continue()
      assert is_function(result, 2)
    end

    test "continues with prompt" do
      result = ClaudeCodeSDK.continue("additional prompt")
      assert is_function(result, 2)
    end
  end

  describe "resume/3" do
    test "resumes with session ID" do
      result = ClaudeCodeSDK.resume("test-session-id")
      assert is_function(result, 2)
    end

    test "resumes with session ID and prompt" do
      result = ClaudeCodeSDK.resume("test-session-id", "additional prompt")
      assert is_function(result, 2)
    end
  end
end
