defmodule ClaudeAgentSDK.Config.Orchestration do
  @moduledoc """
  Concurrency limits, retry policies, and orchestrator defaults.

  Runtime overrides via Application config:

      config :claude_agent_sdk, ClaudeAgentSDK.Config.Orchestration,
        max_concurrent: 10,
        max_retries: 5
  """

  @app :claude_agent_sdk

  @spec get(atom(), term()) :: term()
  defp get(key, default) do
    @app
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end

  @doc "Maximum concurrent parallel queries (default: 5)."
  @spec max_concurrent() :: pos_integer()
  def max_concurrent, do: get(:max_concurrent, 5)

  @doc "Maximum retry attempts (default: 3)."
  @spec max_retries() :: pos_integer()
  def max_retries, do: get(:max_retries, 3)

  @doc "Initial exponential backoff in ms (default: 1000)."
  @spec backoff_ms() :: pos_integer()
  def backoff_ms, do: get(:backoff_ms, 1_000)
end
