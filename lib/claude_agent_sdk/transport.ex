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

  @doc """
  Closes the transport and releases any external resources.
  """
  @callback close(t()) :: :ok

  @doc """
  Returns the current connection status for observability/health checks.
  """
  @callback status(t()) :: :connected | :disconnected | :error
end
