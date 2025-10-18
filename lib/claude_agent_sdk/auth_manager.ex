defmodule ClaudeAgentSDK.AuthManager do
  @moduledoc """
  Manages authentication tokens for Claude Code SDK.

  Provides automatic token acquisition, validation, refresh, and persistence.
  Eliminates the need for manual `claude login` in automated environments.

  ## Features

  - Automatic token setup via `claude setup-token`
  - Persistent storage across application restarts
  - Token expiry detection and automatic refresh
  - Multi-provider support (Anthropic, AWS Bedrock, GCP Vertex)
  - Graceful fallback to ANTHROPIC_API_KEY environment variable

  ## Usage

      # One-time setup (interactive, requires Claude subscription)
      {:ok, token} = ClaudeAgentSDK.AuthManager.setup_token()

      # Subsequent calls automatically use stored token
      ClaudeAgentSDK.query("Hello")  # ✅ Authenticated

      # Manual refresh if needed
      {:ok, token} = ClaudeAgentSDK.AuthManager.refresh_token()

  ## Configuration

      # config/config.exs
      config :claude_agent_sdk,
        auth_storage: :file,  # :file | :application_env | :custom
        auth_file_path: "~/.claude_sdk/token.json",
        auto_refresh: true,
        refresh_before_expiry: 86_400_000  # 1 day in ms
  """

  use GenServer
  require Logger

  alias ClaudeAgentSDK.Auth.{Provider, TokenStore}

  # State structure
  defstruct [
    # Current authentication token
    :token,
    # Token expiry DateTime
    :expiry,
    # :anthropic | :bedrock | :vertex
    :provider,
    # Timer reference for auto-refresh
    :refresh_timer,
    # Module implementing storage behavior
    :storage_backend
  ]

  @type t :: %__MODULE__{
          token: String.t() | nil,
          expiry: DateTime.t() | nil,
          provider: atom(),
          refresh_timer: reference() | nil,
          storage_backend: module()
        }

  ## Public API

  @doc """
  Starts the AuthManager GenServer.

  Automatically loads existing tokens from storage on startup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ensures authentication is valid and available.

  Checks authentication in order of precedence:
  1. ANTHROPIC_API_KEY environment variable
  2. Valid stored token
  3. Automatic token setup (if interactive)

  Returns `:ok` if authenticated, `{:error, reason}` otherwise.

  ## Examples

      iex> ClaudeAgentSDK.AuthManager.ensure_authenticated()
      :ok

      # In CI without token:
      iex> ClaudeAgentSDK.AuthManager.ensure_authenticated()
      {:error, :authentication_required}
  """
  @spec ensure_authenticated() :: :ok | {:error, term()}
  def ensure_authenticated do
    GenServer.call(__MODULE__, :ensure_authenticated, 30_000)
  end

  @doc """
  Sets up a new authentication token interactively.

  Executes `claude setup-token` which requires:
  - Claude subscription
  - Interactive terminal access
  - Browser for OAuth flow

  ## Examples

      iex> ClaudeAgentSDK.AuthManager.setup_token()
      {:ok, "sk-ant-api03-..."}

      iex> ClaudeAgentSDK.AuthManager.setup_token()
      {:error, "claude setup-token failed: not subscribed"}
  """
  @spec setup_token() :: {:ok, String.t()} | {:error, term()}
  def setup_token do
    # 2 min timeout for OAuth
    GenServer.call(__MODULE__, :setup_token, 120_000)
  end

  @doc """
  Retrieves the current authentication token.

  Returns the token if valid, error otherwise.

  ## Examples

      iex> ClaudeAgentSDK.AuthManager.get_token()
      {:ok, "sk-ant-api03-..."}

      iex> ClaudeAgentSDK.AuthManager.get_token()
      {:error, :not_authenticated}
  """
  @spec get_token() :: {:ok, String.t()} | {:error, :not_authenticated}
  def get_token do
    GenServer.call(__MODULE__, :get_token)
  end

  @doc """
  Forces a token refresh.

  Useful for testing or manual token rotation.

  ## Examples

      iex> ClaudeAgentSDK.AuthManager.refresh_token()
      {:ok, "sk-ant-api03-..."}
  """
  @spec refresh_token() :: {:ok, String.t()} | {:error, term()}
  def refresh_token do
    GenServer.call(__MODULE__, :refresh_token, 120_000)
  end

  @doc """
  Clears stored authentication.

  Useful for logout or testing.

  ## Examples

      iex> ClaudeAgentSDK.AuthManager.clear_auth()
      :ok
  """
  @spec clear_auth() :: :ok
  def clear_auth do
    GenServer.call(__MODULE__, :clear_auth)
  end

  @doc """
  Returns current authentication status.

  ## Examples

      iex> ClaudeAgentSDK.AuthManager.status()
      %{
        authenticated: true,
        provider: :anthropic,
        token_present: true,
        expires_at: ~U[2025-11-07 00:00:00Z],
        time_until_expiry_hours: 720
      }
  """
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Determine storage backend
    storage_backend = Keyword.get(opts, :storage_backend, TokenStore)

    # Load existing token from storage
    state =
      case storage_backend.load() do
        {:ok, token_data} ->
          if Mix.env() != :test do
            Logger.info("AuthManager: Loaded existing token from storage")
          end

          %__MODULE__{
            token: token_data.token,
            expiry: token_data.expiry,
            provider: token_data.provider || :anthropic,
            storage_backend: storage_backend
          }

        {:error, :not_found} ->
          if Mix.env() != :test do
            Logger.info("AuthManager: No stored token found, will authenticate on demand")
          end

          %__MODULE__{storage_backend: storage_backend}

        {:error, reason} ->
          Logger.warning("AuthManager: Failed to load token: #{inspect(reason)}")
          %__MODULE__{storage_backend: storage_backend}
      end

    # Schedule auto-refresh if we have a valid token
    state = if valid_token?(state), do: schedule_refresh(state), else: state

    {:ok, state}
  end

  @impl true
  def handle_call(:ensure_authenticated, _from, state) do
    cond do
      # Priority 1: Environment variable (no token needed)
      env_key_present?() ->
        {:reply, :ok, state}

      # Priority 2: Valid stored token
      valid_token?(state) ->
        {:reply, :ok, state}

      # Priority 3: Try automatic setup
      can_setup_interactively?() ->
        case perform_token_setup(state) do
          {:ok, new_state} -> {:reply, :ok, new_state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      # Priority 4: Fail with helpful message
      true ->
        error = {:error, :authentication_required}
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:setup_token, _from, state) do
    case perform_token_setup(state) do
      {:ok, new_state} ->
        token = new_state.token
        {:reply, {:ok, token}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_token, _from, state) do
    cond do
      env_key_present?() ->
        # Prefer CLAUDE_AGENT_OAUTH_TOKEN, fallback to ANTHROPIC_API_KEY
        token = System.get_env("CLAUDE_AGENT_OAUTH_TOKEN") || System.get_env("ANTHROPIC_API_KEY")
        {:reply, {:ok, token}, state}

      valid_token?(state) ->
        {:reply, {:ok, state.token}, state}

      true ->
        {:reply, {:error, :not_authenticated}, state}
    end
  end

  @impl true
  def handle_call(:refresh_token, _from, state) do
    case perform_token_setup(state) do
      {:ok, new_state} ->
        {:reply, {:ok, new_state.token}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:clear_auth, _from, state) do
    # Clear from storage
    :ok = state.storage_backend.clear()

    # Cancel refresh timer
    if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

    # Reset state
    new_state = %{state | token: nil, expiry: nil, refresh_timer: nil}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = build_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_info(:refresh_token, state) do
    Logger.info("AuthManager: Auto-refreshing token")

    case perform_token_setup(state) do
      {:ok, new_state} ->
        Logger.info("AuthManager: Token refresh successful")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("AuthManager: Token refresh failed: #{inspect(reason)}")
        # Schedule retry in 1 hour
        timer = Process.send_after(self(), :refresh_token, 3_600_000)
        {:noreply, %{state | refresh_timer: timer}}
    end
  end

  ## Private Helpers

  defp env_key_present? do
    # Check both ANTHROPIC_API_KEY and CLAUDE_AGENT_OAUTH_TOKEN
    case {System.get_env("ANTHROPIC_API_KEY"), System.get_env("CLAUDE_AGENT_OAUTH_TOKEN")} do
      {nil, nil} -> false
      {"", ""} -> false
      {nil, ""} -> false
      {"", nil} -> false
      # At least one key present
      _ -> true
    end
  end

  defp valid_token?(%__MODULE__{token: nil}), do: false
  defp valid_token?(%__MODULE__{token: _token, expiry: nil}), do: true

  defp valid_token?(%__MODULE__{expiry: expiry}) do
    case DateTime.compare(DateTime.utc_now(), expiry) do
      :lt -> true
      _ -> false
    end
  end

  defp can_setup_interactively? do
    # Check if we're in an interactive environment
    # (has terminal, not in CI, etc.)
    System.get_env("CI") != "true"
  end

  defp perform_token_setup(state) do
    # Determine which provider to use
    provider = detect_provider()

    # Execute token setup for the provider
    case Provider.setup_token(provider) do
      {:ok, token, expiry} ->
        new_state = %{state | token: token, expiry: expiry, provider: provider}

        # Save to storage
        :ok =
          state.storage_backend.save(%{
            token: token,
            expiry: expiry,
            provider: provider
          })

        # Schedule refresh
        new_state = schedule_refresh(new_state)

        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp detect_provider do
    cond do
      System.get_env("CLAUDE_AGENT_USE_BEDROCK") == "1" -> :bedrock
      System.get_env("CLAUDE_AGENT_USE_VERTEX") == "1" -> :vertex
      true -> :anthropic
    end
  end

  defp schedule_refresh(state) do
    # Cancel existing timer
    if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

    # Get refresh interval from config
    refresh_before_ms =
      Application.get_env(
        :claude_agent_sdk,
        :refresh_before_expiry,
        # 1 day default
        86_400_000
      )

    # Calculate time until refresh
    time_until_refresh =
      if state.expiry do
        expiry_ms = DateTime.to_unix(state.expiry, :millisecond)
        now_ms = DateTime.to_unix(DateTime.utc_now(), :millisecond)
        # At least 1 min
        max(expiry_ms - now_ms - refresh_before_ms, 60_000)
      else
        # No expiry = never refresh
        nil
      end

    # Schedule refresh
    timer =
      if time_until_refresh do
        Process.send_after(self(), :refresh_token, time_until_refresh)
      else
        nil
      end

    %{state | refresh_timer: timer}
  end

  defp build_status(state) do
    %{
      authenticated: valid_token?(state) || env_key_present?(),
      provider: state.provider || detect_provider(),
      token_present: state.token != nil,
      expires_at: state.expiry,
      time_until_expiry_hours: calculate_expiry_hours(state.expiry)
    }
  end

  defp calculate_expiry_hours(nil), do: nil

  defp calculate_expiry_hours(expiry) do
    diff_ms = DateTime.diff(expiry, DateTime.utc_now(), :millisecond)
    Float.round(diff_ms / 3_600_000, 1)
  end
end
