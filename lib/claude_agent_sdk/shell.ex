defmodule ClaudeAgentSDK.Shell do
  @moduledoc false

  @special_chars [" ", "!", "\"", "'", "$", "`", "\\", "|", "&", ";", "(", ")", "<", ">"]

  @spec escape_arg(String.t()) :: String.t()
  def escape_arg(""), do: "\"\""

  def escape_arg(arg) when is_binary(arg) do
    if String.contains?(arg, @special_chars) do
      "\"#{String.replace(arg, "\"", "\\\"")}\""
    else
      arg
    end
  end
end
