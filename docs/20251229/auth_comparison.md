# Authentication Comparison: Python vs Elixir Claude Agent SDK

## Overview

The Python and Elixir SDKs take fundamentally different approaches to authentication. Python delegates entirely to the CLI, while Elixir provides a comprehensive AuthManager with multi-provider support.

## Parity Status

| Feature | Python SDK | Elixir SDK | Parity |
|---------|------------|------------|--------|
| CLI Auth Delegation | Yes | Yes | Full |
| Environment Variable Support | Yes | Yes | Full |
| ANTHROPIC_API_KEY | Yes | Yes | Full |
| CLAUDE_AGENT_OAUTH_TOKEN | Yes | Yes | Full |
| Token Setup Automation | No | Yes | Elixir-only |
| Token Persistence | No | Yes | Elixir-only |
| Token Refresh | No | Yes | Elixir-only |
| Multi-Provider (Bedrock/Vertex) | Via CLI | Native | Elixir-only |
| Auth Status API | No | Yes | Elixir-only |

## Python: CLI Delegation

The Python SDK delegates all authentication to the Claude CLI. It sets an entrypoint marker but does not manage tokens.

### Environment Setup

```python
# From query.py
os.environ["CLAUDE_CODE_ENTRYPOINT"] = "sdk-py"

# From subprocess_cli.py
process_env = {
    **os.environ,
    **self._options.env,  # User-provided env vars
    "CLAUDE_CODE_ENTRYPOINT": "sdk-py",
    "CLAUDE_AGENT_SDK_VERSION": __version__,
}
```

### Authentication Flow

1. User sets `ANTHROPIC_API_KEY` in environment
2. SDK passes environment to CLI subprocess
3. CLI handles token validation
4. If auth fails, CLI returns error messages

### No SDK-Level Auth Management

```python
# Python SDK has no AuthManager equivalent
# Users must:
# 1. Run `claude login` manually, OR
# 2. Set ANTHROPIC_API_KEY environment variable
```

## Elixir: AuthManager with Providers

The Elixir SDK provides a comprehensive `AuthManager` GenServer with multi-provider support.

### AuthManager Structure

```elixir
defmodule ClaudeAgentSDK.AuthManager do
  use GenServer

  defstruct [
    :token,           # Current authentication token
    :expiry,          # Token expiry DateTime
    :provider,        # :anthropic | :bedrock | :vertex
    :refresh_timer,   # Timer reference for auto-refresh
    :storage_backend  # Module implementing storage behavior
  ]
end
```

### Public API

```elixir
# Ensure authentication is valid
:ok = ClaudeAgentSDK.AuthManager.ensure_authenticated()

# Interactive token setup (OAuth flow)
{:ok, token} = ClaudeAgentSDK.AuthManager.setup_token()

# Get current token
{:ok, token} = ClaudeAgentSDK.AuthManager.get_token()

# Force refresh
{:ok, token} = ClaudeAgentSDK.AuthManager.refresh_token()

# Clear stored authentication
:ok = ClaudeAgentSDK.AuthManager.clear_auth()

# Get detailed status
%{
  authenticated: true,
  provider: :anthropic,
  token_present: true,
  expires_at: ~U[2025-11-07 00:00:00Z],
  time_until_expiry_hours: 720
} = ClaudeAgentSDK.AuthManager.status()
```

### Authentication Priority

The Elixir AuthManager checks authentication in this order:

```elixir
def handle_call(:ensure_authenticated, _from, state) do
  cond do
    # Priority 1: Environment variable
    env_key_present?() ->
      {:reply, :ok, state}

    # Priority 2: Valid stored token
    valid_token?(state) ->
      {:reply, :ok, state}

    # Priority 3: Automatic setup (if interactive)
    can_setup_interactively?() ->
      case perform_token_setup(state) do
        {:ok, new_state} -> {:reply, :ok, new_state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end

    # Priority 4: Fail with helpful message
    true ->
      {:reply, {:error, :authentication_required}, state}
  end
end
```

## Environment Variable Support

### Shared Variables

Both SDKs respect these environment variables:

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Direct API key authentication |
| `CLAUDE_AGENT_OAUTH_TOKEN` | OAuth token (preferred) |

### Elixir-Specific Variables

| Variable | Purpose |
|----------|---------|
| `CLAUDE_AGENT_USE_BEDROCK` | Set to "1" for AWS Bedrock provider |
| `CLAUDE_AGENT_USE_VERTEX` | Set to "1" for GCP Vertex provider |
| `CI` | If "true", disables interactive setup |

### Environment Check (Elixir)

```elixir
defp env_key_present? do
  case {System.get_env("ANTHROPIC_API_KEY"),
        System.get_env("CLAUDE_AGENT_OAUTH_TOKEN")} do
    {nil, nil} -> false
    {"", ""} -> false
    {nil, ""} -> false
    {"", nil} -> false
    _ -> true  # At least one key present
  end
end
```

## Multi-Provider Support (Elixir Only)

### Provider Abstraction

```elixir
defmodule ClaudeAgentSDK.Auth.Provider do
  @type provider :: :anthropic | :bedrock | :vertex

  @spec setup_token(provider()) ::
    {:ok, String.t(), DateTime.t() | nil} | {:error, term()}
  def setup_token(:anthropic), do: Anthropic.setup_token()
  def setup_token(:bedrock), do: Bedrock.setup_token()
  def setup_token(:vertex), do: Vertex.setup_token()
end
```

### Provider Detection

```elixir
defp detect_provider do
  cond do
    System.get_env("CLAUDE_AGENT_USE_BEDROCK") == "1" -> :bedrock
    System.get_env("CLAUDE_AGENT_USE_VERTEX") == "1" -> :vertex
    true -> :anthropic
  end
end
```

