defmodule Mix.Tasks.Claude.SetupToken do
  use Mix.Task

  @shortdoc "Sets up Claude Code authentication token"

  @moduledoc """
  Sets up a long-lived authentication token for Claude Code SDK.

  This task executes `claude setup-token` and stores the result
  for automatic use by the SDK.

  ## Usage

      $ mix claude.setup_token

  ## Requirements

  - Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)
  - Active Claude subscription
  - Interactive terminal access

  ## Options

  - `--force` - Force token refresh even if valid token exists
  - `--clear` - Clear existing authentication

  ## Examples

      # Initial setup
      $ mix claude.setup_token

      # Force refresh
      $ mix claude.setup_token --force

      # Clear authentication
      $ mix claude.setup_token --clear
  """

  @impl Mix.Task
  def run(args) do
    # Start applications
    Mix.Task.run("app.start")

    # Start AuthManager manually if not in supervision tree
    case ensure_auth_manager_started() do
      :ok ->
        :ok

      {:error, reason} ->
        Mix.raise("Failed to start AuthManager: #{inspect(reason)}")
    end

    # Parse options
    {opts, _args, _invalid} =
      OptionParser.parse(args,
        switches: [force: :boolean, clear: :boolean]
      )

    cond do
      opts[:clear] ->
        clear_auth()

      opts[:force] || !token_exists?() ->
        setup_new_token()

      true ->
        Mix.shell().info("✅ Valid token already exists. Use --force to refresh.")
        show_status()
    end
  end

  @doc false
  @spec ensure_auth_manager_started((-> {:ok, pid()} | {:error, term()})) ::
          :ok | {:error, term()}
  def ensure_auth_manager_started(start_fun \\ fn -> ClaudeAgentSDK.AuthManager.start_link() end) do
    case start_fun.() do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp token_exists? do
    case ClaudeAgentSDK.AuthManager.get_token() do
      {:ok, _token} -> true
      _ -> false
    end
  end

  defp setup_new_token do
    case ClaudeAgentSDK.AuthManager.setup_token() do
      {:ok, token} ->
        Mix.shell().info("✅ Authentication successful!")
        Mix.shell().info("")
        Mix.shell().info("Token: #{String.slice(token, 0, 20)}...")
        Mix.shell().info("")

        # Show how to use the token
        if String.starts_with?(token, "sk-ant-oat01-") do
          Mix.shell().info("💡 To use this token manually, set:")
          Mix.shell().info("   export CLAUDE_AGENT_OAUTH_TOKEN=#{token}")
        end

        show_status()

      {:error, :no_input} ->
        Mix.shell().error("Cancelled.")

      {:error, reason} ->
        Mix.shell().error("Authentication failed: #{inspect(reason)}")
    end
  end

  defp clear_auth do
    Mix.shell().info("🗑️  Clearing authentication...")

    case ClaudeAgentSDK.AuthManager.clear_auth() do
      :ok ->
        Mix.shell().info("✅ Authentication cleared")

      {:error, reason} ->
        Mix.raise("Failed to clear authentication: #{inspect(reason)}")
    end
  end

  defp show_status do
    status = ClaudeAgentSDK.AuthManager.status()

    Mix.shell().info("")
    Mix.shell().info("📊 Authentication Status:")
    Mix.shell().info("  Provider: #{status.provider}")
    Mix.shell().info("  Authenticated: #{status.authenticated}")

    if status.expires_at do
      Mix.shell().info("  Expires: #{status.expires_at}")
      Mix.shell().info("  Time remaining: #{status.time_until_expiry_hours} hours")
    end

    Mix.shell().info("")
    Mix.shell().info("✅ Ready to use ClaudeAgentSDK.query/2")
  end
end
