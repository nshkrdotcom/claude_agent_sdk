defmodule ClaudeAgentSDK.Errors do
  @moduledoc """
  Structured error types for programmatic handling.

  These mirror the Python SDK's exception taxonomy while keeping Elixir-friendly
  return shapes (`{:error, reason}` where `reason` is a struct).

  ## Base Exception

  `ClaudeSDKError` serves as the conceptual base for all SDK errors. While Elixir
  doesn't have exception inheritance, this provides a common pattern for wrapping
  lower-level errors with SDK-specific context.

  ## Error Types

  - `ClaudeSDKError` - Base exception for generic SDK errors
  - `CLIConnectionError` - Connection/startup failures
  - `CLINotFoundError` - CLI executable not found
  - `ProcessError` - CLI process exited with error
  - `CLIJSONDecodeError` - JSON parsing failures
  - `MessageParseError` - Message structure parsing failures

  ## Utility Functions

  - `sdk_error?/1` - Check if an exception is an SDK error
  - `category/1` - Get the category of an SDK error

  ## Guard Macro

  Import `ClaudeAgentSDK.Errors.Guards` to use `is_sdk_error/1` in guards:

      import ClaudeAgentSDK.Errors.Guards

      try do
        ClaudeAgentSDK.query("prompt", opts)
      rescue
        e when is_sdk_error(e) ->
          Logger.error("SDK Error: \#{Exception.message(e)}")
      end

  ## Examples

      # Raising base SDK error
      raise ClaudeAgentSDK.Errors.ClaudeSDKError, message: "Operation failed"

      # Checking error type
      Errors.sdk_error?(%Errors.CLIConnectionError{message: "failed"})
      # => true

      # Getting error category
      Errors.category(%Errors.CLIConnectionError{message: "failed"})
      # => :connection
  """

  @typedoc """
  Union type of all SDK error types.
  """
  @type sdk_error ::
          __MODULE__.ClaudeSDKError.t()
          | __MODULE__.CLIConnectionError.t()
          | __MODULE__.CLINotFoundError.t()
          | __MODULE__.ProcessError.t()
          | __MODULE__.CLIJSONDecodeError.t()
          | __MODULE__.MessageParseError.t()

  @typedoc """
  Error category for grouping related errors.
  """
  @type category :: :connection | :process | :parse | :generic

  @doc """
  Check if an exception is an SDK error.

  Returns `true` if the given value is one of the SDK error types,
  `false` otherwise.

  ## Examples

      iex> Errors.sdk_error?(%Errors.ClaudeSDKError{message: "test"})
      true

      iex> Errors.sdk_error?(%Errors.CLIConnectionError{message: "failed"})
      true

      iex> Errors.sdk_error?(%RuntimeError{message: "not sdk"})
      false

      iex> Errors.sdk_error?("string")
      false
  """
  @spec sdk_error?(term()) :: boolean()
  def sdk_error?(error) do
    case error do
      %{__struct__: __MODULE__.ClaudeSDKError} -> true
      %{__struct__: __MODULE__.CLIConnectionError} -> true
      %{__struct__: __MODULE__.CLINotFoundError} -> true
      %{__struct__: __MODULE__.ProcessError} -> true
      %{__struct__: __MODULE__.CLIJSONDecodeError} -> true
      %{__struct__: __MODULE__.MessageParseError} -> true
      _ -> false
    end
  end

  @doc """
  Get the category of an SDK error.

  Categories help group related errors for handling:

  - `:connection` - Connection and CLI discovery errors
  - `:process` - CLI process execution errors
  - `:parse` - JSON and message parsing errors
  - `:generic` - Base SDK errors without specific category

  ## Examples

      iex> Errors.category(%Errors.CLIConnectionError{message: "failed"})
      :connection

      iex> Errors.category(%Errors.ProcessError{message: "crashed"})
      :process

      iex> Errors.category(%Errors.CLIJSONDecodeError{message: "bad", line: "{"})
      :parse
  """
  @spec category(sdk_error()) :: category()
  def category(error) do
    case error do
      %{__struct__: __MODULE__.CLIConnectionError} -> :connection
      %{__struct__: __MODULE__.CLINotFoundError} -> :connection
      %{__struct__: __MODULE__.ProcessError} -> :process
      %{__struct__: __MODULE__.CLIJSONDecodeError} -> :parse
      %{__struct__: __MODULE__.MessageParseError} -> :parse
      %{__struct__: __MODULE__.ClaudeSDKError} -> :generic
    end
  end
