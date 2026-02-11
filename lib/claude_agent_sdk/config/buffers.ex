defmodule ClaudeAgentSDK.Config.Buffers do
  @moduledoc """
  Buffer sizes, batch limits, and display truncation lengths.

  Runtime overrides via Application config:

      config :claude_agent_sdk, ClaudeAgentSDK.Config.Buffers,
        max_stdout_buffer_bytes: 2_097_152
  """

  @app :claude_agent_sdk

  @spec get(atom(), term()) :: term()
  defp get(key, default) do
    @app
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end

  # -- process / transport ---------------------------------------------------

  @doc "Maximum stdout buffer size in bytes (default: 1 MB)."
  @spec max_stdout_buffer_bytes() :: pos_integer()
  def max_stdout_buffer_bytes,
    do: get(:max_stdout_buffer_bytes, 1_048_576)

  @doc "Maximum stderr buffer size in bytes (default: 256 KB)."
  @spec max_stderr_buffer_bytes() :: pos_integer()
  def max_stderr_buffer_bytes,
    do: get(:max_stderr_buffer_bytes, 262_144)

  @doc "Maximum lines to drain per batch (default: 200)."
  @spec max_lines_per_batch() :: pos_integer()
  def max_lines_per_batch, do: get(:max_lines_per_batch, 200)

  @doc "Inbound event buffer limit before first subscriber (default: 1000)."
  @spec stream_buffer_limit() :: pos_integer()
  def stream_buffer_limit, do: get(:stream_buffer_limit, 1_000)

  # -- display truncation ----------------------------------------------------

  @doc "Error / JSON preview length for logs (default: 100)."
  @spec error_preview_length() :: pos_integer()
  def error_preview_length, do: get(:error_preview_length, 100)

  @doc "Message trim length for debug output (default: 300)."
  @spec message_trim_length() :: pos_integer()
  def message_trim_length, do: get(:message_trim_length, 300)

  @doc "Orchestrator error truncation length (default: 1000)."
  @spec error_truncation_length() :: pos_integer()
  def error_truncation_length,
    do: get(:error_truncation_length, 1_000)

  @doc "Default summary max length (default: 100)."
  @spec summary_max_length() :: pos_integer()
  def summary_max_length, do: get(:summary_max_length, 100)
end
