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
  alias ClaudeAgentSDK.Log, as: Logger

  alias ClaudeAgentSDK.Auth.{Provider, TokenStore}
  alias ClaudeAgentSDK.Config.{Env, Timeouts}

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
    :storage_backend,
    # Module implementing provider setup behavior
    :provider_backend,
    # PID of in-flight setup task
    :setup_task_pid,
    # Monitor ref for in-flight setup task
    :setup_task_ref,
    # setup operation for in-flight task
    :setup_operation,
    # queued call waiters waiting for setup completion
    setup_waiters: []
  ]

  @type t :: %__MODULE__{
          token: String.t() | nil,
          expiry: DateTime.t() | nil,
          provider: atom(),
          refresh_timer: reference() | nil,
          storage_backend: module(),
          provider_backend: module(),
          setup_task_pid: pid() | nil,
          setup_task_ref: reference() | nil,
          setup_operation: :ensure | :setup | :refresh | :auto_refresh | nil,
          setup_waiters: [{GenServer.from(), :ensure | :setup | :refresh}]
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
    GenServer.call(__MODULE__, :ensure_authenticated, Timeouts.auth_ensure_ms())
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
    GenServer.call(__MODULE__, :setup_token, Timeouts.auth_setup_token_ms())
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
    GenServer.call(__MODULE__, :refresh_token, Timeouts.auth_refresh_token_ms())
  end

  @doc """
  Clears stored authentication.

  Useful for logout or testing.

  ## Examples

      iex> ClaudeAgentSDK.AuthManager.clear_auth()
      :ok
  """
  @spec clear_auth() :: :ok | {:error, term()}
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
    provider_backend = Keyword.get(opts, :provider_backend, Provider)

    state = %__MODULE__{storage_backend: storage_backend, provider_backend: provider_backend}
    {:ok, state, {:continue, :load_token}}
  end

  @impl true
  def handle_continue(:load_token, state) do
    state =
      case state.storage_backend.load() do
        {:ok, token_data} ->
          Logger.info("AuthManager: Loaded existing token from storage")

          %{
            state
            | token: token_data.token,
              expiry: token_data.expiry,
              provider: token_data.provider || :anthropic
          }

        {:error, :not_found} ->
          Logger.info("AuthManager: No stored token found, will authenticate on demand")
          state

        {:error, reason} ->
          Logger.warning("AuthManager: Failed to load token: #{inspect(reason)}")
          state
      end

    state = if valid_token?(state), do: schedule_refresh(state), else: state
    {:noreply, state}
  end

  @impl true
  def handle_call(:ensure_authenticated, from, state) do
    cond do
      # Priority 1: Environment variable (no token needed)
      env_key_present?() ->
        {:reply, :ok, state}

      # Priority 2: Valid stored token
      valid_token?(state) ->
        {:reply, :ok, state}

      # Priority 3: Try automatic setup
      can_setup_interactively?() ->
        {:noreply, enqueue_setup_request(state, from, :ensure)}

      # Priority 4: Fail with helpful message
      true ->
        error = {:error, :authentication_required}
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:setup_token, from, state) do
    {:noreply, enqueue_setup_request(state, from, :setup)}
  end

  @impl true
  def handle_call(:get_token, _from, state) do
    cond do
      env_key_present?() ->
        # Prefer CLAUDE_AGENT_OAUTH_TOKEN, fallback to ANTHROPIC_API_KEY
        token = System.get_env(Env.oauth_token()) || System.get_env(Env.anthropic_api_key())
        {:reply, {:ok, token}, state}

      valid_token?(state) ->
        {:reply, {:ok, state.token}, state}

      true ->
        {:reply, {:error, :not_authenticated}, state}
    end
  end

  @impl true
  def handle_call(:refresh_token, from, state) do
    {:noreply, enqueue_setup_request(state, from, :refresh)}
  end

  @impl true
  def handle_call(:clear_auth, _from, state) do
    new_state =
      state
      |> cancel_setup_task(:authentication_cleared)
      |> cancel_refresh_timer()
      |> clear_token_state()

    case clear_token_from_storage(state.storage_backend) do
      :ok ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = build_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_info(:refresh_token, state) do
    state = %{state | refresh_timer: nil}

    cond do
      setup_in_progress?(state) ->
        {:noreply, state}

      state.token == nil ->
        {:noreply, state}

      true ->
        Logger.info("AuthManager: Auto-refreshing token")
        {:noreply, start_setup_task(state, :auto_refresh)}
    end
  end

  @impl true
  def handle_info({:setup_complete, operation, result}, state) do
    state =
      state
      |> demonitor_setup_task()
      |> clear_setup_task_state()
      |> apply_setup_result(operation, result)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{setup_task_ref: ref} = state) do
    operation = state.setup_operation

    if reason == :normal do
      {:noreply, state}
    else
      Logger.error("AuthManager: setup task crashed: #{inspect(reason)}")

      state =
        state
        |> clear_setup_task_state()
        |> reply_setup_waiters({:error, {:setup_crashed, reason}})
        |> maybe_schedule_retry_on_failure(operation)

      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  ## Private Helpers

  defp env_key_present? do
    # Check both ANTHROPIC_API_KEY and CLAUDE_AGENT_OAUTH_TOKEN
    case {System.get_env(Env.anthropic_api_key()), System.get_env(Env.oauth_token())} do
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
    System.get_env(Env.ci()) != "true"
  end

  defp perform_token_setup_work(state) do
    # Determine which provider to use
    provider = detect_provider()

    # Execute token setup for the provider
    case state.provider_backend.setup_token(provider) do
      {:ok, token, expiry} ->
        token_data = %{token: token, expiry: expiry, provider: provider}

        case save_token_to_storage(state.storage_backend, token_data) do
          :ok -> {:ok, token, expiry, provider}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp detect_provider do
    cond do
      System.get_env(Env.use_bedrock()) == "1" -> :bedrock
      System.get_env(Env.use_vertex()) == "1" -> :vertex
      true -> :anthropic
    end
  end

  defp schedule_refresh(state) do
    state = cancel_refresh_timer(state)

    # Get refresh interval from config
    refresh_before_ms = Timeouts.auth_refresh_before_expiry_ms()

    # Calculate time until refresh
    time_until_refresh =
      if state.expiry do
        expiry_ms = DateTime.to_unix(state.expiry, :millisecond)
        now_ms = DateTime.to_unix(DateTime.utc_now(), :millisecond)
        # At least 1 min
        max(expiry_ms - now_ms - refresh_before_ms, Timeouts.auth_min_refresh_delay_ms())
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
    Float.round(diff_ms / Timeouts.ms_per_hour(), 1)
  end

  defp enqueue_setup_request(state, from, operation) do
    state = %{state | setup_waiters: [{from, operation} | state.setup_waiters]}

    if setup_in_progress?(state) do
      state
    else
      start_setup_task(state, operation)
    end
  end

  defp start_setup_task(state, operation) do
    server = self()
    setup_state = state

    {:ok, pid} =
      ClaudeAgentSDK.TaskSupervisor.start_child(fn ->
        result = perform_token_setup_work(setup_state)
        send(server, {:setup_complete, operation, result})
      end)

    ref = Process.monitor(pid)

    %{
      state
      | setup_task_pid: pid,
        setup_task_ref: ref,
        setup_operation: operation
    }
  end

  defp setup_in_progress?(state) do
    is_pid(state.setup_task_pid) and is_reference(state.setup_task_ref)
  end

  defp apply_setup_result(state, _operation, {:ok, token, expiry, provider}) do
    state
    |> set_token_state(token, expiry, provider)
    |> schedule_refresh()
    |> reply_setup_waiters({:ok, token})
  end

  defp apply_setup_result(state, operation, {:error, reason}) do
    state
    |> reply_setup_waiters({:error, reason})
    |> maybe_schedule_retry_on_failure(operation)
  end

  defp maybe_schedule_retry_on_failure(state, :auto_refresh), do: schedule_refresh_retry(state)
  defp maybe_schedule_retry_on_failure(state, _operation), do: state

  defp schedule_refresh_retry(state) do
    timer = Process.send_after(self(), :refresh_token, Timeouts.auth_refresh_retry_ms())
    %{state | refresh_timer: timer}
  end

  defp reply_setup_waiters(%{setup_waiters: []} = state, _result), do: state

  defp reply_setup_waiters(state, result) do
    Enum.each(state.setup_waiters, fn {from, operation} ->
      GenServer.reply(from, format_setup_reply(operation, result))
    end)

    %{state | setup_waiters: []}
  end

  defp format_setup_reply(:ensure, {:ok, _token}), do: :ok
  defp format_setup_reply(:setup, {:ok, token}), do: {:ok, token}
  defp format_setup_reply(:refresh, {:ok, token}), do: {:ok, token}
  defp format_setup_reply(_operation, {:error, reason}), do: {:error, reason}

  defp cancel_setup_task(state, reason) do
    state
    |> stop_setup_task()
    |> reply_setup_waiters({:error, reason})
    |> clear_setup_task_state()
  end

  defp stop_setup_task(%{setup_task_pid: pid, setup_task_ref: ref} = state) do
    if is_reference(ref) do
      Process.demonitor(ref, [:flush])
    end

    if is_pid(pid) and Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    state
  end

  defp demonitor_setup_task(%{setup_task_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    state
  end

  defp demonitor_setup_task(state), do: state

  defp clear_setup_task_state(state) do
    %{
      state
      | setup_task_pid: nil,
        setup_task_ref: nil,
        setup_operation: nil
    }
  end

  defp cancel_refresh_timer(%{refresh_timer: timer} = state) when is_reference(timer) do
    _ = Process.cancel_timer(timer)
    flush_refresh_timer_messages()
    %{state | refresh_timer: nil}
  end

  defp cancel_refresh_timer(state), do: state

  defp flush_refresh_timer_messages do
    receive do
      :refresh_token -> flush_refresh_timer_messages()
    after
      0 -> :ok
    end
  end

  defp clear_token_state(state) do
    %{state | token: nil, expiry: nil, provider: nil}
  end

  defp set_token_state(state, token, expiry, provider) do
    %{state | token: token, expiry: expiry, provider: provider}
  end

  defp save_token_to_storage(storage_backend, token_data) do
    case storage_backend.save(token_data) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_storage_response, other}}
    end
  end

  defp clear_token_from_storage(storage_backend) do
    case storage_backend.clear() do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_storage_response, other}}
    end
  end
end