end

defmodule ClaudeAgentSDK.Errors.ClaudeSDKError do
  @moduledoc """
  Base exception for all Claude Agent SDK errors.

  This provides a common error type for catch-all handling and for wrapping
  lower-level errors with SDK-specific context.

  ## Fields

  - `:message` - Human-readable error description
  - `:cause` - Underlying error that caused this exception (optional)

  ## Examples

      # Simple error
      raise ClaudeAgentSDK.Errors.ClaudeSDKError, message: "Something went wrong"

      # Wrapping another error
      %ClaudeAgentSDK.Errors.ClaudeSDKError{
        message: "Failed to process response",
        cause: original_error
      }
  """
  @enforce_keys [:message]
  defexception [:message, :cause]

  @type t :: %__MODULE__{
          message: String.t(),
          cause: Exception.t() | term() | nil
        }
end

defmodule ClaudeAgentSDK.Errors.CLIConnectionError do
  @moduledoc """
  Raised when the SDK fails to connect to the Claude CLI process.

  Common causes include:
  - Working directory does not exist or is inaccessible
  - Claude CLI crashed during startup
  - Port/transport layer communication failure

  ## Fields

  - `:message` - Human-readable error description
  - `:cwd` - Working directory that was attempted (if available)
  - `:reason` - Underlying error reason
  """
  @enforce_keys [:message]
  defexception [:message, :cwd, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          cwd: String.t() | nil,
          reason: term()
        }
end

defmodule ClaudeAgentSDK.Errors.CLINotFoundError do
  @moduledoc """
  Raised when the Claude CLI executable cannot be found.

  This typically means Claude Code is not installed or not in the PATH.
  Install with: `npm install -g @anthropic-ai/claude-code`

  ## Fields

  - `:message` - Human-readable error description
  - `:cli_path` - Path that was searched (if available)
  """
  @enforce_keys [:message]
  defexception [:message, :cli_path]

  @type t :: %__MODULE__{
          message: String.t(),
          cli_path: String.t() | nil
        }
end

defmodule ClaudeAgentSDK.Errors.ProcessError do
  @moduledoc """
  Raised when the Claude CLI process exits with an error.

  ## Fields

  - `:message` - Human-readable error description
  - `:exit_code` - Process exit code (if available)
  - `:stderr` - Captured stderr output (if available)
  """
  @enforce_keys [:message]
  defexception [:message, :exit_code, :stderr]

  @type t :: %__MODULE__{
          message: String.t(),
          exit_code: integer() | nil,
          stderr: String.t() | nil
        }
end

defmodule ClaudeAgentSDK.Errors.CLIJSONDecodeError do
  @moduledoc """
  Raised when the SDK fails to decode JSON output from the CLI.

  This usually indicates a protocol mismatch or corrupted output stream.

  ## Fields

  - `:message` - Human-readable error description
  - `:line` - The raw line that failed to parse
  - `:original_error` - The underlying JSON decode error
  """
  @enforce_keys [:message, :line]
  defexception [:message, :line, :original_error]

  @type t :: %__MODULE__{
          message: String.t(),
          line: String.t(),
          original_error: term()
        }
end

defmodule ClaudeAgentSDK.Errors.MessageParseError do
  @moduledoc """
  Raised when a message from the CLI cannot be parsed into a known type.

  This may occur with unexpected message formats or protocol changes.

  ## Fields

  - `:message` - Human-readable error description
  - `:data` - The raw message data that failed to parse
  """
  @enforce_keys [:message]
  defexception [:message, :data]

  @type t :: %__MODULE__{
          message: String.t(),
          data: map() | nil
        }
end
