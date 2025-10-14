# Implementation Plan: Authentication Manager
## Priority: MUST-HAVE (Critical)
## Estimated Effort: 2-3 days
## Target Version: 0.1.0

---

## 🎯 Objective

Implement automatic token-based authentication to eliminate manual `claude login` requirement, enabling true automation for CI/CD, background jobs, and production orchestration.

---

## 📋 Problem Statement

### Current State
- Users must manually run `claude login` before using SDK
- No session persistence across Elixir application restarts
- Breaks automation workflows (CI/CD, cron jobs, production services)
- No token refresh mechanism

### Pain Points
```elixir
# Current: Manual intervention required
$ claude login  # ← User must leave Elixir and authenticate manually
$ iex -S mix
iex> ClaudeAgentSDK.query("Hello")  # Only works if login was done

# In CI/CD: Completely broken
# - Can't run `claude login` interactively
# - Must set ANTHROPIC_API_KEY env var (not ideal for all use cases)
```

### Desired State
```elixir
# Automatic authentication with no user intervention
iex> ClaudeAgentSDK.AuthManager.setup_token()  # One-time setup
{:ok, "sk-ant-api03-..."}

# Future queries just work
iex> ClaudeAgentSDK.query("Hello")  # ✅ Automatically authenticated

# Background jobs work seamlessly
defmodule MyApp.ScheduledTask do
  def run do
    # No manual auth needed - token managed automatically
    ClaudeAgentSDK.query("Daily report")
  end
end
```

---

## 🏗️ Architecture Design

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│ ClaudeAgentSDK.AuthManager (GenServer)                   │
├─────────────────────────────────────────────────────────┤
│ Responsibilities:                                        │
│ • Token acquisition via `claude setup-token`            │
│ • Token storage (Application env + persistent file)     │
│ • Token validation and expiry checking                  │
│ • Automatic token refresh before expiry                 │
│ • Multi-provider support (Anthropic/Bedrock/Vertex)     │
└─────────────────────────────────────────────────────────┘
                           │
            ┌──────────────┼──────────────┐
            │              │              │
    ┌───────▼──────┐  ┌───▼─────┐  ┌────▼──────┐
    │ Token Store  │  │ CLI     │  │ Validator │
    │ (Persistent) │  │ Wrapper │  │           │
    └──────────────┘  └─────────┘  └───────────┘
```

### Integration Points

```elixir
# 1. Application Startup (automatic initialization)
defmodule MyApp.Application do
  def start(_type, _args) do
    children = [
      ClaudeAgentSDK.AuthManager,  # ← Add to supervision tree
      # ... other children
    ]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

# 2. Process.stream/3 (automatic auth check)
defmodule ClaudeAgentSDK.Process do
  defp stream_real(args, options, stdin_input) do
    # Check authentication before spawning subprocess
    case ClaudeAgentSDK.AuthManager.ensure_authenticated() do
      :ok ->
        Stream.resource(...)
      {:error, reason} ->
        raise AuthenticationError, reason
    end
  end
end

# 3. Mix Task (manual token setup)
$ mix claude.setup_token
```

---

## 📁 File Structure

```
lib/claude_agent_sdk/
  auth_manager.ex          # New: Main GenServer implementation
  auth/
    token_store.ex         # New: Persistent token storage
    provider.ex            # New: Multi-provider abstraction
    providers/
      anthropic.ex         # New: Anthropic-specific auth
      bedrock.ex           # New: AWS Bedrock auth
      vertex.ex            # New: GCP Vertex auth

lib/mix/tasks/
  claude.setup_token.ex    # New: Mix task for manual setup

test/claude_agent_sdk/
  auth_manager_test.exs    # New: Unit tests
  auth/
    token_store_test.exs   # New: Storage tests
    provider_test.exs      # New: Provider tests

config/
  config.exs               # Update: Add auth config defaults
