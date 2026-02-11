defmodule ClaudeAgentSDK.Config.Env do
  @moduledoc """
  Canonical registry of all environment variable names the SDK reads.

  Using this module instead of bare string literals eliminates typo risk
  and provides a single grep-able registry:

      System.get_env(ClaudeAgentSDK.Config.Env.anthropic_api_key())
  """

  # -- Anthropic auth --------------------------------------------------------

  @doc "Anthropic API key env var (`\"ANTHROPIC_API_KEY\"`)."
  @spec anthropic_api_key() :: String.t()
  def anthropic_api_key, do: "ANTHROPIC_API_KEY"

  @doc "OAuth token env var (`\"CLAUDE_AGENT_OAUTH_TOKEN\"`)."
  @spec oauth_token() :: String.t()
  def oauth_token, do: "CLAUDE_AGENT_OAUTH_TOKEN"

  # -- provider selectors ----------------------------------------------------

  @doc "Bedrock provider flag (`\"CLAUDE_AGENT_USE_BEDROCK\"`)."
  @spec use_bedrock() :: String.t()
  def use_bedrock, do: "CLAUDE_AGENT_USE_BEDROCK"

  @doc "Vertex AI provider flag (`\"CLAUDE_AGENT_USE_VERTEX\"`)."
  @spec use_vertex() :: String.t()
  def use_vertex, do: "CLAUDE_AGENT_USE_VERTEX"

  # -- SDK control -----------------------------------------------------------

  @doc "SDK entrypoint identifier (`\"CLAUDE_CODE_ENTRYPOINT\"`)."
  @spec entrypoint() :: String.t()
  def entrypoint, do: "CLAUDE_CODE_ENTRYPOINT"

  @doc "SDK version injection (`\"CLAUDE_AGENT_SDK_VERSION\"`)."
  @spec sdk_version() :: String.t()
  def sdk_version, do: "CLAUDE_AGENT_SDK_VERSION"

  @doc "File checkpointing flag (`\"CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING\"`)."
  @spec file_checkpointing() :: String.t()
  def file_checkpointing,
    do: "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"

  @doc "Stream close timeout override (`\"CLAUDE_CODE_STREAM_CLOSE_TIMEOUT\"`)."
  @spec stream_close_timeout() :: String.t()
  def stream_close_timeout, do: "CLAUDE_CODE_STREAM_CLOSE_TIMEOUT"

  @doc "Skip version check flag (`\"CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK\"`)."
  @spec skip_version_check() :: String.t()
  def skip_version_check,
    do: "CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK"

  # -- cloud providers -------------------------------------------------------

  @doc "`\"AWS_ACCESS_KEY_ID\"`"
  @spec aws_access_key_id() :: String.t()
  def aws_access_key_id, do: "AWS_ACCESS_KEY_ID"

  @doc "`\"AWS_PROFILE\"`"
  @spec aws_profile() :: String.t()
  def aws_profile, do: "AWS_PROFILE"

  @doc "`\"GOOGLE_APPLICATION_CREDENTIALS\"`"
  @spec gcp_credentials() :: String.t()
  def gcp_credentials, do: "GOOGLE_APPLICATION_CREDENTIALS"

  @doc "`\"GOOGLE_CLOUD_PROJECT\"`"
  @spec gcp_project() :: String.t()
  def gcp_project, do: "GOOGLE_CLOUD_PROJECT"

  # -- CI / test -------------------------------------------------------------

  @doc "`\"CI\"`"
  @spec ci() :: String.t()
  def ci, do: "CI"

  @doc "`\"LIVE_MODE\"`"
  @spec live_mode() :: String.t()
  def live_mode, do: "LIVE_MODE"

  @doc "`\"LIVE_TESTS\"`"
  @spec live_tests() :: String.t()
  def live_tests, do: "LIVE_TESTS"

  # -- base env pass-through -------------------------------------------------

  @doc """
  Environment variables automatically forwarded to CLI subprocesses.

  Returns `["CLAUDE_AGENT_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "PATH", "HOME"]`.
  """
  @spec passthrough_vars() :: [String.t()]
  def passthrough_vars do
    [oauth_token(), anthropic_api_key(), "PATH", "HOME"]
  end
end
