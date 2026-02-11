defmodule ClaudeAgentSDK.Auth.TokenStore do
  @moduledoc """
  Persistent token storage for authentication.

  Supports multiple storage backends:
  - File-based (default): ~/.claude_sdk/token.json
  - Application environment: :claude_agent_sdk, :auth_token
  - Custom: User-provided module implementing this behavior
  """

  @type token_data :: %{
          token: String.t(),
          expiry: DateTime.t() | nil,
          provider: atom()
        }

  @callback save(token_data()) :: :ok | {:error, term()}
  @callback load() :: {:ok, token_data()} | {:error, :not_found | term()}
  @callback clear() :: :ok

  alias ClaudeAgentSDK.Config.Auth, as: AuthConfig

  ## Default File-Based Implementation

  @doc """
  Saves token data to storage.
  """
  @spec save(token_data()) :: :ok | {:error, term()}
  def save(data) do
    path = storage_path()

    # Ensure directory exists
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Serialize data
    json =
      Jason.encode!(%{
        token: data.token,
        expiry: data.expiry && DateTime.to_iso8601(data.expiry),
        provider: data.provider,
        created_at: DateTime.to_iso8601(DateTime.utc_now())
      })

    # Write with restricted permissions (user-only read/write)
    case File.write(path, json) do
      :ok ->
        # Set file permissions to 0600 (user read/write only)
        File.chmod!(path, 0o600)
        :ok

      error ->
        error
    end
  end

  @doc """
  Loads token data from storage.
  """
  @spec load() :: {:ok, token_data()} | {:error, :not_found | term()}
  def load do
    path = storage_path()

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, data} ->
            token_data = %{
              token: data["token"],
              expiry: parse_expiry(data["expiry"]),
              provider: parse_provider(data["provider"])
            }

            {:ok, token_data}

          {:error, reason} ->
            {:error, {:invalid_json, reason}}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clears stored token data.
  """
  @spec clear() :: :ok
  def clear do
    path = storage_path()
    File.rm(path)
    :ok
  end

  defp storage_path do
    Application.get_env(:claude_agent_sdk, :auth_file_path, AuthConfig.token_store_path())
    |> Path.expand()
  end

  defp parse_expiry(nil), do: nil

  defp parse_expiry(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_provider("anthropic"), do: :anthropic
  defp parse_provider("bedrock"), do: :bedrock
  defp parse_provider("vertex"), do: :vertex
  defp parse_provider(nil), do: :anthropic
  defp parse_provider(_unknown), do: :anthropic
end
