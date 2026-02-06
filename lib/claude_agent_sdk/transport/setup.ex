defmodule ClaudeAgentSDK.Transport.Setup do
  @moduledoc false

  @spec validate_cwd(String.t() | nil) :: :ok | {:error, {:cwd_not_found, String.t()}}
  def validate_cwd(nil), do: :ok

  def validate_cwd(cwd) when is_binary(cwd) do
    if File.dir?(cwd) do
      :ok
    else
      {:error, {:cwd_not_found, cwd}}
    end
  end

  def validate_cwd(_cwd), do: :ok
end
