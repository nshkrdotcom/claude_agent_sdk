defmodule ClaudeAgentSDK.Errors.Guards do
  @moduledoc """
  Guard macros for pattern matching SDK errors.

  Provides `is_sdk_error/1` macro that can be used in guards and function heads
  to match any SDK error type.

  ## Usage

      import ClaudeAgentSDK.Errors.Guards

      # In function heads
      def handle_error(e) when is_sdk_error(e) do
        Logger.error("SDK error: \#{Exception.message(e)}")
      end

      # In try/rescue
      try do
        ClaudeAgentSDK.query("prompt", opts)
      rescue
        e when is_sdk_error(e) ->
          {:error, :sdk_failure}
      end

  ## Why a Guard Macro?

  While `Errors.sdk_error?/1` works for runtime checks, Elixir guards are
  compile-time constructs that only allow certain expressions. This macro
  expands to valid guard expressions that match all SDK error struct types.
  """

  @doc """
  Guard macro to check if a value is an SDK error.

  Can be used in function heads and guard clauses.

  ## Examples

      # Function head guard
      def log_error(e) when is_sdk_error(e), do: Logger.error(Exception.message(e))

      # Case clause guard
      case error do
        e when is_sdk_error(e) -> handle_sdk_error(e)
        _ -> handle_other(error)
      end
  """
  defmacro is_sdk_error(error) do
    quote do
      is_struct(unquote(error), ClaudeAgentSDK.Errors.ClaudeSDKError) or
        is_struct(unquote(error), ClaudeAgentSDK.Errors.CLIConnectionError) or
        is_struct(unquote(error), ClaudeAgentSDK.Errors.CLINotFoundError) or
        is_struct(unquote(error), ClaudeAgentSDK.Errors.ProcessError) or
        is_struct(unquote(error), ClaudeAgentSDK.Errors.CLIJSONDecodeError) or
        is_struct(unquote(error), ClaudeAgentSDK.Errors.MessageParseError)
    end
  end
end
