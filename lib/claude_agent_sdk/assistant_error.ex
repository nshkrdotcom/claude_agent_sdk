defmodule ClaudeAgentSDK.AssistantError do
  @moduledoc """
  Enumerates assistant-level error codes surfaced by the Claude CLI.

  Mirrors the Python SDK enum to keep client handling consistent.
  """

  @type t ::
          :authentication_failed
          | :billing_error
          | :rate_limit
          | :invalid_request
          | :server_error
          | :unknown

  @errors [
    :authentication_failed,
    :billing_error,
    :rate_limit,
    :invalid_request,
    :server_error,
    :unknown
  ]

  @doc "Returns the list of supported assistant error codes."
  @spec values() :: [t()]
  def values, do: @errors

  @doc """
  Casts a string/atom error value into the assistant error enum.

  Returns `nil` when no error is present, and `:unknown` when the value
  is present but not recognized.
  """
  @spec cast(String.t() | atom() | nil) :: t() | nil
  def cast(nil), do: nil

  def cast(error) when is_atom(error) do
    if error in @errors, do: error, else: :unknown
  end

  def cast(error) when is_binary(error) do
    error
    |> String.trim()
    |> do_cast_string()
  end

  def cast(_other), do: :unknown

  defp do_cast_string(""), do: nil
  defp do_cast_string("authentication_failed"), do: :authentication_failed
  defp do_cast_string("billing_error"), do: :billing_error
  defp do_cast_string("rate_limit"), do: :rate_limit
  defp do_cast_string("invalid_request"), do: :invalid_request
  defp do_cast_string("server_error"), do: :server_error
  defp do_cast_string("unknown"), do: :unknown
  defp do_cast_string(_unknown), do: :unknown
end
