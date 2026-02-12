defmodule ClaudeAgentSDK.Transport do
  @moduledoc """
  Behaviour describing the transport layer used to communicate with the Claude CLI.

  A transport is responsible for starting and supervising the underlying connection,
  forwarding JSON control/data frames to the CLI, broadcasting replies to subscribers,
  and shutting down cleanly when the client stops.

  Implementations should be OTP-friendly processes (typically a `GenServer`)
  that encapsulate any state required to maintain the connection.
  """

  @typedoc "Opaque transport reference returned from `start_link/1`."
  @type t :: pid()

  @typedoc "Binary payload encoded as newline-terminated JSON."
  @type message :: binary()

  @typedoc "Transport-specific options propagated from `Client.start_link/1`."
  @type opts :: keyword()
  @type subscription_tag :: :legacy | reference()

  @doc """
  Starts the transport process and establishes the CLI connection.
  """
  @callback start(opts()) :: {:ok, t()} | {:error, term()}

  @doc """
  Starts the transport process and establishes the CLI connection.
  """
  @callback start_link(opts()) :: {:ok, t()} | {:error, term()}

  @doc """
  Sends a JSON payload to the CLI.
  """
  @callback send(t(), message()) :: :ok | {:error, term()}

  @doc """
  Subscribes the given process to receive inbound messages.
  """
  @callback subscribe(t(), pid()) :: :ok
  @callback subscribe(t(), pid(), subscription_tag()) :: :ok | {:error, term()}

  @doc """
  Closes the transport and releases any external resources.
  """
  @callback close(t()) :: :ok
  @callback force_close(t()) :: :ok | {:error, term()}
  @callback interrupt(t()) :: :ok | {:error, term()}

  @doc """
  Returns the current connection status for observability/health checks.
  """
  @callback status(t()) :: :connected | :disconnected | :error

  @doc """
  Signals end of input stream to the CLI process.

  This closes stdin to indicate no more input will be sent. Required for
  non-streaming queries where the CLI waits for stdin to close before
  processing.

  ## Implementation Notes

  - The built-in erlexec transport sends an `:eof` signal
  - Custom transports should close the stdin pipe or equivalent
  - This callback is optional - transports may not support it
  """
  @callback end_input(t()) :: :ok | {:error, term()}
  @callback stderr(t()) :: binary()

  @optional_callbacks [end_input: 1, subscribe: 3, force_close: 1, interrupt: 1, stderr: 1]

  @doc false
  @spec normalize_reason(term()) :: term()
  def normalize_reason({:command_not_found, "claude"}), do: :cli_not_found
  def normalize_reason(reason), do: reason
end
