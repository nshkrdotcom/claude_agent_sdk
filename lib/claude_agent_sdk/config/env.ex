defmodule ClaudeAgentSDK.Config.Env do
  @moduledoc """
  Canonical registry of all environment variable names the SDK reads.

  Using this module instead of bare string literals eliminates typo risk
  and provides a single grep-able registry:

      ClaudeAgentSDK.Env.get(ClaudeAgentSDK.Config.Env.anthropic_api_key())
  """

  # -- Anthropic auth --------------------------------------------------------

  @doc "Anthropic API key env var (`\"ANTHROPIC_API_KEY\"`)."
  @spec anthropic_api_key() :: String.t()
  def anthropic_api_key, do: "ANTHROPIC_API_KEY"

  @doc "Anthropic auth token env var (`\"ANTHROPIC_AUTH_TOKEN\"`)."
  @spec anthropic_auth_token() :: String.t()
  def anthropic_auth_token, do: "ANTHROPIC_AUTH_TOKEN"

  @doc "Anthropic-compatible base URL env var (`\"ANTHROPIC_BASE_URL\"`)."
  @spec anthropic_base_url() :: String.t()
  def anthropic_base_url, do: "ANTHROPIC_BASE_URL"

  @doc "Anthropic model env var (`\"ANTHROPIC_MODEL\"`)."
  @spec anthropic_model() :: String.t()
  def anthropic_model, do: "ANTHROPIC_MODEL"

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

  @doc "SDK model backend selector (`\"CLAUDE_AGENT_PROVIDER_BACKEND\"`)."
  @spec provider_backend() :: String.t()
  def provider_backend, do: "CLAUDE_AGENT_PROVIDER_BACKEND"

  @doc "SDK external model overrides JSON (`\"CLAUDE_AGENT_EXTERNAL_MODEL_OVERRIDES\"`)."
  @spec external_model_overrides() :: String.t()
  def external_model_overrides, do: "CLAUDE_AGENT_EXTERNAL_MODEL_OVERRIDES"

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

  @doc "Legacy Claude Code internal env var that must not be inherited."
  @spec claudecode() :: String.t()
  def claudecode, do: "CLAUDECODE"

  @doc "Skip version check flag (`\"CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK\"`)."
  @spec skip_version_check() :: String.t()
  def skip_version_check,
    do: "CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK"

  @doc "W3C trace context parent header env var (`\"TRACEPARENT\"`)."
  @spec traceparent() :: String.t()
  def traceparent, do: "TRACEPARENT"

  @doc "W3C trace context state header env var (`\"TRACESTATE\"`)."
  @spec tracestate() :: String.t()
  def tracestate, do: "TRACESTATE"

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
    [
      oauth_token(),
      anthropic_api_key(),
      anthropic_auth_token(),
      anthropic_base_url(),
      traceparent(),
      tracestate(),
      "PATH",
      "HOME"
    ]
  end

  # -- runtime snapshot allowlist ---------------------------------------------

  @doc """
  Every environment variable name the SDK reads, as a flat list.

  This is the allowlist behind the `config/runtime.exs` snapshot: only these
  names (plus the `CLAUDE_`/`ANTHROPIC_` prefixes, see `snapshot/1`) are
  copied from the OS environment into Application config. Add new variables
  here when introducing a new read.
  """
  @spec all_known_vars() :: [String.t()]
  def all_known_vars do
    [
      anthropic_api_key(),
      anthropic_auth_token(),
      anthropic_base_url(),
      anthropic_model(),
      oauth_token(),
      use_bedrock(),
      use_vertex(),
      provider_backend(),
      external_model_overrides(),
      entrypoint(),
      sdk_version(),
      file_checkpointing(),
      stream_close_timeout(),
      claudecode(),
      skip_version_check(),
      traceparent(),
      tracestate(),
      aws_access_key_id(),
      aws_profile(),
      gcp_credentials(),
      gcp_project(),
      ci(),
      live_mode(),
      live_tests(),
      "CLAUDE_CONFIG_DIR",
      "CLAUDE_EXAMPLES_BACKEND",
      "CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS",
      "MIX_ENV",
      "PATH",
      "HOME"
    ]
  end

  @doc """
  Filters an OS environment map down to the variables the SDK reads.

  Keeps `all_known_vars/0` plus anything under the `CLAUDE_`/`ANTHROPIC_`
  namespaces (so a newly introduced SDK/CLI variable cannot be silently
  dropped), and excludes everything else — unrelated secrets in the parent
  environment must not be copied into inspectable Application config.
  """
  @spec snapshot(%{optional(String.t()) => String.t()}) ::
          %{optional(String.t()) => String.t()}
  def snapshot(os_env) when is_map(os_env) do
    allowed = MapSet.new(all_known_vars())

    Map.filter(os_env, fn {key, _value} ->
      MapSet.member?(allowed, key) or
        String.starts_with?(key, "CLAUDE_") or
        String.starts_with?(key, "ANTHROPIC_")
    end)
  end
end
