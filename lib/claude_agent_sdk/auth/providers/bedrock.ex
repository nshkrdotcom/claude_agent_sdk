defmodule ClaudeAgentSDK.Auth.Providers.Bedrock do
  @moduledoc """
  AWS Bedrock authentication.

  Uses AWS credentials instead of Anthropic API keys.
  Requires CLAUDE_AGENT_USE_BEDROCK=1 environment variable.
  """

  alias ClaudeAgentSDK.Config.{Auth, Env}

  @doc """
  Validates AWS Bedrock authentication.

  Returns {:ok, "aws", nil} if AWS credentials are available.
  No token needed - CLI uses AWS SDK authentication.
  """
  @spec setup_token() :: {:ok, String.t(), nil} | {:error, term()}
  def setup_token do
    if aws_credentials_available?() do
      # Bedrock doesn't use tokens, authentication via AWS credentials
      {:ok, "aws-bedrock", nil}
    else
      {:error,
       """
       AWS Bedrock authentication not configured.

       Set environment variables:
         export CLAUDE_AGENT_USE_BEDROCK=1
         export AWS_ACCESS_KEY_ID=your_key
         export AWS_SECRET_ACCESS_KEY=your_secret
         export AWS_REGION=us-west-2

       Or configure AWS CLI:
         aws configure
       """}
    end
  end

  defp aws_credentials_available? do
    System.get_env(Env.aws_access_key_id()) != nil ||
      System.get_env(Env.aws_profile()) != nil ||
      File.exists?(Path.expand(Auth.aws_credentials_path()))
  end
end
