defmodule ClaudeAgentSDK.Transport.Erlexec do
  @moduledoc """
  Compatibility wrapper around `CliSubprocessCore.Transport.Erlexec`.

  The Claude SDK preserves its public transport API and event shapes while the
  underlying subprocess ownership now lives in `cli_subprocess_core`.
  """

  use GenServer

  import Kernel, except: [send: 2]

  alias ClaudeAgentSDK.{CLI, Options, TaskSupervisor}
  alias ClaudeAgentSDK.Process, as: SDKProcess
  alias ClaudeAgentSDK.Config.{Buffers, Timeouts}
  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig
  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.Transport.ExecOptions
  alias CliSubprocessCore.Command, as: CoreCommand
  alias CliSubprocessCore.ProcessExit, as: CoreProcessExit
  alias CliSubprocessCore.Transport.Erlexec, as: CoreErlexec
  alias CliSubprocessCore.Transport.Error, as: CoreTransportError

  @behaviour ClaudeAgentSDK.Transport

  @default_event_tag :claude_agent_sdk_transport

  defstruct core_transport: nil,
            core_monitor_ref: nil,
            subscribers: %{},
            headless_timeout_ms: Timeouts.transport_headless_ms(),
            headless_timer_ref: nil,
            stderr_buffer: "",
            stderr_callback: nil,
            max_stderr_buffer_size: Buffers.max_stderr_buffer_bytes(),
            task_supervisor: TaskSupervisor,
            event_tag: @default_event_tag

  @type subscriber_info :: %{
          monitor_ref: reference(),
          tag: ClaudeAgentSDK.Transport.subscription_tag()
        }

  @type state :: %__MODULE__{
          core_transport: pid() | nil,
          core_monitor_ref: reference() | nil,
          subscribers: %{optional(pid()) => subscriber_info()},
          headless_timeout_ms: pos_integer() | :infinity,
          headless_timer_ref: reference() | nil,
          stderr_buffer: String.t(),
          stderr_callback: (String.t() -> any()) | nil,
          max_stderr_buffer_size: pos_integer(),
          task_supervisor: pid() | atom(),
          event_tag: atom()
        }

  @impl ClaudeAgentSDK.Transport
  def start(opts) when is_list(opts) do
    case GenServer.start(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> transport_error(reason)
    end
  catch
    :exit, reason ->
      transport_error(reason)
  end

  @impl ClaudeAgentSDK.Transport
  def start_link(opts) when is_list(opts) do
    case GenServer.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> transport_error(reason)
    end
  catch
    :exit, reason ->
      transport_error(reason)
  end

  @impl ClaudeAgentSDK.Transport
  def send(transport, message) when is_pid(transport) do
    case safe_call(transport, {:send, message}) do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> transport_error(reason)
      {:error, reason} -> transport_error(reason)
    end
  end

  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    subscribe(transport, pid, :legacy)
  end

  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid, tag)
      when is_pid(transport) and is_pid(pid) and (tag == :legacy or is_reference(tag)) do
    case safe_call(transport, {:subscribe, pid, tag}) do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> transport_error(reason)
      {:error, reason} -> transport_error(reason)
    end
  end

  @spec unsubscribe(pid(), pid()) :: :ok
  def unsubscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    case safe_call(transport, {:unsubscribe, pid}) do
      {:ok, :ok} -> :ok
      {:error, _reason} -> :ok
    end
  end

  @impl ClaudeAgentSDK.Transport
  def close(transport) when is_pid(transport) do
    GenServer.stop(transport, :normal)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, :noproc -> :ok
  end

  @impl ClaudeAgentSDK.Transport
  def force_close(transport) when is_pid(transport) do
    case safe_call(transport, :force_close, Timeouts.transport_force_close_ms()) do
      {:ok, :ok} ->
        :ok

      {:ok, {:error, :not_connected}} ->
        :ok

      {:ok, {:error, reason}} ->
        transport_error(reason)

      {:error, reason} ->
        transport_error(reason)
    end
  end

  @impl ClaudeAgentSDK.Transport
  def interrupt(transport) when is_pid(transport) do
    case safe_call(transport, :interrupt) do
      {:ok, :ok} ->
        :ok

      {:ok, {:error, :not_connected}} ->
        :ok

      {:ok, {:error, reason}} ->
        transport_error(reason)

      {:error, reason} ->
        transport_error(reason)
    end
  end

  @impl ClaudeAgentSDK.Transport
  def end_input(transport) when is_pid(transport) do
    case safe_call(transport, :end_input) do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> transport_error(reason)
      {:error, reason} -> transport_error(reason)
    end
  end

  @impl ClaudeAgentSDK.Transport
  def status(transport) when is_pid(transport) do
    case safe_call(transport, :status) do
      {:ok, status} when status in [:connected, :disconnected, :error] -> status
      _ -> :disconnected
    end
  end

  @impl ClaudeAgentSDK.Transport
  def stderr(transport) when is_pid(transport) do
    case safe_call(transport, :stderr) do
      {:ok, stderr} when is_binary(stderr) -> stderr
      _ -> ""
    end
  end

  @impl GenServer
  def init(opts) do
    options = Keyword.get(opts, :options) || %Options{}

    stderr_callback_owner =
      normalize_stderr_callback_owner(Keyword.get(opts, :stderr_callback_owner))

    with {:ok, normalized} <- normalize_start_opts(opts, options, stderr_callback_owner),
         {:ok, core_transport} <-
           CoreErlexec.start(Keyword.put(normalized.core_opts, :subscriber, self())) do
      state =
        %__MODULE__{
          core_transport: core_transport,
          core_monitor_ref: Process.monitor(core_transport),
          subscribers: %{},
          headless_timeout_ms: normalized.headless_timeout_ms,
          stderr_buffer: "",
          stderr_callback: normalized.stderr_callback,
          max_stderr_buffer_size: normalized.max_stderr_buffer_size,
          task_supervisor: normalized.task_supervisor,
          event_tag: normalized.event_tag
        }
        |> maybe_add_bootstrap_subscriber(normalized.bootstrap_subscriber)
        |> maybe_schedule_headless_timer()

      {:ok, state}
    else
      {:error, {:transport, reason}} -> {:stop, reason}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:subscribe, pid, tag}, _from, state) do
    {:reply, :ok, put_subscriber(state, pid, tag)}
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, remove_subscriber(state, pid)}
  end

  def handle_call({:send, message}, _from, %{core_transport: core_transport} = state) do
    {:reply, normalize_core_reply(CoreErlexec.send(core_transport, message)), state}
  end

  def handle_call({:send, _message}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:end_input, _from, %{core_transport: core_transport} = state) do
    {:reply, normalize_core_reply(CoreErlexec.end_input(core_transport)), state}
  end

  def handle_call(:end_input, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:interrupt, _from, %{core_transport: core_transport} = state) do
    reply =
      if CoreErlexec.status(core_transport) == :connected do
        normalize_core_reply(CoreErlexec.interrupt(core_transport))
      else
        {:error, :not_connected}
      end

    {:reply, reply, state}
  end

  def handle_call(:interrupt, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:force_close, _from, %{core_transport: core_transport} = state) do
    reply =
      if CoreErlexec.status(core_transport) == :connected do
        normalize_core_reply(CoreErlexec.force_close(core_transport))
      else
        {:error, :not_connected}
      end

    {:stop, :normal, reply, %{state | core_transport: nil}}
  end

  def handle_call(:force_close, _from, state) do
    {:stop, :normal, {:error, :not_connected}, state}
  end

  def handle_call(:status, _from, %{core_transport: core_transport} = state)
      when is_pid(core_transport) do
    {:reply, CoreErlexec.status(core_transport), state}
  end

  def handle_call(:status, _from, state) do
    {:reply, :disconnected, state}
  end

  def handle_call(:stderr, _from, state) do
    {:reply, state.stderr_buffer, state}
  end

  @impl GenServer
  def handle_info({:transport_message, line}, state) when is_binary(line) do
    broadcast_event(state, {:message, line})
    {:noreply, state}
  end

  def handle_info({:transport_error, %CoreTransportError{} = error}, state) do
    broadcast_event(state, {:error, error})
    {:noreply, state}
  end

  def handle_info({:transport_stderr, data}, state) do
    stderr_buffer =
      append_stderr_tail(
        state.stderr_buffer,
        IO.iodata_to_binary(data),
        state.max_stderr_buffer_size
      )

    broadcast_event(state, {:stderr, data})
    {:noreply, %{state | stderr_buffer: stderr_buffer}}
  end

  def handle_info({:transport_exit, %CoreProcessExit{} = exit}, state) do
    broadcast_event(state, {:exit, exit})
    {:stop, :normal, %{state | core_transport: nil}}
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, reason},
        %{core_monitor_ref: monitor_ref} = state
      ) do
    translated_reason = translate_down_reason(reason)

    if translated_reason != :normal do
      broadcast_event(state, {:exit, CoreProcessExit.from_reason(translated_reason)})
      {:stop, translated_reason, %{state | core_transport: nil, core_monitor_ref: nil}}
    else
      {:stop, :normal, %{state | core_transport: nil, core_monitor_ref: nil}}
    end
  end

  def handle_info({:DOWN, monitor_ref, :process, pid, _reason}, state)
      when is_reference(monitor_ref) do
    {:noreply, remove_subscriber_by_monitor(state, monitor_ref, pid)}
  end

  def handle_info(:headless_timeout, state) do
    state = %{state | headless_timer_ref: nil}

    if map_size(state.subscribers) == 0 do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{core_transport: core_transport} = state) do
    state = cancel_headless_timer(state)
    demonitor_subscribers(state.subscribers)

    if is_pid(core_transport) do
      _ = CoreErlexec.close(core_transport)
    end

    :ok
  catch
    _, _ -> :ok
  end

  @doc false
  def __exec_opts__(%Options{} = options), do: ExecOptions.erlexec(options)

  defp safe_call(transport, message, timeout \\ Timeouts.transport_call_ms())

  defp safe_call(transport, message, timeout)
       when is_pid(transport) and is_integer(timeout) and timeout >= 0 do
    task =
      try do
        Task.Supervisor.async_nolink(configured_task_supervisor(), fn ->
          try do
            {:ok, GenServer.call(transport, message, :infinity)}
          catch
            :exit, reason -> {:error, normalize_call_exit(reason)}
          end
        end)
      catch
        :exit, _ ->
          Task.async(fn ->
            try do
              {:ok, GenServer.call(transport, message, :infinity)}
            catch
              :exit, reason -> {:error, normalize_call_exit(reason)}
            end
          end)
      end

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, normalize_call_exit(reason)}
    end
  end

  defp configured_task_supervisor do
    Application.get_env(:claude_agent_sdk, :task_supervisor, TaskSupervisor)
  end

  defp normalize_call_exit({:noproc, _}), do: :not_connected
  defp normalize_call_exit(:noproc), do: :not_connected
  defp normalize_call_exit({:normal, _}), do: :not_connected
  defp normalize_call_exit({:shutdown, _}), do: :not_connected
  defp normalize_call_exit({:timeout, _}), do: :timeout
  defp normalize_call_exit(reason), do: {:call_exit, reason}

  defp normalize_start_opts(opts, %Options{} = options, stderr_callback_owner) do
    bootstrap_subscriber = Keyword.get(opts, :subscriber)

    with :ok <- validate_bootstrap_subscriber(bootstrap_subscriber),
         {:ok, {command, args, cwd, env}} <- resolve_invocation(opts, options) do
      stderr_callback =
        opts
        |> Keyword.get(:stderr_callback, options.stderr)
        |> stderr_callback_for_owner(stderr_callback_owner)

      headless_timeout_ms = normalize_headless_timeout_ms(Keyword.get(opts, :headless_timeout_ms))

      max_stderr_buffer_size =
        normalize_max_stderr_buffer_size(Keyword.get(opts, :max_stderr_buffer_size))

      max_buffer_size =
        normalize_max_buffer_size(Keyword.get(opts, :max_buffer_size, options.max_buffer_size))

      task_supervisor = Keyword.get(opts, :task_supervisor, TaskSupervisor)

      core_task_supervisor =
        Keyword.get(opts, :task_supervisor, CliSubprocessCore.TaskSupervisor)

      event_tag = Keyword.get(opts, :event_tag, @default_event_tag)
      startup_mode = normalize_startup_mode(Keyword.get(opts, :startup_mode, :eager))

      core_opts = [
        command: command,
        args: args,
        cwd: cwd,
        env: env,
        startup_mode: startup_mode,
        task_supervisor: core_task_supervisor,
        event_tag: event_tag,
        headless_timeout_ms: :infinity,
        max_buffer_size: max_buffer_size,
        max_stderr_buffer_size: max_stderr_buffer_size,
        stderr_callback: stderr_callback
      ]

      {:ok,
       %{
         core_opts: core_opts,
         bootstrap_subscriber: bootstrap_subscriber,
         headless_timeout_ms: headless_timeout_ms,
         max_stderr_buffer_size: max_stderr_buffer_size,
         stderr_callback: stderr_callback,
         task_supervisor: task_supervisor,
         event_tag: event_tag
       }}
    end
  end

  defp resolve_invocation(opts, %Options{} = options) do
    command = Keyword.get(opts, :command)
    args = Keyword.get(opts, :args, [])

    cond do
      is_binary(command) ->
        {:ok, {command, args, options.cwd, SDKProcess.__env_vars__(options)}}

      match?(%CoreCommand{}, command) ->
        {:ok, {command.command, command.args, command.cwd, command.env}}

      true ->
        build_invocation_from_options(options)
    end
  end

  defp build_invocation_from_options(%Options{} = options) do
    case CLI.resolve_executable(options) do
      {:ok, executable} ->
        args = CLIConfig.streaming_bidirectional_args() ++ Options.to_stream_json_args(options)
        {:ok, {executable, args, options.cwd, SDKProcess.__env_vars__(options)}}

      {:error, :not_found} ->
        {:error, :cli_not_found}
    end
  end

  defp validate_bootstrap_subscriber(nil), do: :ok
  defp validate_bootstrap_subscriber(pid) when is_pid(pid), do: :ok

  defp validate_bootstrap_subscriber({pid, tag})
       when is_pid(pid) and (tag == :legacy or is_reference(tag)),
       do: :ok

  defp validate_bootstrap_subscriber(subscriber), do: {:error, {:invalid_subscriber, subscriber}}

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

  defp maybe_add_bootstrap_subscriber(state, nil), do: state

  defp maybe_add_bootstrap_subscriber(state, pid) when is_pid(pid),
    do: put_subscriber(state, pid, :legacy)

  defp maybe_add_bootstrap_subscriber(state, {pid, tag})
       when is_pid(pid) and (tag == :legacy or is_reference(tag)) do
    put_subscriber(state, pid, tag)
  end

  defp put_subscriber(state, pid, tag) do
    subscribers =
      case Map.fetch(state.subscribers, pid) do
        {:ok, %{monitor_ref: monitor_ref}} ->
          Map.put(state.subscribers, pid, %{monitor_ref: monitor_ref, tag: tag})

        :error ->
          monitor_ref = Process.monitor(pid)
          Map.put(state.subscribers, pid, %{monitor_ref: monitor_ref, tag: tag})
      end

    %{state | subscribers: subscribers}
    |> cancel_headless_timer()
  end

  defp remove_subscriber(state, pid) do
    case Map.pop(state.subscribers, pid) do
      {nil, _subscribers} ->
        state

      {%{monitor_ref: monitor_ref}, subscribers} ->
        Process.demonitor(monitor_ref, [:flush])

        %{state | subscribers: subscribers}
        |> maybe_schedule_headless_timer()
    end
  end

  defp remove_subscriber_by_monitor(state, monitor_ref, pid) do
    subscribers =
      case Map.pop(state.subscribers, pid) do
        {%{monitor_ref: ^monitor_ref}, rest} -> rest
        {_value, rest} -> rest
      end

    %{state | subscribers: subscribers}
    |> maybe_schedule_headless_timer()
  end

  defp demonitor_subscribers(subscribers) do
    Enum.each(subscribers, fn
      {_pid, %{monitor_ref: monitor_ref}} when is_reference(monitor_ref) ->
        Process.demonitor(monitor_ref, [:flush])

      _other ->
        :ok
    end)
  end

  defp maybe_schedule_headless_timer(%{headless_timer_ref: ref} = state) when not is_nil(ref),
    do: state

  defp maybe_schedule_headless_timer(%{subscribers: subscribers} = state)
       when map_size(subscribers) > 0,
       do: state

  defp maybe_schedule_headless_timer(%{headless_timeout_ms: :infinity} = state), do: state

  defp maybe_schedule_headless_timer(%{headless_timeout_ms: timeout_ms} = state)
       when is_integer(timeout_ms) and timeout_ms > 0 do
    %{state | headless_timer_ref: Process.send_after(self(), :headless_timeout, timeout_ms)}
  end

  defp maybe_schedule_headless_timer(state), do: state

  defp cancel_headless_timer(%{headless_timer_ref: nil} = state), do: state

  defp cancel_headless_timer(state) do
    _ = Process.cancel_timer(state.headless_timer_ref, async: false, info: false)
    flush_headless_timeout_message()
    %{state | headless_timer_ref: nil}
  end

  defp flush_headless_timeout_message do
    receive do
      :headless_timeout -> :ok
    after
      0 -> :ok
    end
  end

  defp broadcast_event(state, event) do
    Enum.each(state.subscribers, fn
      {pid, %{tag: :legacy}} ->
        dispatch_legacy_event(pid, event)

      {pid, %{tag: ref}} when is_reference(ref) ->
        Kernel.send(pid, {state.event_tag, ref, event})
    end)
  end

  defp dispatch_legacy_event(pid, {:message, line}),
    do: Kernel.send(pid, {:transport_message, line})

  defp dispatch_legacy_event(pid, {:error, %CoreTransportError{} = error}),
    do: Kernel.send(pid, {:transport_error, legacy_transport_reason(error)})

  defp dispatch_legacy_event(pid, {:error, error}),
    do: Kernel.send(pid, {:transport_error, error})

  defp dispatch_legacy_event(pid, {:stderr, data}),
    do: Kernel.send(pid, {:transport_stderr, data})

  defp dispatch_legacy_event(pid, {:exit, %CoreProcessExit{reason: reason}}),
    do: Kernel.send(pid, {:transport_exit, reason})

  defp dispatch_legacy_event(pid, {:exit, reason}),
    do: Kernel.send(pid, {:transport_exit, reason})

  defp append_stderr_tail(_existing, _data, max_size)
       when not is_integer(max_size) or max_size <= 0,
       do: ""

  defp append_stderr_tail(existing, data, max_size) do
    combined = existing <> data
    combined_size = byte_size(combined)

    if combined_size <= max_size do
      combined
    else
      :binary.part(combined, combined_size - max_size, max_size)
    end
  end

  defp normalize_core_reply(:ok), do: :ok

  defp normalize_core_reply({:error, {:transport, %CoreTransportError{} = error}}) do
    {:error, legacy_transport_reason(error)}
  end

  defp normalize_core_reply({:error, %CoreTransportError{} = error}) do
    {:error, legacy_transport_reason(error)}
  end

  defp normalize_core_reply({:error, reason}), do: {:error, legacy_transport_reason(reason)}
  defp normalize_core_reply(other), do: {:error, {:unexpected_core_reply, other}}

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

  defp translate_down_reason(%CoreTransportError{} = error), do: legacy_transport_reason(error)
  defp translate_down_reason(reason), do: legacy_transport_reason(reason)

  defp transport_error(reason), do: {:error, {:transport, reason}}
end
