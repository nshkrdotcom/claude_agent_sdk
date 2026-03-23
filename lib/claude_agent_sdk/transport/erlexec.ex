defmodule ClaudeAgentSDK.Transport.Erlexec do
  @moduledoc """
  Compatibility facade over `CliSubprocessCore.Transport.Erlexec`.

  The shared core now owns subprocess startup, subscriber fan-out, stderr
  delivery, interrupt handling, and shutdown semantics. This module only keeps
  the Claude SDK's public transport module name, legacy default event tag, and
  legacy error normalization for callers that still reference
  `ClaudeAgentSDK.Transport.Erlexec` directly.
  """

  import Kernel, except: [send: 2]

  alias ClaudeAgentSDK.Config.{Buffers, Timeouts}
  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Process, as: SDKProcess
  alias ClaudeAgentSDK.Runtime.CLI, as: RuntimeCLI
  alias ClaudeAgentSDK.Transport.ExecOptions
  alias CliSubprocessCore.Command, as: CoreCommand
  alias CliSubprocessCore.Transport.Erlexec, as: CoreErlexec
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
    |> CoreErlexec.send(message)
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    transport
    |> CoreErlexec.subscribe(pid)
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid, tag)
      when is_pid(transport) and is_pid(pid) and (tag == :legacy or is_reference(tag)) do
    transport
    |> CoreErlexec.subscribe(pid, tag)
    |> normalize_core_reply()
  end

  @spec unsubscribe(pid(), pid()) :: :ok
  def unsubscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    CoreErlexec.unsubscribe(transport, pid)
  end

  @impl ClaudeAgentSDK.Transport
  def close(transport) when is_pid(transport) do
    CoreErlexec.close(transport)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, :noproc -> :ok
  end

  @impl ClaudeAgentSDK.Transport
  def force_close(transport) when is_pid(transport) do
    transport
    |> CoreErlexec.force_close()
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def interrupt(transport) when is_pid(transport) do
    transport
    |> CoreErlexec.interrupt()
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def end_input(transport) when is_pid(transport) do
    transport
    |> CoreErlexec.end_input()
    |> normalize_core_reply()
  end

  @impl ClaudeAgentSDK.Transport
  def status(transport) when is_pid(transport), do: CoreErlexec.status(transport)

  @impl ClaudeAgentSDK.Transport
  def stderr(transport) when is_pid(transport), do: CoreErlexec.stderr(transport)

  @doc false
  def __exec_opts__(%Options{} = options), do: ExecOptions.erlexec(options)

  defp start_core_transport(fun, opts) do
    with {:ok, core_opts} <- normalize_start_opts(opts) do
      case apply(CoreErlexec, fun, [core_opts]) do
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

    stderr_callback_owner =
      normalize_stderr_callback_owner(Keyword.get(opts, :stderr_callback_owner))

    with {:ok, command} <- resolve_invocation(opts, options) do
      stderr_callback =
        opts
        |> Keyword.get(:stderr_callback, options.stderr)
        |> stderr_callback_for_owner(stderr_callback_owner)

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
        stderr_callback: stderr_callback
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

  defp normalize_stderr_callback_owner(:client), do: :client
  defp normalize_stderr_callback_owner(_owner), do: :transport

  defp stderr_callback_for_owner(callback, :transport) when is_function(callback, 1), do: callback
  defp stderr_callback_for_owner(_callback, _owner), do: nil

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
