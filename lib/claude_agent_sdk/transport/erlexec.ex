defmodule ClaudeAgentSDK.Transport.Erlexec do
  @moduledoc """
  Claude raw transport entrypoint backed by `CliSubprocessCore.Transport`.

  The shared core owns subprocess startup, subscriber fan-out, stderr
  delivery, interrupt handling, and shutdown semantics. This module preserves
  the Claude SDK's public transport module name, default event tag, and
  Claude-specific error normalization on top of that core-backed
  implementation.
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

  @behaviour ClaudeAgentSDK.Transport

  @default_event_tag :claude_agent_sdk_transport

  @impl ClaudeAgentSDK.Transport
  def start(opts) when is_list(opts), do: start_core_transport(:start, opts)

  @impl ClaudeAgentSDK.Transport
  def start_link(opts) when is_list(opts), do: start_core_transport(:start_link, opts)

  @impl ClaudeAgentSDK.Transport
  def send(transport, message) when is_pid(transport) do
    transport
    |> CoreTransport.send(message)
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    transport
    |> CoreTransport.subscribe(pid)
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
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

  @impl ClaudeAgentSDK.Transport
  def close(transport) when is_pid(transport), do: CoreTransport.close(transport)

  @impl ClaudeAgentSDK.Transport
  def force_close(transport) when is_pid(transport) do
    transport
    |> CoreTransport.force_close()
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def interrupt(transport) when is_pid(transport) do
    transport
    |> CoreTransport.interrupt()
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def end_input(transport) when is_pid(transport) do
    transport
    |> CoreTransport.end_input()
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def status(transport) when is_pid(transport), do: CoreTransport.status(transport)

  @impl ClaudeAgentSDK.Transport
  def stderr(transport) when is_pid(transport), do: CoreTransport.stderr(transport)

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

  defp normalize_core_reply({:error, %CoreTransportError{} = error}) do
    transport_error(legacy_transport_reason(error))
  end

  defp normalize_core_reply({:error, reason}),
    do: transport_error(legacy_transport_reason(reason))

  defp normalize_core_reply(other), do: transport_error({:unexpected_core_reply, other})

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
end
