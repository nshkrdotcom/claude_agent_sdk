defmodule ClaudeAgentSDK.Streaming.Session do
  @moduledoc """
  GenServer managing a persistent Claude streaming session.

  Real sessions run on `ClaudeAgentSDK.Runtime.CLI`, which itself runs on the
  shared core session API. The in-memory mock mode remains local so tests can
  drive streaming behavior deterministically without a subprocess.
  """

  use GenServer

  alias ClaudeAgentSDK.Config.Timeouts
  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Process, as: SDKProcess
  alias ClaudeAgentSDK.Runtime.CLI
  alias ClaudeAgentSDK.Streaming.EventParser
  alias ClaudeAgentSDK.Streaming.Termination
  alias ClaudeAgentSDK.Streaming.Timeout
  alias CliSubprocessCore.ExecutionSurface
  alias ExternalRuntimeTransport.Transport.Error, as: CoreTransportError

  @type subscriber_ref :: reference()
  @type subscriber_pid :: pid()

  defstruct [
    :mode,
    :runtime_session,
    :runtime_transport,
    :runtime_ref,
    :runtime_event_tag,
    :runtime_projection_state,
    :runtime_session_monitor_ref,
    :runtime_transport_monitor_ref,
    :session_id,
    :options,
    :subscribers,
    :subscriber_monitors,
    :subscriber_queue,
    :active_subscriber,
    :message_buffer,
    :accumulated_text,
    :stop_reason,
    :stderr_buffer
  ]

  @type state :: %__MODULE__{
          mode: :runtime | :mock,
          runtime_session: pid() | nil,
          runtime_transport: pid() | nil,
          runtime_ref: reference() | nil,
          runtime_event_tag: atom() | nil,
          runtime_projection_state: CLI.ProjectionState.t() | nil,
          runtime_session_monitor_ref: reference() | nil,
          runtime_transport_monitor_ref: reference() | nil,
          session_id: String.t() | nil,
          options: Options.t(),
          subscribers: %{optional(reference()) => pid()},
          subscriber_monitors: %{optional(reference()) => reference()},
          subscriber_queue: [{reference(), String.t()}],
          active_subscriber: reference() | nil,
          message_buffer: String.t(),
          accumulated_text: String.t(),
          stop_reason: String.t() | nil,
          stderr_buffer: String.t()
        }

  @doc """
  Starts a new streaming session.
  """
  @spec start_link(Options.t() | nil) :: GenServer.on_start()
  def start_link(options \\ nil) do
    start_link(options, [])
  end

  @doc false
  @spec start_link(Options.t() | nil, keyword()) :: GenServer.on_start()
  def start_link(options, start_opts) when is_list(start_opts) do
    GenServer.start_link(__MODULE__, {options, start_opts})
  end

  @doc """
  Sends a message to the session and returns a lazy event stream.
  """
  @spec send_message(pid(), String.t()) :: Enumerable.t()
  def send_message(session, message) do
    ref = make_ref()
    timeout_ms = timeout_ms_for_session(session)
    timeout = Timeout.new(timeout_ms)

    :ok = GenServer.call(session, {:subscribe, ref, self()}, Timeouts.streaming_session_ms())
    :ok = GenServer.cast(session, {:send_message, message, ref})

    Stream.resource(
      fn -> {session, ref, :active, nil, timeout} end,
      fn
        {session, ref, :complete, stop_reason, timeout} ->
          {:halt, {session, ref, :complete, stop_reason, timeout}}

        {session, ref, :active, stop_reason, timeout} ->
          receive do
            {:stream_event, ^ref, event} ->
              {new_stop_reason, complete?} = Termination.step(event, stop_reason)
              status = if complete?, do: :complete, else: :active
              {[event], {session, ref, status, new_stop_reason, Timeout.reset(timeout)}}

            {:stream_error, ^ref, reason} ->
              {[%{type: :error, error: reason}], {session, ref, :complete, stop_reason, timeout}}

            {:stream_complete, ^ref} ->
              {:halt, {session, ref, :complete, stop_reason, timeout}}
          after
            Timeout.remaining_ms(timeout) ->
              {[Timeout.timeout_event()], {session, ref, :complete, stop_reason, timeout}}
          end
      end,
      fn {session, ref, _status, _stop_reason, _timeout} ->
        GenServer.cast(session, {:unsubscribe, ref})
      end
    )
  end

  @doc false
  @spec push_events(pid(), [map()]) :: :ok
  def push_events(session, events) when is_pid(session) and is_list(events) do
    payload = Enum.map_join(events, "\n", &Jason.encode!/1)
    send(session, {:mock_stdout, payload <> "\n"})
    :ok
  end

  @doc """
  Closes the session.
  """
  @spec close(pid()) :: :ok
  def close(session) do
    GenServer.stop(session, :normal, Timeouts.streaming_session_ms())
  catch
    :exit, {:noproc, _} -> :ok
  end

  @doc """
  Returns the current Claude session id if one has been observed.
  """
  @spec get_session_id(pid()) :: {:ok, String.t()} | {:error, :no_session_id}
  def get_session_id(session) do
    GenServer.call(session, :get_session_id, Timeouts.streaming_session_ms())
  end

  @impl true
  def init({options, start_opts}) when is_list(start_opts) do
    opts = options || %Options{}

    case Keyword.get(start_opts, :mock_stream, false) do
      true ->
        {:ok, initial_state(opts, :mock)}

      false ->
        init_runtime_session(opts, start_opts)
    end
  end

  def init(options) do
    init({options, []})
  end

  @impl true
  def handle_call({:subscribe, ref, pid}, _from, state) do
    state = put_subscriber(state, ref, pid)
    active_subscriber = state.active_subscriber || ref
    {:reply, :ok, %{state | active_subscriber: active_subscriber}}
  end

  def handle_call(:get_session_id, _from, state) do
    case state.session_id do
      nil -> {:reply, {:error, :no_session_id}, state}
      id -> {:reply, {:ok, id}, state}
    end
  end

  def handle_call(:timeout_ms, _from, state) do
    {:reply, timeout_ms_for_options(state.options), state}
  end

  @impl true
  def handle_cast({:send_message, message, ref}, state) do
    if state.active_subscriber == ref do
      case dispatch_message(state, message) do
        :ok ->
          {:noreply, state}

        {:error, reason} ->
          notify_stream_error(state, ref, reason)
          {:noreply, handle_message_complete(%{state | accumulated_text: "", stop_reason: nil})}
      end
    else
      {:noreply, %{state | subscriber_queue: state.subscriber_queue ++ [{ref, message}]}}
    end
  end

  def handle_cast({:unsubscribe, ref}, state) do
    {:noreply, drop_subscriber(state, ref)}
  end

  @impl true
  def handle_info(
        {event_tag, runtime_ref, {:event, core_event}},
        %{runtime_ref: runtime_ref, runtime_event_tag: runtime_event_tag} = state
      )
      when event_tag == runtime_event_tag do
    {events, projection_state} = CLI.project_event(core_event, state.runtime_projection_state)
    session_id = projection_state.session_id || extract_session_id(events) || state.session_id

    maybe_broadcast_events(state, events)

    {stop_reason, complete?} = Termination.reduce(events, state.stop_reason)

    state = %{
      state
      | runtime_projection_state: projection_state,
        accumulated_text: projection_state.accumulated_text,
        session_id: session_id,
        stop_reason: stop_reason
    }

    if complete? do
      {:noreply, handle_message_complete(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {_event_tag, runtime_ref, {:event, _core_event}},
        %{runtime_ref: runtime_ref} = state
      ) do
    {:noreply, state}
  end

  def handle_info({:mock_stdout, data}, %{mode: :mock} = state) do
    {:noreply, handle_mock_stdout(state, data)}
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, pid, reason},
        %{runtime_transport_monitor_ref: monitor_ref, runtime_transport: pid} = state
      ) do
    if normal_exit_reason?(reason) do
      {:noreply, %{state | runtime_transport: nil, runtime_transport_monitor_ref: nil}}
    else
      {:stop, {:subprocess_failed, reason}, state}
    end
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, pid, reason},
        %{runtime_session_monitor_ref: monitor_ref, runtime_session: pid} = state
      ) do
    if normal_exit_reason?(reason) do
      broadcast_complete(state.subscribers)
      {:stop, :normal, %{state | runtime_session: nil, runtime_session_monitor_ref: nil}}
    else
      {:stop, {:subprocess_failed, reason}, state}
    end
  end

  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state)
      when is_reference(monitor_ref) do
    case find_subscriber_ref_by_monitor(state, monitor_ref) do
      nil ->
        {:noreply, state}

      subscriber_ref ->
        {:noreply, drop_subscriber(state, subscriber_ref, skip_demonitor: true, promote: true)}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{runtime_session: runtime_session} = state)
      when is_pid(runtime_session) do
    demonitor_runtime(state)
    demonitor_subscribers(state)
    _ = CLI.close(runtime_session)
    :ok
  catch
    _, _ -> :ok
  end

  def terminate(_reason, state) do
    demonitor_runtime(state)
    demonitor_subscribers(state)
    :ok
  catch
    _, _ -> :ok
  end

  @doc false
  def __shell_escape__(arg) when is_binary(arg), do: SDKProcess.__shell_escape__(arg)

  defp init_runtime_session(%Options{} = options, start_opts) do
    runtime_ref = make_ref()
    startup_mode = normalize_startup_mode(Keyword.get(start_opts, :startup_mode, :eager))
    runtime_event_tag = Keyword.get(start_opts, :session_event_tag, CLI.session_event_tag())

    case prevalidate_runtime_start(options) do
      :ok ->
        runtime_opts =
          [
            options: %{options | include_partial_messages: true},
            subscriber: {self(), runtime_ref},
            session_event_tag: runtime_event_tag,
            startup_mode: startup_mode
          ]
          |> maybe_put(:task_supervisor, Keyword.get(start_opts, :task_supervisor))
          |> maybe_put(
            :headless_timeout_ms,
            Keyword.get(start_opts, :headless_timeout_ms, :infinity)
          )
          |> maybe_put(:max_buffer_size, Keyword.get(start_opts, :max_buffer_size))
          |> maybe_put(:max_stderr_buffer_size, Keyword.get(start_opts, :max_stderr_buffer_size))

        case CLI.start_session(runtime_opts) do
          {:ok, runtime_session, %{info: info, projection_state: projection_state}} ->
            runtime_transport = get_in(info, [:transport, :pid])

            {:ok,
             %{
               initial_state(options, :runtime)
               | runtime_session: runtime_session,
                 runtime_transport: runtime_transport,
                 runtime_ref: runtime_ref,
                 runtime_event_tag: Map.get(info, :session_event_tag, runtime_event_tag),
                 runtime_projection_state: projection_state,
                 runtime_session_monitor_ref: Process.monitor(runtime_session),
                 runtime_transport_monitor_ref: maybe_monitor(runtime_transport)
             }}

          {:error, reason} ->
            {:stop, {:subprocess_failed, normalize_runtime_start_error(reason)}}
        end

      {:error, reason} ->
        {:stop, {:subprocess_failed, reason}}
    end
  end

  defp initial_state(options, mode) do
    %__MODULE__{
      mode: mode,
      runtime_session: nil,
      runtime_transport: nil,
      runtime_ref: nil,
      runtime_event_tag: nil,
      runtime_projection_state: nil,
      runtime_session_monitor_ref: nil,
      runtime_transport_monitor_ref: nil,
      session_id: nil,
      options: options,
      subscribers: %{},
      subscriber_monitors: %{},
      subscriber_queue: [],
      active_subscriber: nil,
      message_buffer: "",
      accumulated_text: "",
      stop_reason: nil,
      stderr_buffer: ""
    }
  end

  defp normalize_startup_mode(:lazy), do: :lazy
  defp normalize_startup_mode(_), do: :eager

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_monitor(pid) when is_pid(pid), do: Process.monitor(pid)
  defp maybe_monitor(_pid), do: nil

  defp timeout_ms_for_session(session) when is_pid(session) do
    GenServer.call(session, :timeout_ms, Timeouts.streaming_session_ms())
  catch
    :exit, _ -> Timeouts.streaming_session_ms()
  end

  defp timeout_ms_for_session(_session), do: Timeouts.streaming_session_ms()

  defp timeout_ms_for_options(%Options{timeout_ms: timeout_ms})
       when is_integer(timeout_ms) and timeout_ms > 0,
       do: timeout_ms

  defp timeout_ms_for_options(_options), do: Timeouts.streaming_session_ms()

  defp dispatch_message(%{mode: :mock}, _message), do: :ok

  defp dispatch_message(%{runtime_session: runtime_session}, message)
       when is_pid(runtime_session) do
    CLI.send_input(runtime_session, message)
  end

  defp dispatch_message(_state, _message), do: {:error, :not_connected}

  defp handle_mock_stdout(state, data) do
    buffer = state.message_buffer <> data

    {:ok, events, remaining, accumulated_text} =
      EventParser.parse_buffer(buffer, state.accumulated_text)

    session_id = extract_session_id(events) || state.session_id

    maybe_broadcast_events(state, events)

    {stop_reason, complete?} = Termination.reduce(events, state.stop_reason)

    state = %{
      state
      | message_buffer: remaining,
        accumulated_text: accumulated_text,
        session_id: session_id,
        stop_reason: stop_reason
    }

    if complete? do
      handle_message_complete(state)
    else
      state
    end
  end

  defp maybe_broadcast_events(%{active_subscriber: nil}, _events), do: :ok

  defp maybe_broadcast_events(state, events) do
    broadcast_events_to(state.active_subscriber, state.subscribers, events)
    :ok
  end

  defp handle_message_complete(state) do
    state = %{state | accumulated_text: "", stop_reason: nil}

    case state.subscriber_queue do
      [] ->
        %{state | active_subscriber: nil, subscriber_queue: []}

      [{next_ref, next_message} | rest] ->
        state = %{state | active_subscriber: next_ref, subscriber_queue: rest}

        case dispatch_message(state, next_message) do
          :ok ->
            state

          {:error, reason} ->
            notify_stream_error(state, next_ref, reason)
            handle_message_complete(state)
        end
    end
  end

  defp notify_stream_error(state, ref, reason) do
    case Map.get(state.subscribers, ref) do
      nil -> :ok
      pid -> send(pid, {:stream_error, ref, reason})
    end
  end

  defp put_subscriber(state, ref, pid) when is_reference(ref) and is_pid(pid) do
    state = remove_subscriber_monitor(state, ref)
    monitor_ref = Process.monitor(pid)

    %{
      state
      | subscribers: Map.put(state.subscribers, ref, pid),
        subscriber_monitors: Map.put(state.subscriber_monitors, ref, monitor_ref)
    }
  end

  defp remove_subscriber_monitor(state, ref) do
    case Map.pop(state.subscriber_monitors, ref) do
      {monitor_ref, monitors} when is_reference(monitor_ref) ->
        Process.demonitor(monitor_ref, [:flush])
        %{state | subscriber_monitors: monitors}

      {_, monitors} ->
        %{state | subscriber_monitors: monitors}
    end
  end

  defp drop_subscriber(state, ref, opts \\ []) do
    skip_demonitor? = Keyword.get(opts, :skip_demonitor, false)
    promote? = Keyword.get(opts, :promote, false)

    state =
      if skip_demonitor? do
        %{state | subscriber_monitors: Map.delete(state.subscriber_monitors, ref)}
      else
        remove_subscriber_monitor(state, ref)
      end

    subscribers = Map.delete(state.subscribers, ref)
    queue = Enum.reject(state.subscriber_queue, fn {queue_ref, _msg} -> queue_ref == ref end)
    state = %{state | subscribers: subscribers, subscriber_queue: queue}

    cond do
      state.active_subscriber != ref ->
        state

      not promote? ->
        %{state | active_subscriber: nil}

      true ->
        promote_subscriber_after_drop(state)
    end
  end

  defp promote_subscriber_after_drop(%{subscriber_queue: []} = state) do
    %{state | active_subscriber: nil}
  end

  defp promote_subscriber_after_drop(
         %{subscriber_queue: [{next_ref, next_message} | rest]} = state
       ) do
    state = %{state | active_subscriber: next_ref, subscriber_queue: rest}

    case dispatch_message(state, next_message) do
      :ok ->
        state

      {:error, reason} ->
        notify_stream_error(state, next_ref, reason)
        handle_message_complete(state)
    end
  end

  defp find_subscriber_ref_by_monitor(state, monitor_ref) when is_reference(monitor_ref) do
    Enum.find_value(state.subscriber_monitors, fn {subscriber_ref, ref} ->
      if ref == monitor_ref, do: subscriber_ref
    end)
  end

  defp extract_session_id(events) do
    Enum.find_value(events, fn
      %{session_id: id} when is_binary(id) -> id
      _ -> nil
    end)
  end

  defp broadcast_events_to(ref, subscribers, events) do
    case Map.get(subscribers, ref) do
      nil ->
        :ok

      pid ->
        Enum.each(events, fn event ->
          send(pid, {:stream_event, ref, event})
        end)
    end
  end

  defp broadcast_complete(subscribers) do
    Enum.each(subscribers, fn {ref, pid} ->
      send(pid, {:stream_complete, ref})
    end)
  end

  defp demonitor_runtime(state) do
    if is_reference(state.runtime_session_monitor_ref) do
      Process.demonitor(state.runtime_session_monitor_ref, [:flush])
    end

    if is_reference(state.runtime_transport_monitor_ref) do
      Process.demonitor(state.runtime_transport_monitor_ref, [:flush])
    end
  end

  defp demonitor_subscribers(state) do
    Enum.each(state.subscriber_monitors, fn {_ref, monitor_ref} ->
      Process.demonitor(monitor_ref, [:flush])
    end)
  end

  defp normal_exit_reason?(reason), do: reason in [:normal, :shutdown, {:shutdown, :normal}]

  defp prevalidate_runtime_start(%Options{cwd: cwd, execution_surface: execution_surface})
       when is_binary(cwd) and cwd != "" do
    if ExecutionSurface.nonlocal_path_surface?(execution_surface) or File.dir?(cwd) do
      :ok
    else
      {:error, {:cwd_not_found, cwd}}
    end
  end

  defp prevalidate_runtime_start(_options), do: :ok

  defp normalize_runtime_start_error({:transport, %CoreTransportError{reason: reason}}),
    do: reason

  defp normalize_runtime_start_error(%CoreTransportError{reason: reason}), do: reason
  defp normalize_runtime_start_error(reason), do: reason
end
