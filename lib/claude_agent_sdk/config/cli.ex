defmodule ClaudeAgentSDK.Config.CLI do
  @moduledoc """
  CLI binary discovery, version constraints, and shared flag builders.

  Runtime overrides via Application config:

      config :claude_agent_sdk, ClaudeAgentSDK.Config.CLI,
        minimum_version: "2.1.0",
        recommended_version: "2.1.5"
  """

  @app :claude_agent_sdk

  @spec get(atom(), term()) :: term()
  defp get(key, default) do
    @app
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end

  # -- versions --------------------------------------------------------------

  @doc "Minimum supported CLI version (default: `\"2.0.0\"`)."
  @spec minimum_version() :: String.t()
  def minimum_version, do: get(:minimum_version, "2.0.0")

  @doc "Recommended CLI version for this SDK release (default: `\"2.0.75\"`)."
  @spec recommended_version() :: String.t()
  def recommended_version, do: get(:recommended_version, "2.0.75")

  # -- executable discovery --------------------------------------------------

  @doc ~S'Executable candidates tried during PATH search (default: `["claude-code", "claude"]`).'
  @spec executable_candidates() :: [String.t()]
  def executable_candidates,
    do: get(:executable_candidates, ["claude-code", "claude"])

  @doc "npm install command shown in error messages."
  @spec install_command() :: String.t()
  def install_command,
    do: "npm install -g @anthropic-ai/claude-code"

  # -- shared flag builders --------------------------------------------------

  @doc """
  Standard streaming CLI args used across all transport/query modules.

  Returns `["--output-format", "stream-json", "--verbose"]`.
  """
  @spec streaming_output_args() :: [String.t()]
  def streaming_output_args do
    ["--output-format", "stream-json", "--verbose"]
  end

  @doc """
  Bidirectional streaming args (adds `--input-format`).

  Returns the full flag set for stdin+stdout streaming.
  """
  @spec streaming_bidirectional_args() :: [String.t()]
  def streaming_bidirectional_args do
    [
      "--output-format",
      "stream-json",
      "--input-format",
      "stream-json",
      "--verbose"
    ]
  end
end
