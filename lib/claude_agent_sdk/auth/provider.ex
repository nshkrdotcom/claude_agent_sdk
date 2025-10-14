defmodule ClaudeAgentSDK.Auth.Provider do
  @moduledoc """
  Multi-provider authentication abstraction.

  Supports:
  - Anthropic (via `claude setup-token`)
  - AWS Bedrock (via AWS credentials)
  - GCP Vertex AI (via GCP credentials)
  """

  @type provider :: :anthropic | :bedrock | :vertex

  alias ClaudeAgentSDK.Auth.Providers.{Anthropic, Bedrock, Vertex}

  @doc """
  Sets up authentication token for the specified provider.

  Returns `{:ok, token, expiry}` or `{:error, reason}`.
  """
  @spec setup_token(provider()) :: {:ok, String.t(), DateTime.t() | nil} | {:error, term()}
  def setup_token(:anthropic), do: Anthropic.setup_token()
  def setup_token(:bedrock), do: Bedrock.setup_token()
  def setup_token(:vertex), do: Vertex.setup_token()
end
