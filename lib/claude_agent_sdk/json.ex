defmodule ClaudeAgentSDK.JSON do
  @moduledoc """
  JSON decoding wrapper for Claude Agent SDK.

  Prefers OTP's built-in `:json` decoder when available and falls back to `Jason`
  on older OTP releases.
  """

  @spec decode(String.t()) :: {:ok, term()} | {:error, :invalid_json}
  def decode(json_string) when is_binary(json_string) do
    if function_exported?(:json, :decode, 1) do
      decode_with_otp(json_string)
    else
      decode_with_jason(json_string)
    end
  end

  defp decode_with_otp(json_string) do
    {:ok, :json.decode(json_string)}
  rescue
    _error ->
      {:error, :invalid_json}
  catch
    _kind, _reason ->
      {:error, :invalid_json}
  end

  defp decode_with_jason(json_string) do
    case Jason.decode(json_string) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _reason} ->
        {:error, :invalid_json}
    end
  end
end