### Anthropic Provider

```elixir
# Uses `claude setup-token` CLI command
defmodule ClaudeAgentSDK.Auth.Providers.Anthropic do
  def setup_token do
    # Execute claude setup-token
    # Parse token from output
    # Extract expiry if present
    {:ok, token, expiry}
  end
end
```

### Bedrock/Vertex Providers

```elixir
# AWS Bedrock - uses AWS SDK credentials
defmodule ClaudeAgentSDK.Auth.Providers.Bedrock do
  def setup_token do
    # Use AWS credential chain
    # Returns session token with expiry
  end
end

# GCP Vertex - uses GCP SDK credentials
defmodule ClaudeAgentSDK.Auth.Providers.Vertex do
  def setup_token do
    # Use GCP credential chain
    # Returns access token with expiry
  end
end
```

## Token Persistence (Elixir Only)

### TokenStore Behavior

```elixir
defmodule ClaudeAgentSDK.Auth.TokenStore do
  @callback load() :: {:ok, token_data()} | {:error, term()}
  @callback save(token_data()) :: :ok | {:error, term()}
  @callback clear() :: :ok
end
```

### Storage Backends

```elixir
# Configuration
config :claude_agent_sdk,
  auth_storage: :file,  # :file | :application_env | :custom
  auth_file_path: "~/.claude_sdk/token.json"
```

### Load on Startup

```elixir
def init(opts) do
  storage_backend = Keyword.get(opts, :storage_backend, TokenStore)

  state =
    case storage_backend.load() do
      {:ok, token_data} ->
        Logger.info("AuthManager: Loaded existing token from storage")
        %__MODULE__{
          token: token_data.token,
          expiry: token_data.expiry,
          provider: token_data.provider || :anthropic,
          storage_backend: storage_backend
        }

      {:error, :not_found} ->
        Logger.info("AuthManager: No stored token found")
        %__MODULE__{storage_backend: storage_backend}
    end

  {:ok, state}
end
```

## Token Refresh (Elixir Only)

### Auto-Refresh Scheduling

```elixir
defp schedule_refresh(state) do
  # Cancel existing timer
  if state.refresh_timer, do: Process.cancel_timer(state.refresh_timer)

  # Get refresh interval (default: 1 day before expiry)
  refresh_before_ms = Application.get_env(
    :claude_agent_sdk,
    :refresh_before_expiry,
    86_400_000  # 1 day
  )

  # Calculate time until refresh
  time_until_refresh =
    if state.expiry do
      expiry_ms = DateTime.to_unix(state.expiry, :millisecond)
      now_ms = DateTime.to_unix(DateTime.utc_now(), :millisecond)
      max(expiry_ms - now_ms - refresh_before_ms, 60_000)  # At least 1 min
    else
      nil
    end

  # Schedule refresh
  timer = if time_until_refresh do
    Process.send_after(self(), :refresh_token, time_until_refresh)
  end

  %{state | refresh_timer: timer}
end
```

### Refresh Handler

```elixir
def handle_info(:refresh_token, state) do
  Logger.info("AuthManager: Auto-refreshing token")

  case perform_token_setup(state) do
    {:ok, new_state} ->
      Logger.info("AuthManager: Token refresh successful")
      {:noreply, new_state}

    {:error, reason} ->
      Logger.error("AuthManager: Token refresh failed: #{inspect(reason)}")
      # Retry in 1 hour
      timer = Process.send_after(self(), :refresh_token, 3_600_000)
      {:noreply, %{state | refresh_timer: timer}}
  end
end
```

## Configuration Comparison

### Python

```python
# No SDK-level auth configuration
# Relies entirely on environment and CLI

# Set env vars before running
os.environ["ANTHROPIC_API_KEY"] = "sk-ant-..."
```

### Elixir

```elixir
# config/config.exs
config :claude_agent_sdk,
  auth_storage: :file,
  auth_file_path: "~/.claude_sdk/token.json",
  auto_refresh: true,
  refresh_before_expiry: 86_400_000  # 1 day in ms
```

## Usage Comparison

### Python Workflow

```python
# 1. User runs claude login OR sets ANTHROPIC_API_KEY
# 2. Import and use SDK
from claude_agent_sdk import query

# 3. SDK passes auth to CLI
async for message in query(prompt="Hello"):
    print(message)
```

### Elixir Workflow

```elixir
# Option A: Environment variable (same as Python)
System.put_env("ANTHROPIC_API_KEY", "sk-ant-...")
ClaudeAgentSDK.query("Hello")

# Option B: AuthManager (SDK-managed)
{:ok, _} = ClaudeAgentSDK.AuthManager.start_link([])
:ok = ClaudeAgentSDK.AuthManager.ensure_authenticated()
ClaudeAgentSDK.query("Hello")

# Option C: Automatic setup with persistence
{:ok, _} = ClaudeAgentSDK.AuthManager.setup_token()
# Token saved to ~/.claude_sdk/token.json
# Subsequent restarts auto-load token
```

## Differences Summary

| Aspect | Python | Elixir |
|--------|--------|--------|
| Auth Management | CLI-delegated | SDK-native |
| Token Storage | CLI manages | SDK manages |
| Auto-Refresh | No | Yes |
| Multi-Provider | Via CLI only | Native support |
| Interactive Setup | Via CLI | Via AuthManager |
| Status API | No | Yes |

## Recommendations

### For Python SDK

1. Consider adding optional AuthManager for parity
2. Add auth status checking utility
3. Document token refresh expectations

### For Elixir SDK

1. AuthManager is feature-complete
2. Consider adding Python-style simple mode that delegates entirely to CLI
3. Document Bedrock/Vertex provider setup requirements

### For Both

1. Standardize environment variable names
2. Document auth priority clearly
3. Add auth troubleshooting guides
