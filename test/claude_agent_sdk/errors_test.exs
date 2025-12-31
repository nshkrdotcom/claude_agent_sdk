defmodule ClaudeAgentSDK.ErrorsTest do
  @moduledoc """
  Tests for error types and base exception hierarchy.
  """

  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Errors.{
    ClaudeSDKError,
    CLIConnectionError,
    CLIJSONDecodeError,
    CLINotFoundError,
    MessageParseError,
    ProcessError
  }

  describe "ClaudeSDKError (base exception)" do
    test "can be raised with just a message" do
      assert_raise ClaudeSDKError, "Something went wrong", fn ->
        raise ClaudeSDKError, message: "Something went wrong"
      end
    end

    test "can be raised with message and cause" do
      cause = %RuntimeError{message: "underlying error"}

      error = %ClaudeSDKError{message: "Wrapped error", cause: cause}

      assert error.message == "Wrapped error"
      assert error.cause == cause
    end

    test "implements Exception behaviour" do
      error = %ClaudeSDKError{message: "Test error", cause: nil}
      assert Exception.message(error) == "Test error"
    end

    test "can be caught as base type for all SDK errors" do
      # All specific errors can be pattern matched, but for catch-all
      # users can now use ClaudeSDKError as a base type concept
      errors = [
        %CLIConnectionError{message: "Connection failed"},
        %CLINotFoundError{message: "CLI not found"},
        %ProcessError{message: "Process exited"},
        %CLIJSONDecodeError{message: "JSON decode failed", line: "bad"},
        %MessageParseError{message: "Parse failed"}
      ]

      for error <- errors do
        assert is_exception(error)
        assert is_binary(Exception.message(error))
      end
    end
  end

  describe "CLIConnectionError" do
    test "has required message field" do
      error = %CLIConnectionError{message: "Failed to connect"}
      assert error.message == "Failed to connect"
    end

    test "has optional cwd and reason fields" do
      error = %CLIConnectionError{
        message: "Connection failed",
        cwd: "/some/path",
        reason: :enoent
      }

      assert error.cwd == "/some/path"
      assert error.reason == :enoent
    end
  end

  describe "CLINotFoundError" do
    test "has required message field" do
      error = %CLINotFoundError{message: "Claude CLI not found"}
      assert error.message == "Claude CLI not found"
    end

    test "has optional cli_path field" do
      error = %CLINotFoundError{
        message: "Not found",
        cli_path: "/usr/bin/claude"
      }

      assert error.cli_path == "/usr/bin/claude"
    end
  end

  describe "ProcessError" do
    test "has required message field" do
      error = %ProcessError{message: "Process crashed"}
      assert error.message == "Process crashed"
    end

    test "has optional exit_code and stderr fields" do
      error = %ProcessError{
        message: "Command failed",
        exit_code: 1,
        stderr: "Error output"
      }

      assert error.exit_code == 1
      assert error.stderr == "Error output"
    end
  end

  describe "CLIJSONDecodeError" do
    test "has required message and line fields" do
      error = %CLIJSONDecodeError{
        message: "Invalid JSON",
        line: "{invalid"
      }

      assert error.message == "Invalid JSON"
      assert error.line == "{invalid"
    end

    test "has optional original_error field" do
      error = %CLIJSONDecodeError{
        message: "Decode failed",
        line: "bad json",
        original_error: %Jason.DecodeError{}
      }

      assert match?(%Jason.DecodeError{}, error.original_error)
    end
  end

  describe "MessageParseError" do
    test "has required message field" do
      error = %MessageParseError{message: "Unknown message type"}
      assert error.message == "Unknown message type"
    end

    test "has optional data field" do
      error = %MessageParseError{
        message: "Parse failed",
        data: %{"type" => "unknown"}
      }

      assert error.data == %{"type" => "unknown"}
    end
  end
end
