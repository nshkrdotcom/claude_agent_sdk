defmodule ClaudeAgentSDK.Auth.Providers.Anthropic do
  @moduledoc """
  Anthropic-specific authentication via `claude setup-token`.
  """

  alias ClaudeAgentSDK.Config.{Auth, Env, Timeouts}
  alias ClaudeAgentSDK.Log, as: Logger

  @doc """
  Guides user through obtaining an OAuth token via `claude setup-token`.

  The Claude CLI requires an interactive TTY, so this function prompts
  the user to run `claude setup-token` in a separate terminal and paste
  the resulting token.

  ## Requirements

  - Claude Code CLI installed (v2.0.10+)
  - Active Claude subscription

  ## Token Format

  Accepts OAuth tokens (sk-ant-oat01-...) or API keys (sk-ant-api03-...).
  """
  @spec setup_token() :: {:ok, String.t(), DateTime.t()} | {:error, term()}
  def setup_token do
    # The Claude CLI requires a TTY for its interactive UI (uses Ink/React).
    # We cannot run it from Elixir directly. Instead, guide the user.

    IO.puts("""
    Run this in another terminal:

        claude setup-token

    Then paste the token below.
    """)

    prompt_for_token()
  end

  defp prompt_for_token do
    case IO.gets("Token: ") do
      :eof ->
        {:error, :no_input}

      {:error, reason} ->
        {:error, {:read_error, reason}}

      input ->
        token = String.trim(input)
        validate_and_return_token(token)
    end
  end

  defp validate_and_return_token("") do
    IO.puts("No token entered. Please try again.\n")
    prompt_for_token()
  end

  defp validate_and_return_token(token) do
    cond do
      String.starts_with?(token, Auth.oauth_token_prefix()) ->
        expiry =
          DateTime.add(
            DateTime.utc_now(),
            Auth.token_ttl_days() * Timeouts.seconds_per_day(),
            :second
          )

        Logger.info("Token stored (valid until #{Calendar.strftime(expiry, "%Y-%m-%d")})")
        {:ok, token, expiry}

      String.starts_with?(token, Auth.api_key_prefix()) ->
        expiry =
          DateTime.add(
            DateTime.utc_now(),
            Auth.token_ttl_days() * Timeouts.seconds_per_day(),
            :second
          )

        Logger.info("Token stored")
        {:ok, token, expiry}

      true ->
        IO.puts(
          "Invalid format. Token should start with '#{Auth.api_key_prefix()}'. Please try again.\n"
        )

        prompt_for_token()
    end
  end

  @doc """
  Returns the environment variable name for Claude OAuth tokens.

  ## Examples

      iex> ClaudeAgentSDK.Auth.Providers.Anthropic.oauth_env_var()
      "CLAUDE_AGENT_OAUTH_TOKEN"
  """
  @spec oauth_env_var() :: String.t()
  def oauth_env_var, do: Env.oauth_token()
end
