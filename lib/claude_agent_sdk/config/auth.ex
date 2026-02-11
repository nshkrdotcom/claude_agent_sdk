defmodule ClaudeAgentSDK.Config.Auth do
  @moduledoc """
  Authentication configuration: file paths, TTLs, and token prefixes.

  Runtime overrides via Application config:

      config :claude_agent_sdk, ClaudeAgentSDK.Config.Auth,
        token_store_path: "~/.my_sdk/token.json",
        session_max_age_days: 60
  """

  @app :claude_agent_sdk

  @spec get(atom(), term()) :: term()
  defp get(key, default) do
    @app
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end

  # -- file paths ------------------------------------------------------------

  @doc "Default token storage path (default: `~/.claude_sdk/token.json`)."
  @spec token_store_path() :: String.t()
  def token_store_path,
    do: get(:token_store_path, "~/.claude_sdk/token.json")

  @doc "Default session storage directory (default: `~/.claude_sdk/sessions`)."
  @spec session_storage_dir() :: String.t()
  def session_storage_dir,
    do: get(:session_storage_dir, "~/.claude_sdk/sessions")

  # -- TTLs ------------------------------------------------------------------

  @doc "Token validity period in days (default: 365)."
  @spec token_ttl_days() :: pos_integer()
  def token_ttl_days, do: get(:token_ttl_days, 365)

  @doc "Maximum session age in days (default: 30)."
  @spec session_max_age_days() :: pos_integer()
  def session_max_age_days, do: get(:session_max_age_days, 30)

  # -- token prefixes --------------------------------------------------------

  @doc "OAuth token prefix for validation."
  @spec oauth_token_prefix() :: String.t()
  def oauth_token_prefix, do: "sk-ant-oat01-"

  @doc "API key prefix for validation."
  @spec api_key_prefix() :: String.t()
  def api_key_prefix, do: "sk-ant-"

  # -- cloud credential paths ------------------------------------------------

  @doc "AWS credentials file path (default: `~/.aws/credentials`)."
  @spec aws_credentials_path() :: String.t()
  def aws_credentials_path,
    do: get(:aws_credentials_path, "~/.aws/credentials")

  @doc "GCP application default credentials path."
  @spec gcp_credentials_path() :: String.t()
  def gcp_credentials_path do
    get(
      :gcp_credentials_path,
      "~/.config/gcloud/application_default_credentials.json"
    )
  end

  # -- provider names --------------------------------------------------------

  @doc "List of supported auth provider atoms."
  @spec providers() :: [:anthropic | :bedrock | :vertex]
  def providers, do: [:anthropic, :bedrock, :vertex]
end