```

---

## 🔧 Implementation Details

### Phase 1: Core AuthManager GenServer

**File**: `lib/claude_agent_sdk/auth_manager.ex`

```elixir
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

  alias ClaudeAgentSDK.Auth.{TokenStore, Provider}

  # State structure
  defstruct [
    :token,              # Current authentication token
    :expiry,             # Token expiry DateTime
    :provider,           # :anthropic | :bedrock | :vertex
    :refresh_timer,      # Timer reference for auto-refresh
    :storage_backend     # Module implementing storage behavior
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
    GenServer.call(__MODULE__, :setup_token, 120_000)  # 2 min timeout for OAuth
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
    state = case storage_backend.load() do
      {:ok, token_data} ->
        Logger.info("AuthManager: Loaded existing token from storage")
        %__MODULE__{
          token: token_data.token,
          expiry: token_data.expiry,
          provider: token_data.provider || :anthropic,
          storage_backend: storage_backend
        }

      {:error, :not_found} ->
        Logger.info("AuthManager: No stored token found, will authenticate on demand")
        %__MODULE__{storage_backend: storage_backend}

      {:error, reason} ->
        Logger.warn("AuthManager: Failed to load token: #{inspect(reason)}")
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
        {:reply, {:ok, System.get_env("ANTHROPIC_API_KEY")}, state}

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
    case System.get_env("ANTHROPIC_API_KEY") do
      nil -> false
      "" -> false
      _key -> true
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
    System.get_env("CI") != "true" && :erlang.system_info(:io_format) != :nif
  end

  defp perform_token_setup(state) do
    # Determine which provider to use
    provider = detect_provider()

    # Execute token setup for the provider
    case Provider.setup_token(provider) do
      {:ok, token, expiry} ->
        new_state = %{state |
          token: token,
          expiry: expiry,
          provider: provider
        }

        # Save to storage
        :ok = state.storage_backend.save(%{
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
    refresh_before_ms = Application.get_env(
      :claude_agent_sdk,
      :refresh_before_expiry,
      86_400_000  # 1 day default
    )

    # Calculate time until refresh
    time_until_refresh = if state.expiry do
      expiry_ms = DateTime.to_unix(state.expiry, :millisecond)
      now_ms = DateTime.to_unix(DateTime.utc_now(), :millisecond)
      max(expiry_ms - now_ms - refresh_before_ms, 60_000)  # At least 1 min
    else
      # No expiry = never refresh
      nil
    end

    # Schedule refresh
    timer = if time_until_refresh do
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
```

### Phase 2: Token Storage Backend

**File**: `lib/claude_agent_sdk/auth/token_store.ex`

```elixir
defmodule ClaudeAgentSDK.Auth.TokenStore do
  @moduledoc """
  Persistent token storage for authentication.

  Supports multiple storage backends:
  - File-based (default): ~/.claude_sdk/token.json
  - Application environment: :claude_agent_sdk, :auth_token
  - Custom: User-provided module implementing this behavior
  """

  @type token_data :: %{
    token: String.t(),
    expiry: DateTime.t() | nil,
    provider: atom()
  }

  @callback save(token_data()) :: :ok | {:error, term()}
  @callback load() :: {:ok, token_data()} | {:error, :not_found | term()}
  @callback clear() :: :ok

  ## Default File-Based Implementation

  @default_path Path.expand("~/.claude_sdk/token.json")

  @doc """
  Saves token data to storage.
  """
  @spec save(token_data()) :: :ok | {:error, term()}
  def save(data) do
    path = storage_path()

    # Ensure directory exists
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Serialize data
    json = Jason.encode!(%{
      token: data.token,
      expiry: data.expiry && DateTime.to_iso8601(data.expiry),
      provider: data.provider,
      created_at: DateTime.to_iso8601(DateTime.utc_now())
    })

    # Write with restricted permissions (user-only read/write)
    case File.write(path, json, [:exclusive]) do
      :ok ->
        # Set file permissions to 0600 (user read/write only)
        File.chmod!(path, 0o600)
        :ok

      {:error, :eexist} ->
        # File exists, overwrite
        File.write!(path, json)
        File.chmod!(path, 0o600)
        :ok

      error ->
        error
    end
  end

  @doc """
  Loads token data from storage.
  """
  @spec load() :: {:ok, token_data()} | {:error, :not_found | term()}
  def load do
    path = storage_path()

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, data} ->
            token_data = %{
              token: data["token"],
              expiry: parse_expiry(data["expiry"]),
              provider: String.to_atom(data["provider"] || "anthropic")
            }
            {:ok, token_data}

          {:error, reason} ->
            {:error, {:invalid_json, reason}}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clears stored token data.
  """
  @spec clear() :: :ok
  def clear do
    path = storage_path()
    File.rm(path)
    :ok
  end

  defp storage_path do
    Application.get_env(:claude_agent_sdk, :auth_file_path, @default_path)
    |> Path.expand()
  end

  defp parse_expiry(nil), do: nil
  defp parse_expiry(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end
end
```

### Phase 3: Provider Abstraction

**File**: `lib/claude_agent_sdk/auth/provider.ex`

```elixir
defmodule ClaudeAgentSDK.Auth.Provider do
  @moduledoc """
  Multi-provider authentication abstraction.

  Supports:
  - Anthropic (via `claude setup-token`)
  - AWS Bedrock (via AWS credentials)
  - GCP Vertex AI (via GCP credentials)
  """

  @type provider :: :anthropic | :bedrock | :vertex

  @doc """
  Sets up authentication token for the specified provider.

  Returns `{:ok, token, expiry}` or `{:error, reason}`.
  """
  @spec setup_token(provider()) :: {:ok, String.t(), DateTime.t() | nil} | {:error, term()}
  def setup_token(:anthropic) do
    ClaudeAgentSDK.Auth.Providers.Anthropic.setup_token()
  end

  def setup_token(:bedrock) do
    ClaudeAgentSDK.Auth.Providers.Bedrock.setup_token()
  end

  def setup_token(:vertex) do
    ClaudeAgentSDK.Auth.Providers.Vertex.setup_token()
  end
end
```

**File**: `lib/claude_agent_sdk/auth/providers/anthropic.ex`

```elixir
defmodule ClaudeAgentSDK.Auth.Providers.Anthropic do
  @moduledoc """
  Anthropic-specific authentication via `claude setup-token`.
  """

  require Logger

  @token_ttl_days 30

  @doc """
  Executes `claude setup-token` and extracts the token.

  This requires:
  - Claude Code CLI installed
  - Active Claude subscription
  - Interactive terminal for OAuth flow
  """
  @spec setup_token() :: {:ok, String.t(), DateTime.t()} | {:error, term()}
  def setup_token do
    Logger.info("Setting up Anthropic authentication token...")

    case System.cmd("claude", ["setup-token"],
      stderr_to_stdout: true,
      env: [],
      timeout: 120_000  # 2 minutes for OAuth
    ) do
      {output, 0} ->
        parse_token_output(output)

      {error, exit_code} ->
        {:error, "claude setup-token failed (exit #{exit_code}): #{error}"}
    end
  end

  defp parse_token_output(output) do
    # Expected output format:
    # "Successfully created long-lived token: sk-ant-api03-..."
    # or
    # "Token: sk-ant-api03-..."

    patterns = [
      ~r/Token:\s+(sk-ant-api03-[A-Za-z0-9\-_]+)/,
      ~r/token:\s+(sk-ant-api03-[A-Za-z0-9\-_]+)/,
      ~r/(sk-ant-api03-[A-Za-z0-9\-_]{95})/  # Standard token format
    ]

    token = Enum.find_value(patterns, fn pattern ->
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
        Logger.info("Successfully obtained Anthropic token (expires: #{expiry})")
        {:ok, token, expiry}
    end
  end
end
```

### Phase 4: Mix Task

**File**: `lib/mix/tasks/claude.setup_token.ex`

```elixir
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

    # Parse options
    {opts, _args, _invalid} = OptionParser.parse(args,
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

  defp token_exists? do
    case ClaudeAgentSDK.AuthManager.get_token() do
      {:ok, _token} -> true
      _ -> false
    end
  end

  defp setup_new_token do
    Mix.shell().info("🔐 Setting up Claude Code authentication...")
    Mix.shell().info("")
    Mix.shell().info("This will:")
    Mix.shell().info("  1. Open your browser for OAuth authentication")
    Mix.shell().info("  2. Generate a long-lived token (30 days)")
    Mix.shell().info("  3. Store the token for automatic use")
    Mix.shell().info("")

    case ClaudeAgentSDK.AuthManager.setup_token() do
      {:ok, token} ->
        Mix.shell().info("✅ Authentication successful!")
        Mix.shell().info("")
        Mix.shell().info("Token: #{String.slice(token, 0, 20)}...")
        show_status()

      {:error, reason} ->
        Mix.shell().error("❌ Authentication failed: #{inspect(reason)}")
        Mix.shell().error("")
        Mix.shell().error("Troubleshooting:")
        Mix.shell().error("  • Ensure Claude CLI is installed: npm install -g @anthropic-ai/claude-code")
        Mix.shell().error("  • Verify you have an active Claude subscription")
        Mix.shell().error("  • Check that you're in an interactive terminal")
        Mix.raise("Authentication setup failed")
    end
  end

  defp clear_auth do
    Mix.shell().info("🗑️  Clearing authentication...")
    :ok = ClaudeAgentSDK.AuthManager.clear_auth()
    Mix.shell().info("✅ Authentication cleared")
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
    Mix.shell().info("Ready to use ClaudeAgentSDK.query/2")
  end
end
```

---

## 🧪 Testing Strategy

### Unit Tests

**File**: `test/claude_agent_sdk/auth_manager_test.exs`

```elixir
defmodule ClaudeAgentSDK.AuthManagerTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.AuthManager
  alias ClaudeAgentSDK.Auth.TokenStore

  setup do
    # Use test storage backend
    start_supervised!({AuthManager, storage_backend: TokenStore.Memory})
    on_exit(fn -> AuthManager.clear_auth() end)
    :ok
  end

  describe "ensure_authenticated/0" do
    test "returns :ok when ANTHROPIC_API_KEY is set" do
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-test-key")
      assert :ok = AuthManager.ensure_authenticated()
      System.delete_env("ANTHROPIC_API_KEY")
    end

    test "returns :ok when valid token exists" do
      # Setup mock token
      {:ok, _token} = AuthManager.setup_token()
      assert :ok = AuthManager.ensure_authenticated()
    end

    test "returns error when not authenticated" do
      assert {:error, :authentication_required} = AuthManager.ensure_authenticated()
    end
  end

  describe "setup_token/0" do
    test "acquires and stores token" do
      # Mock claude CLI
      expect_cli_call("setup-token", "Token: sk-ant-api03-test123")

      assert {:ok, token} = AuthManager.setup_token()
      assert String.starts_with?(token, "sk-ant-api03-")

      # Verify token is stored
      assert {:ok, ^token} = AuthManager.get_token()
    end

    test "handles CLI failure gracefully" do
      expect_cli_call("setup-token", {:error, 1, "Not subscribed"})

      assert {:error, reason} = AuthManager.setup_token()
      assert reason =~ "failed"
    end
  end

  describe "token refresh" do
    test "automatically refreshes before expiry" do
      # Setup token expiring in 1 second
      setup_expiring_token(1000)

      # Wait for refresh
      Process.sleep(2000)

      # Verify new token was acquired
      assert {:ok, _new_token} = AuthManager.get_token()
    end

    test "manual refresh updates token" do
      {:ok, old_token} = AuthManager.setup_token()

      {:ok, new_token} = AuthManager.refresh_token()

      assert new_token != old_token
    end
  end

  describe "status/0" do
    test "returns authentication status" do
      AuthManager.setup_token()

      status = AuthManager.status()

      assert status.authenticated == true
      assert status.provider == :anthropic
      assert status.token_present == true
      assert is_number(status.time_until_expiry_hours)
    end
  end
end
```

### Integration Tests

```elixir
defmodule ClaudeAgentSDK.AuthIntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "queries work automatically with stored token" do
    # Setup token once
    {:ok, _token} = ClaudeAgentSDK.AuthManager.setup_token()

    # Query should work without manual authentication
    messages = ClaudeAgentSDK.query("Hello") |> Enum.to_list()

    assert Enum.any?(messages, &(&1.type == :assistant))
  end

  @tag :integration
  test "survives application restart" do
    # Setup token
    {:ok, token} = ClaudeAgentSDK.AuthManager.setup_token()

    # Restart GenServer (simulating app restart)
    Process.exit(Process.whereis(ClaudeAgentSDK.AuthManager), :kill)
    Process.sleep(100)

    # Token should be reloaded from storage
    {:ok, loaded_token} = ClaudeAgentSDK.AuthManager.get_token()
    assert loaded_token == token
  end
end
```

---

## 📊 Success Criteria

### Functional Requirements
- [ ] Automatic token acquisition via `claude setup-token`
- [ ] Token persistence across application restarts
- [ ] Automatic token refresh before expiry
- [ ] Support for ANTHROPIC_API_KEY fallback
- [ ] Mix task for manual token setup
- [ ] Clear and helpful error messages

### Non-Functional Requirements
- [ ] Zero user intervention after initial setup
- [ ] Works in CI/CD with env var fallback
- [ ] Secure token storage (file permissions 0600)
- [ ] Graceful degradation if CLI unavailable
- [ ] Performance: < 100ms overhead for auth check

### Quality Requirements
- [ ] 100% test coverage for core logic
- [ ] Integration tests with real CLI (tagged)
- [ ] Comprehensive documentation
- [ ] Dialyzer clean
- [ ] Credo score: A

---

## 🚧 Migration Guide

### For Existing Users

**Before** (manual authentication):
```bash
$ claude login
# Then run Elixir code
```

**After** (automatic authentication):
```bash
$ mix claude.setup_token  # One-time setup
# Token stored, future queries automatic
```

### Configuration Changes

```elixir
# config/config.exs

# Optional: Customize token storage
config :claude_agent_sdk,
  auth_storage: :file,  # or :application_env
  auth_file_path: "~/.my_app/claude_token.json",
  auto_refresh: true,
  refresh_before_expiry: 86_400_000  # 1 day

# For CI/CD: Use environment variable
# No code changes needed, just set:
# export ANTHROPIC_API_KEY=sk-ant-...
```

### Application Supervision Tree

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    # Add AuthManager to supervision tree
    ClaudeAgentSDK.AuthManager,  # ← New
    # ... rest of your children
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

---

## 🐛 Known Issues & Edge Cases

### Issue 1: Interactive OAuth in CI
**Problem**: `claude setup-token` requires browser OAuth, won't work in CI
**Solution**: Fallback to `ANTHROPIC_API_KEY` environment variable
**Status**: Documented, working as designed

### Issue 2: Token Expiry Uncertainty
**Problem**: CLI doesn't return explicit expiry, we estimate 30 days
**Solution**: Conservative refresh (refresh 1 day early)
**Status**: Acceptable, can improve if CLI adds expiry metadata

### Issue 3: Multi-Process Token Access
**Problem**: Multiple Elixir nodes might conflict on file access
**Solution**: Add file locking or distributed token store
**Status**: Future enhancement (v0.2.0)

---

## 📝 Documentation Updates

### README.md Changes

Add new authentication section:

```markdown
## Authentication

### Automatic Token Setup (Recommended)

```bash
# One-time setup
$ mix claude.setup_token
```

This generates a long-lived token (30 days) that's automatically used by all SDK queries.

### Environment Variable (CI/CD)

```bash
export ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
```

The SDK automatically detects and uses this variable.

### Manual CLI Login (Legacy)

```bash
$ claude login
```

Still works but requires re-authentication more frequently.
```

---

## 🎯 Definition of Done

- [ ] All code implemented and committed
- [ ] Unit tests written and passing (>95% coverage)
- [ ] Integration tests passing (tagged for optional execution)
- [ ] Dialyzer warnings resolved
- [ ] Credo score: A
- [ ] Documentation complete (inline + README)
- [ ] Migration guide written
- [ ] Example code updated
- [ ] CHANGELOG.md entry added
- [ ] Peer review completed
- [ ] Works in production scenario (tested manually)

---

## ⏱️ Timeline

### Day 1: Core Implementation
- ✅ AuthManager GenServer (4 hours)
- ✅ TokenStore backend (2 hours)
- ✅ Provider abstraction (2 hours)

### Day 2: Integration & Testing
- ✅ Mix task (1 hour)
- ✅ Unit tests (3 hours)
- ✅ Integration tests (2 hours)
- ✅ Process.ex integration (1 hour)

### Day 3: Polish & Documentation
- ✅ Documentation (3 hours)
- ✅ Migration guide (1 hour)
- ✅ Example updates (1 hour)
- ✅ Code review fixes (2 hours)

**Total**: 22 hours (2.75 days)

---

## 🔗 Dependencies

### External
- `claude` CLI (already required)
- `jason` (already in deps)

### Internal
- `ClaudeAgentSDK.Process` (update for auth check)
- `ClaudeAgentSDK.AuthChecker` (deprecate in favor of AuthManager)

### New
- `ClaudeAgentSDK.AuthManager`
- `ClaudeAgentSDK.Auth.TokenStore`
- `ClaudeAgentSDK.Auth.Provider`

---

## 🎓 References

- Claude Code CLI docs: https://docs.claude.com/claude-code
- `claude setup-token` command documentation
- OAuth 2.0 specification (for understanding token flow)
- Elixir GenServer best practices
- File permission handling in Elixir

---

**Status**: Ready for Implementation
**Assigned To**: TBD
**Review Required**: Yes (before merge to main)
**Blocking**: None
**Blocked By**: None
