defmodule ClaudeAgentSDK.Errors do
  @moduledoc """
  Structured error types for programmatic handling.

  These mirror the Python SDK's exception taxonomy while keeping Elixir-friendly
  return shapes (`{:error, reason}` where `reason` is a struct).
  """
end

defmodule ClaudeAgentSDK.Errors.CLIConnectionError do
  @moduledoc false
  @enforce_keys [:message]
  defexception [:message, :cwd, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          cwd: String.t() | nil,
          reason: term()
        }
end

defmodule ClaudeAgentSDK.Errors.CLINotFoundError do
  @moduledoc false
  @enforce_keys [:message]
  defexception [:message, :cli_path]

  @type t :: %__MODULE__{
          message: String.t(),
          cli_path: String.t() | nil
        }
end

defmodule ClaudeAgentSDK.Errors.ProcessError do
  @moduledoc false
  @enforce_keys [:message]
  defexception [:message, :exit_code, :stderr]

  @type t :: %__MODULE__{
          message: String.t(),
          exit_code: integer() | nil,
          stderr: String.t() | nil
        }
end

defmodule ClaudeAgentSDK.Errors.CLIJSONDecodeError do
  @moduledoc false
  @enforce_keys [:message, :line]
  defexception [:message, :line, :original_error]

  @type t :: %__MODULE__{
          message: String.t(),
          line: String.t(),
          original_error: term()
        }
end

defmodule ClaudeAgentSDK.Errors.MessageParseError do
  @moduledoc false
  @enforce_keys [:message]
  defexception [:message, :data]

  @type t :: %__MODULE__{
          message: String.t(),
          data: map() | nil
        }
end
