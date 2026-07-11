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
  alias ClaudeAgentSDK.GovernedLaunch

  ## Default File-Based Implementation

  @doc """
  Saves token data to storage.
  """
  @spec save(token_data(), keyword()) :: :ok | {:error, term()}
  def save(data, opts \\ []) do
    path = storage_path!(opts)

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

    # Write to a sibling temp file, restrict to 0600 while it is still
    # empty, then write + rename into place — the token is never on disk
    # with permissions looser than user-only.
    tmp_path = path <> ".tmp"

    with :ok <- File.touch(tmp_path),
         :ok <- File.chmod(tmp_path, 0o600),
         :ok <- File.write(tmp_path, json),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      error ->
        _ = File.rm(tmp_path)
        error
    end
  end

  @doc """
  Loads token data from storage.
  """
  @spec load(keyword()) :: {:ok, token_data()} | {:error, :not_found | term()}
  def load(opts \\ []) do
    path = storage_path!(opts)

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
  @spec clear(keyword()) :: :ok
  def clear(opts \\ []) do
    path = storage_path!(opts)
    File.rm(path)
    :ok
  end

  @doc false
  @spec storage_path(keyword()) :: String.t()
  def storage_path(opts \\ []) do
    storage_path!(opts)
  end

  defp storage_path!(opts) when is_list(opts) do
    case GovernedLaunch.token_store_path(opts) do
      {:ok, path} ->
        path

      {:error, :missing_governed_authority} ->
        standalone_storage_path()

      {:error, reason} ->
        raise ArgumentError, "invalid governed token store path: #{inspect(reason)}"
    end
  end

  defp standalone_storage_path do
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
