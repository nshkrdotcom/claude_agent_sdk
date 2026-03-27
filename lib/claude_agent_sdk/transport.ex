defmodule ClaudeAgentSDK.Transport do
  @moduledoc """
  Behaviour describing the transport layer used to communicate with the Claude CLI.

  The shared core owns subprocess lifecycle; this behaviour defines the
  Claude-facing surface layered on top.

  A transport is responsible for starting and supervising the underlying connection,
  forwarding JSON control/data frames to the CLI, broadcasting replies to subscribers,
  and shutting down cleanly when the client stops.

  Implementations should be OTP-friendly processes (typically a `GenServer`)
  that encapsulate any state required to maintain the connection.
  """

  import Kernel, except: [send: 2]

  alias ClaudeAgentSDK.Config.{Buffers, Timeouts}
  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Process, as: SDKProcess
  alias ClaudeAgentSDK.Runtime.CLI, as: RuntimeCLI
  alias CliSubprocessCore.Command, as: CoreCommand
  alias CliSubprocessCore.Transport, as: CoreTransport
  alias CliSubprocessCore.Transport.Error, as: CoreTransportError

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

  - The built-in transport sends an `:eof` signal
  - Custom transports should close the stdin pipe or equivalent
  - This callback is optional - transports may not support it
  """
  @callback end_input(t()) :: :ok | {:error, term()}
  @callback stderr(t()) :: binary()

  @optional_callbacks [end_input: 1, subscribe: 3, force_close: 1, interrupt: 1, stderr: 1]

  @default_event_tag :claude_agent_sdk_transport

  @spec start(opts()) :: {:ok, t()} | {:error, term()}
  def start(opts) when is_list(opts), do: start_core_transport(:start, opts)

  @spec start_link(opts()) :: {:ok, t()} | {:error, term()}
  def start_link(opts) when is_list(opts), do: start_core_transport(:start_link, opts)

  @spec send(t(), message()) :: :ok | {:error, term()}
  def send(transport, message) when is_pid(transport) do
    transport
    |> CoreTransport.send(message)
    |> normalize_core_reply()
  end

  @spec subscribe(t(), pid()) :: :ok
  def subscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    transport
    |> CoreTransport.subscribe(pid)
    |> normalize_core_reply()
  end

  @spec subscribe(t(), pid(), subscription_tag()) :: :ok | {:error, term()}
  def subscribe(transport, pid, tag)
      when is_pid(transport) and is_pid(pid) and (tag == :legacy or is_reference(tag)) do
    transport
    |> CoreTransport.subscribe(pid, tag)
    |> normalize_core_reply()
  end

  @spec unsubscribe(pid(), pid()) :: :ok
  def unsubscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    CoreTransport.unsubscribe(transport, pid)
  end

  @spec close(t()) :: :ok
  def close(transport) when is_pid(transport), do: CoreTransport.close(transport)

  @spec force_close(t()) :: :ok | {:error, term()}
  def force_close(transport) when is_pid(transport) do
    transport
    |> CoreTransport.force_close()
    |> normalize_core_reply()
  end

  @spec interrupt(t()) :: :ok | {:error, term()}
  def interrupt(transport) when is_pid(transport) do
    transport
    |> CoreTransport.interrupt()
    |> normalize_core_reply()
  end

  @spec end_input(t()) :: :ok | {:error, term()}
  def end_input(transport) when is_pid(transport) do
    transport
    |> CoreTransport.end_input()
    |> normalize_core_reply()
  end

  @spec status(t()) :: :connected | :disconnected | :error
  def status(transport) when is_pid(transport), do: CoreTransport.status(transport)

  @spec stderr(t()) :: binary()
  def stderr(transport) when is_pid(transport), do: CoreTransport.stderr(transport)

  @doc false
  @spec normalize_reason(term()) :: term()
  def normalize_reason({:transport, %CoreTransportError{} = error}), do: normalize_reason(error)

  def normalize_reason(%CoreTransportError{
        reason: {:buffer_overflow, actual_size, max_size},
        context: context
      }) do
    %CLIJSONDecodeError{
      message: "JSON message exceeded maximum buffer size of #{max_size} bytes",
      line: Map.get(context, :preview, "") |> truncate_preview(),
      original_error: {:buffer_overflow, actual_size, max_size}
    }
  end

  def normalize_reason(%CoreTransportError{reason: {:command_not_found, command}})
      when command in ["claude", "claude-code"],
      do: :cli_not_found

  def normalize_reason(%CoreTransportError{reason: reason}), do: normalize_reason(reason)
  def normalize_reason({:command_not_found, "claude-code"}), do: :cli_not_found
  def normalize_reason({:command_not_found, "claude"}), do: :cli_not_found
  def normalize_reason(:noproc), do: :not_connected
  def normalize_reason({:call_exit, :noproc}), do: :not_connected
  def normalize_reason({:transport, :noproc}), do: :not_connected
  def normalize_reason(reason), do: reason

  defp start_core_transport(fun, opts) do
    with {:ok, core_opts} <- normalize_start_opts(opts) do
      case apply(CoreTransport, fun, [core_opts]) do
        {:ok, transport} ->
          {:ok, transport}

        {:error, {:transport, %CoreTransportError{} = error}} ->
          transport_error(legacy_transport_reason(error))

        {:error, reason} ->
          transport_error(legacy_transport_reason(reason))
      end
    end
  catch
    :exit, reason ->
      transport_error(legacy_transport_reason(reason))
  end

  defp normalize_start_opts(opts) do
    options = Keyword.get(opts, :options) || %Options{}

    with {:ok, command} <- resolve_invocation(opts, options) do
      core_opts = [
        command: command,
        subscriber: Keyword.get(opts, :subscriber),
        startup_mode: normalize_startup_mode(Keyword.get(opts, :startup_mode, :eager)),
        task_supervisor: Keyword.get(opts, :task_supervisor, CliSubprocessCore.TaskSupervisor),
        event_tag: Keyword.get(opts, :event_tag, @default_event_tag),
        headless_timeout_ms:
          normalize_headless_timeout_ms(Keyword.get(opts, :headless_timeout_ms)),
        max_buffer_size:
          normalize_max_buffer_size(Keyword.get(opts, :max_buffer_size, options.max_buffer_size)),
        max_stderr_buffer_size:
          normalize_max_stderr_buffer_size(Keyword.get(opts, :max_stderr_buffer_size)),
        stderr_callback: Keyword.get(opts, :stderr_callback, options.stderr)
      ]

      {:ok,
       Enum.reject(core_opts, fn
         {_key, nil} -> true
         _pair -> false
       end)}
    end
  end

  defp resolve_invocation(opts, %Options{} = options) do
    case Keyword.get(opts, :command) do
      %CoreCommand{} = command ->
        {:ok, command}

      command when is_binary(command) ->
        args = Keyword.get(opts, :args, [])
        cwd = Keyword.get(opts, :cwd, options.cwd)
        env = Keyword.get(opts, :env, SDKProcess.__env_vars__(options))
        user = Keyword.get(opts, :user, options.user)

        {:ok, CoreCommand.new(command, args, cwd: cwd, env: env, user: user)}

      nil ->
        RuntimeCLI.build_invocation(options: options)

      other ->
        {:error, {:invalid_command, other}}
    end
  end

  defp normalize_startup_mode(:lazy), do: :lazy
  defp normalize_startup_mode(_mode), do: :eager

  defp normalize_headless_timeout_ms(:infinity), do: :infinity

  defp normalize_headless_timeout_ms(timeout_ms)
       when is_integer(timeout_ms) and timeout_ms > 0,
       do: timeout_ms

  defp normalize_headless_timeout_ms(_timeout_ms), do: Timeouts.transport_headless_ms()

  defp normalize_max_buffer_size(size) when is_integer(size) and size > 0, do: size
  defp normalize_max_buffer_size(_size), do: Buffers.max_stdout_buffer_bytes()

  defp normalize_max_stderr_buffer_size(size) when is_integer(size) and size > 0, do: size
  defp normalize_max_stderr_buffer_size(_size), do: Buffers.max_stderr_buffer_bytes()

  defp normalize_core_reply(:ok), do: :ok

  defp normalize_core_reply({:error, {:transport, %CoreTransportError{} = error}}) do
    transport_error(legacy_transport_reason(error))
  end

  defp normalize_core_reply({:error, {:transport, reason}}),
    do: transport_error(legacy_transport_reason(reason))

  defp legacy_transport_reason(%CoreTransportError{
         reason: {:buffer_overflow, actual, max},
         context: context
       }) do
    %CLIJSONDecodeError{
      message: "JSON message exceeded maximum buffer size of #{max} bytes",
      line: Map.get(context, :preview, ""),
      original_error: {:buffer_overflow, actual, max}
    }
  end

  defp legacy_transport_reason(%CoreTransportError{reason: {:command_not_found, command}})
       when command in ["claude", "claude-code"] do
    :cli_not_found
  end

  defp legacy_transport_reason(%CoreTransportError{reason: reason}),
    do: legacy_transport_reason(reason)

  defp legacy_transport_reason(%CLIJSONDecodeError{} = error), do: error
  defp legacy_transport_reason(:noproc), do: :not_connected
  defp legacy_transport_reason({:call_exit, :noproc}), do: :not_connected
  defp legacy_transport_reason({:transport, :noproc}), do: :not_connected
  defp legacy_transport_reason(:transport_stopped), do: :transport_stopped
  defp legacy_transport_reason(reason), do: reason

  defp transport_error(reason), do: {:error, {:transport, reason}}

  defp truncate_preview(preview) do
    if byte_size(preview) > Buffers.error_preview_length() do
      binary_part(preview, 0, Buffers.error_preview_length()) <> "..."
    else
      preview
    end
  end
end
