defmodule ClaudeAgentSDK.Errors do
  @moduledoc """
  Structured error types for programmatic handling.

  These mirror the Python SDK's exception taxonomy while keeping Elixir-friendly
  return shapes (`{:error, reason}` where `reason` is a struct).
  """
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
