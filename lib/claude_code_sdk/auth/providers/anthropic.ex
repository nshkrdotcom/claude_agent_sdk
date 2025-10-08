defmodule ClaudeCodeSDK.Auth.Providers.Anthropic do
  @moduledoc """
  Anthropic-specific authentication via `claude setup-token`.
  """

  require Logger

  # OAuth tokens valid for 1 year
  @token_ttl_days 365

  @doc """
  Executes `claude setup-token` and extracts the OAuth token.

  This requires:
  - Claude Code CLI installed (v2.0.10+)
  - Active Claude subscription
  - Interactive terminal for OAuth flow

  ## Process

  1. Opens browser to claude.ai/oauth/authorize
  2. User signs in with Claude account
  3. CLI displays OAuth token (sk-ant-oat01-...)
  4. Token is valid for 1 year

  ## Token Format

  Returns OAuth token: sk-ant-oat01-...
  Should be set as: export CLAUDE_CODE_OAUTH_TOKEN=<token>
  """
  @spec setup_token() :: {:ok, String.t(), DateTime.t()} | {:error, term()}
  def setup_token do
    Logger.info("Setting up Anthropic authentication token...")
    Logger.info("This will open a browser for OAuth - please sign in when prompted")

    case System.cmd("claude", ["setup-token"],
           stderr_to_stdout: true,
           env: [],
           # 2 minutes for OAuth
           timeout: 120_000
         ) do
      {output, 0} ->
        parse_token_output(output)

      {error, exit_code} ->
        {:error, "claude setup-token failed (exit #{exit_code}): #{error}"}
    end
  end

  defp parse_token_output(output) do
    # Actual output format from `claude setup-token` (v2.0.10):
    #
    # "Your OAuth token (valid for 1 year):"
    # "sk-ant-oat01-..."
    # "Store this token securely. You won't be able to see it again."
    # "Use this token by setting: export CLAUDE_CODE_OAUTH_TOKEN=<token>"

    patterns = [
      # OAuth token format (v2.0.10+) - most specific first
      ~r/Your OAuth token.*?:\s*\n\s*(sk-ant-oat01-[A-Za-z0-9\-_]+)/m,
      # OAuth token direct match
      ~r/(sk-ant-oat01-[A-Za-z0-9\-_]{95,120})/,
      # Legacy API key format (older CLI versions)
      ~r/(sk-ant-api03-[A-Za-z0-9\-_]{95,120})/,
      # Generic fallback - any sk-ant- token
      ~r/(sk-ant-[a-z0-9]+-[A-Za-z0-9\-_]{95,120})/i
    ]

    token =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, output) do
          [_, token] -> token
          _ -> nil
        end
      end)

    case token do
      nil ->
        {:error, "Could not extract token from output: #{output}"}

      token ->
        expiry = DateTime.add(DateTime.utc_now(), @token_ttl_days * 86_400, :second)
        token_type = if String.starts_with?(token, "sk-ant-oat01-"), do: "OAuth", else: "API"

        Logger.info("Successfully obtained Anthropic #{token_type} token")
        Logger.info("Token valid until: #{Calendar.strftime(expiry, "%Y-%m-%d")}")

        Logger.info(
          "Set environment variable: export CLAUDE_CODE_OAUTH_TOKEN=#{String.slice(token, 0, 20)}..."
        )

        {:ok, token, expiry}
    end
  end

  @doc """
  Returns the environment variable name for Claude OAuth tokens.

  ## Examples

      iex> ClaudeCodeSDK.Auth.Providers.Anthropic.oauth_env_var()
      "CLAUDE_CODE_OAUTH_TOKEN"
  """
  @spec oauth_env_var() :: String.t()
  def oauth_env_var, do: "CLAUDE_CODE_OAUTH_TOKEN"
end
