defmodule ClaudeAgentSDK.Transport.Erlexec do
  @moduledoc """
  Transport implementation backed by erlexec.

  This transport supports OS-level user execution via erlexec's `:user` option,
  which `Port`-based transports cannot provide.
  """

  use GenServer

  import Kernel, except: [send: 2]

  @behaviour ClaudeAgentSDK.Transport

  alias ClaudeAgentSDK.{CLI, Options, Runtime, TaskSupervisor}
  alias ClaudeAgentSDK.Config.{Buffers, Timeouts}
  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig
  alias ClaudeAgentSDK.Errors.CLIJSONDecodeError
  alias ClaudeAgentSDK.Process, as: SDKProcess
  alias ClaudeAgentSDK.Transport.ExecOptions
  alias ClaudeAgentSDK.Transport.Setup

  defstruct subprocess: nil,
            subscribers: %{},
            stdout_buffer: "",
            pending_lines: :queue.new(),
            drain_scheduled?: false,
            status: :disconnected,
            stderr_callback: nil,
            stderr_buffer: "",
            max_buffer_size: Buffers.max_stdout_buffer_bytes(),
            max_stderr_buffer_size: Buffers.max_stderr_buffer_bytes(),
            overflowed?: false,
            pending_calls: %{},
            finalize_timer_ref: nil,
            headless_timeout_ms: Timeouts.transport_headless_ms(),
            headless_timer_ref: nil,
            task_supervisor: TaskSupervisor,
            startup_opts: nil

  @type subscriber_info :: %{
          monitor_ref: reference(),
          tag: ClaudeAgentSDK.Transport.subscription_tag()
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
    case start(opts) do
      {:ok, pid} ->
        Process.link(pid)
        {:ok, pid}

      {:error, _reason} = error ->
        error
    end
  catch
    :error, :badarg ->
      transport_error(:not_connected)

    :exit, reason ->
      transport_error(reason)
  end

  @impl ClaudeAgentSDK.Transport
  def send(transport, message) when is_pid(transport) do
    case safe_call(transport, {:send, message}) do
      {:ok, result} -> result
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
      {:ok, result} -> result
      {:error, reason} -> transport_error(reason)
    end
  end

  @spec unsubscribe(pid(), pid()) :: :ok
  def unsubscribe(transport, pid) when is_pid(transport) and is_pid(pid) do
    case safe_call(transport, {:unsubscribe, pid}) do
      {:ok, :ok} -> :ok
      {:error, _} -> :ok
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

      {:error, reason} when reason == :not_connected ->
        :ok

      {:error, reason} ->
        transport_error(reason)
    end
  end

  @impl ClaudeAgentSDK.Transport
  def interrupt(transport) when is_pid(transport) do
    case safe_call(transport, :interrupt) do
      {:ok, :ok} ->
        :ok

      {:error, reason} when reason == :not_connected ->
        :ok

      {:error, reason} ->
        transport_error(reason)
    end
  end

  @impl ClaudeAgentSDK.Transport
  def end_input(transport) when is_pid(transport) do
    case safe_call(transport, :end_input) do
      {:ok, result} -> result
      {:error, reason} -> transport_error(reason)
    end
  end

  @impl ClaudeAgentSDK.Transport
  def status(transport) when is_pid(transport) do
    case safe_call(transport, :status) do
      {:ok, status} when status in [:connected, :disconnected, :error] -> status
      {:ok, _other} -> :error
      {:error, _reason} -> :disconnected
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

    state = %__MODULE__{
      subprocess: nil,
      status: :disconnected,
      stderr_callback: options.stderr,
      max_buffer_size: max_buffer_size_from_options(options),
      max_stderr_buffer_size:
        normalize_max_stderr_buffer_size(Keyword.get(opts, :max_stderr_buffer_size, nil)),
      overflowed?: false,
      startup_opts: opts,
      task_supervisor: Keyword.get(opts, :task_supervisor, TaskSupervisor),
      headless_timeout_ms:
        normalize_headless_timeout_ms(
          Keyword.get(opts, :headless_timeout_ms, Timeouts.transport_headless_ms())
        )
    }

    case startup_mode_from_opts(opts) do
      :lazy ->
        {:ok, maybe_schedule_headless_timer(state), {:continue, :start_subprocess}}

      :eager ->
        case start_subprocess(state, opts, options) do
          {:ok, connected_state} ->
            {:ok, connected_state}

          {:error, reason} ->
            {:stop, reason}
        end
    end
  end

  @impl GenServer
  def handle_continue(:start_subprocess, %{startup_opts: opts} = state) do
    options = Keyword.get(opts, :options) || %Options{}

    case start_subprocess(state, opts, options) do
      {:ok, connected_state} ->
        {:noreply, connected_state}

      {:error, reason} ->
        {:stop, reason, %{state | startup_opts: nil}}
    end
  end

  @impl GenServer
  def handle_call({:subscribe, pid, tag}, _from, state) do
    state =
      state
      |> put_subscriber(pid, tag)
      |> cancel_headless_timer()

    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {existing, subscribers} = Map.pop(state.subscribers, pid)

    if is_map(existing) and is_reference(existing.monitor_ref) do
      Process.demonitor(existing.monitor_ref, [:flush])
    end

    state = %{state | subscribers: subscribers} |> maybe_schedule_headless_timer()
    {:reply, :ok, state}
  end

  def handle_call({:send, message}, from, %{subprocess: {pid, _}} = state) do
    case start_io_task(state, fn -> send_payload(pid, message) end) do
      {:ok, task} ->
        pending_calls = Map.put(state.pending_calls, task.ref, from)
        {:noreply, %{state | pending_calls: pending_calls}}

      {:error, reason} ->
        {:reply, transport_error(reason), state}
    end
  end

  def handle_call({:send, _}, _from, %{subprocess: nil} = state) do
    {:reply, transport_error(:not_connected), state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:end_input, from, %{subprocess: {pid, _}} = state) do
    case start_io_task(state, fn -> send_eof(pid) end) do
      {:ok, task} ->
        pending_calls = Map.put(state.pending_calls, task.ref, from)
        {:noreply, %{state | pending_calls: pending_calls}}

      {:error, reason} ->
        {:reply, transport_error(reason), state}
    end
  end

  def handle_call(:end_input, _from, %{subprocess: nil} = state) do
    {:reply, transport_error(:not_connected), state}
  end

  def handle_call(:interrupt, from, %{subprocess: {pid, _}} = state) do
    case start_io_task(state, fn -> interrupt_subprocess(pid) end) do
      {:ok, task} ->
        pending_calls = Map.put(state.pending_calls, task.ref, from)
        {:noreply, %{state | pending_calls: pending_calls}}

      {:error, reason} ->
        {:reply, transport_error(reason), state}
    end
  end

  def handle_call(:interrupt, _from, %{subprocess: nil} = state) do
    {:reply, transport_error(:not_connected), state}
  end

  def handle_call(:stderr, _from, state) do
    {:reply, state.stderr_buffer, state}
  end

  def handle_call(:force_close, _from, state) do
    state = force_stop_subprocess(state)
    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_info({:stdout, os_pid, data}, %{subprocess: {_pid, os_pid}} = state) do
    data = IO.iodata_to_binary(data)

    state =
      state
      |> append_stdout_data(data)
      |> drain_stdout_lines(Buffers.max_lines_per_batch())
      |> maybe_schedule_drain()

    {:noreply, state}
  end

  def handle_info({:stderr, _os_pid, data}, state) do
    data = IO.iodata_to_binary(data)
    stderr_buffer = append_stderr_data(state.stderr_buffer, data, state.max_stderr_buffer_size)

    dispatch_stderr_callback(state.stderr_callback, data)
    send_event(state.subscribers, {:stderr, data})

    {:noreply, %{state | stderr_buffer: stderr_buffer}}
  end

  def handle_info({ref, result}, %{pending_calls: pending_calls} = state)
      when is_reference(ref) do
    case Map.pop(pending_calls, ref) do
      {nil, _} ->
        {:noreply, state}

      {from, rest} ->
        Process.demonitor(ref, [:flush])
        GenServer.reply(from, normalize_call_result(result))
        {:noreply, %{state | pending_calls: rest}}
    end
  end

  def handle_info({:DOWN, os_pid, :process, pid, reason}, %{subprocess: {pid, os_pid}} = state) do
    state = cancel_finalize_timer(state)

    timer_ref =
      Process.send_after(
        self(),
        {:finalize_exit, os_pid, pid, reason},
        Timeouts.transport_finalize_ms()
      )

    {:noreply, %{state | finalize_timer_ref: timer_ref}}
  end

  def handle_info({:finalize_exit, os_pid, pid, reason}, %{subprocess: {pid, os_pid}} = state) do
    state =
      state
      |> Map.put(:finalize_timer_ref, nil)
      |> Map.put(:drain_scheduled?, false)
      |> drain_stdout_lines(Buffers.max_lines_per_batch())

    if :queue.is_empty(state.pending_lines) do
      state = flush_stdout_fragment(state)
      send_event(state.subscribers, {:exit, reason})
      {:stop, :normal, %{state | status: :disconnected, subprocess: nil}}
    else
      Kernel.send(self(), {:finalize_exit, os_pid, pid, reason})
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %{pending_calls: pending_calls} = state)
      when is_reference(ref) do
    case Map.pop(pending_calls, ref) do
      {from, rest} when not is_nil(from) ->
        GenServer.reply(from, transport_error({:send_failed, reason}))
        {:noreply, %{state | pending_calls: rest}}

      {nil, _} ->
        handle_subscriber_down(ref, pid, state)
    end
  end

  def handle_info(:drain_stdout, state) do
    state =
      state
      |> Map.put(:drain_scheduled?, false)
      |> drain_stdout_lines(Buffers.max_lines_per_batch())
      |> maybe_schedule_drain()

    {:noreply, state}
  end

  def handle_info(:headless_timeout, state) do
    state = %{state | headless_timer_ref: nil}

    if map_size(state.subscribers) == 0 and not is_nil(state.subprocess) do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    state =
      state
      |> cancel_finalize_timer()
      |> cancel_headless_timer()

    demonitor_subscribers(state.subscribers)
    cleanup_pending_calls(state.pending_calls)
    _ = force_stop_subprocess(state)
    :ok
  catch
    _, _ -> :ok
  end

  defp safe_call(transport, message, timeout \\ Timeouts.transport_call_ms())

  defp safe_call(transport, message, timeout)
       when is_pid(transport) and is_integer(timeout) and timeout >= 0 do
    case start_call_task(fn ->
           try do
             {:ok, GenServer.call(transport, message, :infinity)}
           catch
             :exit, reason -> {:error, normalize_call_exit(reason)}
           end
         end) do
      {:ok, task} ->
        await_call_task(task, timeout)

      {:error, reason} ->
        {:error, normalize_call_task_start_error(reason)}
    end
  end

  defp await_call_task(task, timeout) when is_integer(timeout) and timeout >= 0 do
    task_ref = Map.get(task, :ref)
    task_pid = Map.get(task, :pid)

    if is_reference(task_ref) do
      receive do
        {^task_ref, result} ->
          Process.demonitor(task_ref, [:flush])
          result

        {:DOWN, ^task_ref, :process, _pid, reason} ->
          {:error, normalize_call_exit(reason)}
      after
        timeout ->
          maybe_kill_task(task_pid)
          Process.demonitor(task_ref, [:flush])
          {:error, :timeout}
      end
    else
      {:error, {:call_exit, :invalid_task_ref}}
    end
  end

  defp maybe_kill_task(pid) when is_pid(pid) do
    Process.exit(pid, :kill)
    :ok
  catch
    :exit, _ ->
      :ok
  end

  defp maybe_kill_task(_), do: :ok

  defp normalize_call_task_start_error(reason), do: {:call_exit, reason}

  defp normalize_call_exit({:noproc, _}), do: :not_connected
  defp normalize_call_exit(:noproc), do: :not_connected
  defp normalize_call_exit({:normal, _}), do: :not_connected
  defp normalize_call_exit({:shutdown, _}), do: :not_connected
  defp normalize_call_exit({:timeout, _}), do: :timeout
  defp normalize_call_exit(reason), do: {:call_exit, reason}

  defp normalize_call_result(:ok), do: :ok
  defp normalize_call_result({:error, {:transport, _reason}} = error), do: error
  defp normalize_call_result({:error, reason}), do: transport_error(reason)
  defp normalize_call_result(other), do: transport_error({:unexpected_task_result, other})

  defp start_call_task(fun) do
    supervisor = configured_task_supervisor()

    try do
      {:ok, Task.Supervisor.async_nolink(supervisor, fun)}
    catch
      :exit, {:noproc, _} ->
        try do
          {:ok, Task.async(fun)}
        catch
          :exit, reason -> {:error, {:task_start_failed, reason}}
        end

      :exit, :noproc ->
        try do
          {:ok, Task.async(fun)}
        catch
          :exit, reason -> {:error, {:task_start_failed, reason}}
        end

      :exit, reason ->
        {:error, {:task_start_failed, reason}}
    end
  end

  defp configured_task_supervisor do
    Application.get_env(:claude_agent_sdk, :task_supervisor, TaskSupervisor)
  end

  defp resolve_command(opts, options) do
    case Keyword.fetch(opts, :command) do
      {:ok, command} when is_binary(command) ->
        with :ok <- validate_command(command) do
          {:ok, command, Keyword.get(opts, :args, [])}
        end

      {:ok, _command} ->
        {:error, :invalid_command}

      :error ->
        case build_command_from_options(options) do
          {:ok, {cmd, args}} -> {:ok, cmd, args}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp startup_mode_from_opts(opts) do
    case Keyword.get(opts, :startup_mode, :eager) do
      :lazy -> :lazy
      _ -> :eager
    end
  end

  defp validate_command(command) when is_binary(command) do
    if command_exists?(command) do
      :ok
    else
      {:error, {:command_not_found, command}}
    end
  end

  defp command_exists?(command) when is_binary(command) do
    cond do
      String.trim(command) == "" ->
        false

      String.contains?(command, [" ", "\t", "\n"]) ->
        # Treat composite shell command strings as caller-managed.
        true

      String.contains?(command, "/") ->
        File.exists?(command)

      true ->
        not is_nil(System.find_executable(command))
    end
  end

  defp start_subprocess(state, opts, options) do
    subscriber = Keyword.get(opts, :subscriber)

    with {:ok, command, args} <- resolve_command(opts, options),
         :ok <- Setup.validate_cwd(options.cwd),
         :ok <- Runtime.ensure_erlexec_started(),
         cmd <- build_command(command, args),
         exec_opts <- build_exec_opts(options),
         {:ok, pid, os_pid} <- :exec.run(cmd, exec_opts) do
      state =
        %{state | subprocess: {pid, os_pid}, status: :connected}
        |> Map.put(:stderr_callback, options.stderr)
        |> Map.put(:max_buffer_size, max_buffer_size_from_options(options))
        |> Map.put(:startup_opts, nil)

      with {:ok, state} <- add_bootstrap_subscriber(state, subscriber) do
        {:ok, maybe_schedule_headless_timer(state)}
      end
    end
  end

  defp add_bootstrap_subscriber(state, nil), do: {:ok, state}

  defp add_bootstrap_subscriber(state, pid) when is_pid(pid),
    do: {:ok, put_subscriber(state, pid, :legacy)}

  defp add_bootstrap_subscriber(state, {pid, tag})
       when is_pid(pid) and (tag == :legacy or is_reference(tag)) do
    {:ok, put_subscriber(state, pid, tag)}
  end

  defp add_bootstrap_subscriber(_state, _subscriber), do: {:error, :invalid_subscriber}

  defp put_subscriber(state, pid, tag) do
    subscribers =
      case Map.fetch(state.subscribers, pid) do
        {:ok, %{monitor_ref: monitor_ref}} ->
          Map.put(state.subscribers, pid, %{monitor_ref: monitor_ref, tag: tag})

        {:ok, monitor_ref} when is_reference(monitor_ref) ->
          Map.put(state.subscribers, pid, %{monitor_ref: monitor_ref, tag: tag})

        :error ->
          monitor_ref = Process.monitor(pid)
          Map.put(state.subscribers, pid, %{monitor_ref: monitor_ref, tag: tag})
      end

    %{state | subscribers: subscribers}
  end

  defp handle_subscriber_down(ref, pid, state) do
    subscribers =
      case Map.pop(state.subscribers, pid) do
        {%{monitor_ref: ^ref}, rest} -> rest
        {^ref, rest} -> rest
        {_, rest} -> rest
      end

    state = %{state | subscribers: subscribers}

    if map_size(subscribers) == 0 do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp maybe_schedule_headless_timer(%{headless_timer_ref: ref} = state) when not is_nil(ref),
    do: state

  defp maybe_schedule_headless_timer(%{subscribers: subscribers} = state)
       when map_size(subscribers) > 0,
       do: state

  defp maybe_schedule_headless_timer(%{headless_timeout_ms: :infinity} = state), do: state

  defp maybe_schedule_headless_timer(%{headless_timeout_ms: timeout_ms} = state)
       when is_integer(timeout_ms) and timeout_ms > 0 do
    timer_ref = Process.send_after(self(), :headless_timeout, timeout_ms)
    %{state | headless_timer_ref: timer_ref}
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

  defp start_io_task(state, fun) when is_function(fun, 0) do
    {:ok, Task.Supervisor.async_nolink(state.task_supervisor, fun)}
  catch
    :exit, {:noproc, _} ->
      fallback_start_io_task(fun)

    :exit, :noproc ->
      fallback_start_io_task(fun)

    :exit, reason ->
      {:error, {:task_start_failed, reason}}
  end

  defp fallback_start_io_task(fun) when is_function(fun, 0) do
    {:ok, Task.async(fun)}
  catch
    :exit, reason ->
      {:error, {:task_start_failed, reason}}
  end

  defp send_payload(pid, message) do
    payload = message |> normalize_payload() |> ensure_newline()
    :exec.send(pid, payload)
    :ok
  catch
    kind, reason ->
      transport_error({:send_failed, {kind, reason}})
  end

  defp send_eof(pid) do
    :exec.send(pid, :eof)
    :ok
  catch
    kind, reason ->
      transport_error({:send_failed, {kind, reason}})
  end

  defp interrupt_subprocess(pid) when is_pid(pid) do
    _ = :exec.kill(pid, 2)
    :ok
  catch
    _, _ ->
      transport_error(:not_connected)
  end

  defp send_event(subscribers, event) do
    Enum.each(subscribers, fn {pid, info} ->
      dispatch_event(pid, info, event)
    end)
  end

  defp dispatch_event(pid, %{tag: :legacy}, {:message, line}),
    do: Kernel.send(pid, {:transport_message, line})

  defp dispatch_event(pid, %{tag: :legacy}, {:error, reason}),
    do: Kernel.send(pid, {:transport_error, reason})

  defp dispatch_event(pid, %{tag: :legacy}, {:stderr, data}),
    do: Kernel.send(pid, {:transport_stderr, data})

  defp dispatch_event(pid, %{tag: :legacy}, {:exit, reason}),
    do: Kernel.send(pid, {:transport_exit, reason})

  defp dispatch_event(pid, %{tag: ref}, event) when is_reference(ref),
    do: Kernel.send(pid, {:claude_agent_sdk_transport, ref, event})

  defp dispatch_event(pid, monitor_ref, {:message, line}) when is_reference(monitor_ref),
    do: Kernel.send(pid, {:transport_message, line})

  defp dispatch_event(pid, monitor_ref, {:error, reason}) when is_reference(monitor_ref),
    do: Kernel.send(pid, {:transport_error, reason})

  defp dispatch_event(pid, monitor_ref, {:stderr, data}) when is_reference(monitor_ref),
    do: Kernel.send(pid, {:transport_stderr, data})

  defp dispatch_event(pid, monitor_ref, {:exit, reason}) when is_reference(monitor_ref),
    do: Kernel.send(pid, {:transport_exit, reason})

  defp append_stdout_data(%{overflowed?: true} = state, data) do
    case drop_until_next_newline(data) do
      :none ->
        state

      {:rest, rest} ->
        state
        |> Map.put(:overflowed?, false)
        |> Map.put(:stdout_buffer, "")
        |> append_stdout_data(rest)
    end
  end

  defp append_stdout_data(state, data) do
    full = state.stdout_buffer <> data
    {complete_lines, remaining} = split_complete_lines(full)

    pending_lines =
      Enum.reduce(complete_lines, state.pending_lines, fn line, queue ->
        :queue.in(line, queue)
      end)

    state = %{state | pending_lines: pending_lines, stdout_buffer: "", overflowed?: false}

    if byte_size(remaining) > state.max_buffer_size do
      send_event(state.subscribers, {:error, buffer_overflow_error(state, remaining)})
      %{state | stdout_buffer: "", overflowed?: true}
    else
      %{state | stdout_buffer: remaining}
    end
  end

  defp drain_stdout_lines(state, 0), do: state

  defp drain_stdout_lines(state, remaining) when is_integer(remaining) and remaining > 0 do
    case :queue.out(state.pending_lines) do
      {:empty, _queue} ->
        state

      {{:value, line}, queue} ->
        state = %{state | pending_lines: queue}

        if byte_size(line) > state.max_buffer_size do
          send_event(state.subscribers, {:error, buffer_overflow_error(state, line)})
        else
          send_event(state.subscribers, {:message, line})
        end

        drain_stdout_lines(state, remaining - 1)
    end
  end

  defp maybe_schedule_drain(%{drain_scheduled?: true} = state), do: state

  defp maybe_schedule_drain(state) do
    if :queue.is_empty(state.pending_lines) do
      state
    else
      Kernel.send(self(), :drain_stdout)
      %{state | drain_scheduled?: true}
    end
  end

  defp split_complete_lines(""), do: {[], ""}

  defp split_complete_lines(data) do
    case :binary.split(data, "\n", [:global]) do
      [single] ->
        {[], single}

      parts ->
        {complete, [rest]} = Enum.split(parts, length(parts) - 1)
        {Enum.map(complete, &strip_trailing_cr/1), rest}
    end
  end

  defp flush_stdout_fragment(state) do
    line = trim_ascii(state.stdout_buffer)

    cond do
      line == "" ->
        %{state | stdout_buffer: "", overflowed?: false, drain_scheduled?: false}

      byte_size(line) > state.max_buffer_size ->
        send_event(state.subscribers, {:error, buffer_overflow_error(state, line)})
        %{state | stdout_buffer: "", overflowed?: false, drain_scheduled?: false}

      true ->
        send_event(state.subscribers, {:message, line})
        %{state | stdout_buffer: "", overflowed?: false, drain_scheduled?: false}
    end
  end

  defp cancel_finalize_timer(%{finalize_timer_ref: nil} = state), do: state

  defp cancel_finalize_timer(state) do
    _ = Process.cancel_timer(state.finalize_timer_ref, async: false, info: false)
    flush_finalize_message(state.subprocess)
    %{state | finalize_timer_ref: nil}
  end

  defp flush_finalize_message({pid, os_pid}) do
    receive do
      {:finalize_exit, ^os_pid, ^pid, _reason} -> :ok
    after
      0 -> :ok
    end
  end

  defp flush_finalize_message(_), do: :ok

  defp drop_until_next_newline(data) do
    case :binary.match(data, "\n") do
      :nomatch ->
        :none

      {idx, 1} ->
        rest_start = idx + 1
        rest_size = byte_size(data) - rest_start

        rest =
          if rest_size > 0 do
            :binary.part(data, rest_start, rest_size)
          else
            ""
          end

        {:rest, rest}
    end
  end

  defp strip_trailing_cr(line) do
    size = byte_size(line)

    if size > 0 and :binary.at(line, size - 1) == 13 do
      :binary.part(line, 0, size - 1)
    else
      line
    end
  end

  # Fast ASCII-only trim for framing whitespace and CRLF handling.
  defp trim_ascii(binary) when is_binary(binary) do
    binary
    |> trim_ascii_leading()
    |> trim_ascii_trailing()
  end

  defp trim_ascii_leading(<<char, rest::binary>>) when char in [9, 10, 13, 32],
    do: trim_ascii_leading(rest)

  defp trim_ascii_leading(binary), do: binary

  defp trim_ascii_trailing(binary), do: do_trim_ascii_trailing(binary, byte_size(binary))

  defp do_trim_ascii_trailing(_binary, 0), do: ""

  defp do_trim_ascii_trailing(binary, size) when size > 0 do
    last = :binary.at(binary, size - 1)

    if last in [9, 10, 13, 32] do
      do_trim_ascii_trailing(binary, size - 1)
    else
      :binary.part(binary, 0, size)
    end
  end

  defp append_stderr_data(_existing, _data, max_size)
       when not is_integer(max_size) or max_size <= 0,
       do: ""

  defp append_stderr_data(existing, data, max_size) do
    combined = existing <> data
    combined_size = byte_size(combined)

    if combined_size <= max_size do
      combined
    else
      :binary.part(combined, combined_size - max_size, max_size)
    end
  end

  defp dispatch_stderr_callback(callback, data) when is_function(callback, 1) do
    {lines, _tail} = split_complete_lines(data)

    lines
    |> Enum.map(&trim_ascii/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(callback)
  end

  defp dispatch_stderr_callback(_callback, _data), do: :ok

  defp cleanup_pending_calls(pending_calls) do
    Enum.each(pending_calls, fn {ref, from} ->
      Process.demonitor(ref, [:flush])
      GenServer.reply(from, transport_error(:transport_stopped))
    end)
  end

  defp demonitor_subscribers(subscribers) do
    Enum.each(subscribers, fn
      {_pid, %{monitor_ref: ref}} -> Process.demonitor(ref, [:flush])
      {_pid, ref} when is_reference(ref) -> Process.demonitor(ref, [:flush])
    end)
  end

  defp force_stop_subprocess(%{subprocess: {pid, _}} = state) do
    stop_subprocess(pid)
    %{state | subprocess: nil, status: :disconnected}
  end

  defp force_stop_subprocess(state), do: state

  defp stop_subprocess(pid) when is_pid(pid) do
    :exec.stop(pid)
    _ = :exec.kill(pid, 9)
    :ok
  catch
    _, _ ->
      :ok
  end

  defp build_command(command, args) when is_binary(command) and is_list(args) do
    quoted_args = Enum.map(args, &SDKProcess.__shell_escape__/1)
    Enum.join([command | quoted_args], " ")
  end

  defp build_exec_opts(%Options{} = options) do
    ExecOptions.erlexec(options)
  end

  defp normalize_payload(message) when is_binary(message), do: message

  defp normalize_payload(message) when is_map(message) or is_list(message),
    do: Jason.encode!(message)

  defp normalize_payload(message), do: to_string(message)

  defp ensure_newline(payload) do
    if String.ends_with?(payload, "\n"), do: payload, else: payload <> "\n"
  end

  @doc false
  def __exec_opts__(%Options{} = options), do: build_exec_opts(options)

  defp max_buffer_size_from_options(%Options{max_buffer_size: size}) do
    normalize_max_buffer_size(size)
  end

  defp normalize_max_buffer_size(size) when is_integer(size) and size > 0, do: size
  defp normalize_max_buffer_size(_), do: Buffers.max_stdout_buffer_bytes()

  defp normalize_max_stderr_buffer_size(size) when is_integer(size) and size > 0, do: size
  defp normalize_max_stderr_buffer_size(_), do: Buffers.max_stderr_buffer_bytes()

  defp normalize_headless_timeout_ms(:infinity), do: :infinity
  defp normalize_headless_timeout_ms(size) when is_integer(size) and size > 0, do: size
  defp normalize_headless_timeout_ms(_), do: Timeouts.transport_headless_ms()

  defp build_command_from_options(%Options{} = options) do
    case CLI.resolve_executable(options) do
      {:ok, executable} ->
        args = CLIConfig.streaming_bidirectional_args()

        args = args ++ ClaudeAgentSDK.Options.to_stream_json_args(options)
        {:ok, {executable, args}}

      {:error, :not_found} ->
        {:error, :cli_not_found}
    end
  end

  defp buffer_overflow_error(state, data) do
    %CLIJSONDecodeError{
      message: "JSON message exceeded maximum buffer size of #{state.max_buffer_size} bytes",
      line: truncate_line(data),
      original_error: {:buffer_overflow, byte_size(data), state.max_buffer_size}
    }
  end

  defp truncate_line(data) when is_binary(data) do
    if byte_size(data) > Buffers.error_preview_length() do
      binary_part(data, 0, Buffers.error_preview_length()) <> "..."
    else
      data
    end
  end

  defp transport_error(reason), do: {:error, {:transport, reason}}
end
