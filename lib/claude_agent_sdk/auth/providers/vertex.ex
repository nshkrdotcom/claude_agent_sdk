defmodule ClaudeAgentSDK.Auth.Providers.Vertex do
  @moduledoc """
  Google Vertex AI authentication.

  Uses GCP credentials instead of Anthropic API keys.
  Requires CLAUDE_AGENT_USE_VERTEX=1 environment variable.
  """

  alias ClaudeAgentSDK.Config.{Auth, Env}

  @doc """
  Validates Google Vertex AI authentication.

  Returns {:ok, "gcp", nil} if GCP credentials are available.
  No token needed - CLI uses GCP SDK authentication.
  """
  @spec setup_token() :: {:ok, String.t(), nil} | {:error, term()}
  def setup_token do
    if gcp_credentials_available?() do
      # Vertex doesn't use tokens, authentication via GCP credentials
      {:ok, "gcp-vertex", nil}
    else
      {:error,
       """
       Google Vertex AI authentication not configured.

       Set environment variables:
         export CLAUDE_AGENT_USE_VERTEX=1
         export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
         export GOOGLE_CLOUD_PROJECT=your-project-id

       Or use gcloud CLI:
         gcloud auth application-default login
       """}
    end
  end

  defp gcp_credentials_available? do
    System.get_env(Env.gcp_credentials()) != nil ||
      System.get_env(Env.gcp_project()) != nil ||
      File.exists?(Path.expand(Auth.gcp_credentials_path()))
  end
end
