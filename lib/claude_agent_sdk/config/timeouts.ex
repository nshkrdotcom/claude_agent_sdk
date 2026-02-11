defmodule ClaudeAgentSDK.Config.Timeouts do
  @moduledoc """
  Canonical timeout values for the SDK.

  Every timeout in the codebase reads from this module. Runtime
  overrides via Application config:

      config :claude_agent_sdk, ClaudeAgentSDK.Config.Timeouts,
        client_init_ms: 90_000

  Or at runtime:

      Application.put_env(
        :claude_agent_sdk,
        ClaudeAgentSDK.Config.Timeouts,
        client_init_ms: 90_000
      )
  """

  @app :claude_agent_sdk

  # -- helpers ---------------------------------------------------------------

  @spec get(atom(), term()) :: term()
  defp get(key, default) do
    @app
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end

  # -- client ----------------------------------------------------------------

  @doc "Client initialization timeout (default: 60 s)."
  @spec client_init_ms() :: pos_integer()
  def client_init_ms, do: get(:client_init_ms, 60_000)

  @doc "Hook callback execution timeout (default: 60 s)."
  @spec client_hook_ms() :: pos_integer()
  def client_hook_ms, do: get(:client_hook_ms, 60_000)

  @doc "Control protocol request timeout (default: 60 s)."
  @spec client_control_request_ms() :: pos_integer()
  def client_control_request_ms,
    do: get(:client_control_request_ms, 60_000)

  @doc "Client graceful stop timeout (default: 5 s)."
  @spec client_stop_ms() :: pos_integer()
  def client_stop_ms, do: get(:client_stop_ms, 5_000)

  @doc "Wait for CLI exit status before force-close (default: 200 ms)."
  @spec client_exit_wait_ms() :: pos_integer()
  def client_exit_wait_ms, do: get(:client_exit_wait_ms, 200)

  @doc "Permission callback Task.yield timeout (default: 60 s)."
  @spec client_permission_yield_ms() :: pos_integer()
  def client_permission_yield_ms,
    do: get(:client_permission_yield_ms, 60_000)

  # -- streaming -------------------------------------------------------------

  @doc "Streaming session default timeout (default: 5 min)."
  @spec streaming_session_ms() :: pos_integer()
  def streaming_session_ms, do: get(:streaming_session_ms, 300_000)

  @doc "Stream receive liveness probe interval (default: 30 s)."
  @spec stream_receive_ms() :: pos_integer()
  def stream_receive_ms, do: get(:stream_receive_ms, 30_000)

  # -- query -----------------------------------------------------------------

  @doc "Total query timeout (default: 75 min)."
  @spec query_total_ms() :: pos_integer()
  def query_total_ms, do: get(:query_total_ms, 4_500_000)

  @doc "Parallel query per-task timeout (default: 5 min)."
  @spec query_parallel_ms() :: pos_integer()
  def query_parallel_ms, do: get(:query_parallel_ms, 300_000)

  # -- transport -------------------------------------------------------------

  @doc "Safe GenServer.call timeout for transport (default: 5 s)."
  @spec transport_call_ms() :: pos_integer()
  def transport_call_ms, do: get(:transport_call_ms, 5_000)

  @doc "Force-close transport timeout (default: 500 ms)."
  @spec transport_force_close_ms() :: pos_integer()
  def transport_force_close_ms,
    do: get(:transport_force_close_ms, 500)

  @doc "Headless mode timeout (default: 5 s)."
  @spec transport_headless_ms() :: pos_integer()
  def transport_headless_ms, do: get(:transport_headless_ms, 5_000)

  @doc "Process finalization delay (default: 25 ms)."
  @spec transport_finalize_ms() :: non_neg_integer()
  def transport_finalize_ms, do: get(:transport_finalize_ms, 25)

  # -- close grace -----------------------------------------------------------

  @doc "Client close grace period (default: 2 s)."
  @spec client_close_grace_ms() :: pos_integer()
  def client_close_grace_ms, do: get(:client_close_grace_ms, 2_000)

  @doc "Transport close grace period (default: 2 s)."
  @spec transport_close_grace_ms() :: pos_integer()
  def transport_close_grace_ms,
    do: get(:transport_close_grace_ms, 2_000)

  # -- auth ------------------------------------------------------------------

  @doc "ensure_authenticated GenServer.call timeout (default: 30 s)."
  @spec auth_ensure_ms() :: pos_integer()
  def auth_ensure_ms, do: get(:auth_ensure_ms, 30_000)

  @doc "OAuth setup_token GenServer.call timeout (default: 2 min)."
  @spec auth_setup_token_ms() :: pos_integer()
  def auth_setup_token_ms, do: get(:auth_setup_token_ms, 120_000)

  @doc "Token refresh GenServer.call timeout (default: 2 min)."
  @spec auth_refresh_token_ms() :: pos_integer()
  def auth_refresh_token_ms, do: get(:auth_refresh_token_ms, 120_000)

  @doc "Retry interval on token refresh failure (default: 1 h)."
  @spec auth_refresh_retry_ms() :: pos_integer()
  def auth_refresh_retry_ms,
    do: get(:auth_refresh_retry_ms, 3_600_000)

  @doc "Schedule refresh this far before expiry (default: 1 day)."
  @spec auth_refresh_before_expiry_ms() :: pos_integer()
  def auth_refresh_before_expiry_ms,
    do: get(:auth_refresh_before_expiry_ms, 86_400_000)

  @doc "Minimum delay before scheduling a refresh (default: 1 min)."
  @spec auth_min_refresh_delay_ms() :: pos_integer()
  def auth_min_refresh_delay_ms,
    do: get(:auth_min_refresh_delay_ms, 60_000)

  @doc "CLI auth test command timeout (default: 30 s)."
  @spec auth_cli_test_ms() :: pos_integer()
  def auth_cli_test_ms, do: get(:auth_cli_test_ms, 30_000)

  @doc "CLI version check command timeout (default: 10 s)."
  @spec auth_cli_version_ms() :: pos_integer()
  def auth_cli_version_ms, do: get(:auth_cli_version_ms, 10_000)

  # -- tools & hooks ---------------------------------------------------------

  @doc "Tool execution timeout (default: 30 s)."
  @spec tool_execution_ms() :: pos_integer()
  def tool_execution_ms, do: get(:tool_execution_ms, 30_000)

  @doc "Minimum hook timeout floor (default: 1 s)."
  @spec hook_min_ms() :: pos_integer()
  def hook_min_ms, do: get(:hook_min_ms, 1_000)

  # -- session ---------------------------------------------------------------

  @doc "Session cleanup check interval (default: 24 h)."
  @spec session_cleanup_interval_ms() :: pos_integer()
  def session_cleanup_interval_ms,
    do: get(:session_cleanup_interval_ms, 86_400_000)

  # -- orchestrator ----------------------------------------------------------

  @doc "Initial exponential backoff for retries (default: 1 s)."
  @spec orchestrator_backoff_ms() :: pos_integer()
  def orchestrator_backoff_ms,
    do: get(:orchestrator_backoff_ms, 1_000)

  @doc "Milliseconds in one hour (conversion constant)."
  @spec ms_per_hour() :: pos_integer()
  def ms_per_hour, do: 3_600_000

  @doc "Seconds per day (conversion constant)."
  @spec seconds_per_day() :: pos_integer()
  def seconds_per_day, do: 86_400
end
