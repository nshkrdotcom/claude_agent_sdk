defmodule ClaudeAgentSDK.Streaming.Session do
  @moduledoc """
  GenServer managing a persistent bidirectional streaming session with Claude.

  Maintains a long-lived subprocess with stdin/stdout pipes for interactive
  conversations with character-level streaming support via `--include-partial-messages`.

  ## Architecture

  ```
  Session GenServer
    |
    ├─> erlexec subprocess (claude CLI)
    │   ├─ stdin  (send messages)
    │   ├─ stdout (receive streaming events)
    │   └─ stderr (capture errors)
    |
    └─> Subscriber Map
        ├─ ref1 => {pid1, current_stream_ref}
        ├─ ref2 => {pid2, current_stream_ref}
        └─ ...
  ```

  ## State

  - `subprocess` - {erlexec_pid, os_pid} tuple
  - `session_id` - Claude session ID (extracted from first message)
  - `options` - ClaudeAgentSDK.Options for configuration
  - `subscribers` - Map of ref => {subscriber_pid, active: boolean}
  - `message_buffer` - Incomplete JSON buffer from stdout
  - `accumulated_text` - Current message text being assembled

  ## Lifecycle

  1. `init/1` - Spawn subprocess with streaming flags
  2. `:read_output` loop - Continuously read from stdout
  3. Parse events via EventParser
  4. Broadcast to subscribers
  5. `terminate/2` - Clean shutdown of subprocess
  """

  use GenServer
  alias ClaudeAgentSDK.Log, as: Logger

  alias ClaudeAgentSDK.{CLI, Options, Runtime}
  alias ClaudeAgentSDK.Config.Timeouts
  alias ClaudeAgentSDK.Shell
  alias ClaudeAgentSDK.Streaming.EventParser
  alias ClaudeAgentSDK.Streaming.Termination
  alias ClaudeAgentSDK.Transport.ExecOptions

  @type subscriber_ref :: reference()
  @type subscriber_pid :: pid()

  defstruct [
    # {erlexec_pid, os_pid}
    :subprocess,
    # Enable mock stream input (tests)
    :mock_stream?,
    # Claude session ID
    :session_id,
    # Configuration options
    :options,
    # %{ref => pid} - all subscribers
    :subscribers,
    # %{ref => monitor_ref} - subscriber process monitors
    :subscriber_monitors,
    # [{ref, message}] - FIFO queue of pending subscribers with their messages
    :subscriber_queue,
    # ref - currently active subscriber receiving events
    :active_subscriber,
    # Incomplete JSON buffer
    :message_buffer,
    # Currently assembling text
    :accumulated_text,
    # Current stop reason for message termination
    :stop_reason,
    # Monitor reference for subprocess
    :monitor_ref
  ]

  ## Public API

  @doc """
  Starts a new streaming session.

  Spawns a Claude CLI subprocess with streaming flags enabled and
  begins listening for events.

  ## Parameters
  - `options` - Optional `ClaudeAgentSDK.Options` struct

  ## Returns
  - `{:ok, pid}` - Session started successfully
  - `{:error, reason}` - Failed to start subprocess

  ## Examples

      {:ok, session} = Session.start_link()
      {:ok, session} = Session.start_link(%Options{model: "opus", max_turns: 10})
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
  Sends a message to the Claude session and returns a stream of events.

  The returned stream yields events as they arrive from Claude, enabling
  real-time typewriter effects and incremental UI updates.

  ## Parameters
  - `session` - Session PID
  - `message` - Message text to send

  ## Returns
  Stream of event maps (see EventParser for event types)

  ## Examples

      {:ok, session} = Session.start_link()

      # Get streaming response
      Session.send_message(session, "Hello")
      |> Stream.each(fn
        %{type: :text_delta, text: text} -> IO.write(text)
        %{type: :message_stop} -> IO.puts("")
      end)
      |> Stream.run()
  """
  @spec send_message(pid(), String.t()) :: Enumerable.t()
  def send_message(session, message) do
    ref = make_ref()
    timeout_ms = timeout_ms_for_session(session)

    # Subscribe to receive events
    :ok = GenServer.call(session, {:subscribe, ref, self()}, Timeouts.streaming_session_ms())

    # Send the message to Claude
    :ok = GenServer.cast(session, {:send_message, message, ref})

    # Return stream that receives events
    Stream.resource(
      fn -> {session, ref, :active, nil, timeout_ms} end,
      fn state ->
        {session, ref, status, stop_reason, timeout_ms} = state

        if status == :complete do
          {:halt, state}
        else
          receive do
            {:stream_event, ^ref, event} ->
              {new_stop_reason, message_complete?} = Termination.step(event, stop_reason)

              new_status =
                if message_complete? do
                  :complete
                else
                  :active
                end

              {[event], {session, ref, new_status, new_stop_reason, timeout_ms}}

            {:stream_error, ^ref, reason} ->
              error_event = %{type: :error, error: reason}
              {[error_event], {session, ref, :complete, stop_reason, timeout_ms}}

            {:stream_complete, ^ref} ->
              {:halt, {session, ref, :complete, stop_reason, timeout_ms}}
          after
            timeout_ms ->
              Logger.warning("Streaming timeout after #{timeout_ms}ms")
              timeout_event = %{type: :error, error: :timeout}
              {[timeout_event], {session, ref, :complete, stop_reason, timeout_ms}}
          end
        end
      end,
      fn {session, ref, _status, _stop_reason, _timeout_ms} ->
        # Unsubscribe on stream completion
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
  Closes the streaming session and terminates the subprocess.

  ## Parameters
  - `session` - Session PID

  ## Examples

      {:ok, session} = Session.start_link()
      # ... use session ...
      :ok = Session.close(session)
  """
  @spec close(pid()) :: :ok
  def close(session) do
    GenServer.stop(session, :normal, Timeouts.streaming_session_ms())
  catch
    :exit, {:noproc, _} -> :ok
  end

  @doc """
  Gets the Claude session ID.

  The session ID is extracted from the first `message_start` event.

  ## Returns
  - `{:ok, session_id}` - Session ID available
  - `{:error, :no_session_id}` - Session not yet initialized

  ## Examples

      {:ok, session} = Session.start_link()
      {:ok, session_id} = Session.get_session_id(session)
  """
  @spec get_session_id(pid()) :: {:ok, String.t()} | {:error, :no_session_id}
  def get_session_id(session) do
    GenServer.call(session, :get_session_id, Timeouts.streaming_session_ms())
  end

  ## GenServer Callbacks

  @impl true
  def init({options, start_opts}) when is_list(start_opts) do
    opts = options || %Options{}
    startup_mode = startup_mode_from_opts(start_opts)

    case Keyword.get(start_opts, :mock_stream, false) do
      true ->
        {:ok, initial_state(opts, true)}

      false ->
        init_with_subprocess(opts, startup_mode)
    end
  end

  def init(options) do
    init({options, []})
  end

  defp init_with_subprocess(opts, :lazy) do
    {:ok, initial_state(opts, false), {:continue, :start_subprocess}}
  end

  defp init_with_subprocess(opts, :eager) do
    state = initial_state(opts, false)

    case start_subprocess(state) do
      {:ok, connected_state} -> {:ok, connected_state}
      {:error, reason} -> {:stop, {:subprocess_failed, reason}}
    end
  end

  @impl true
  def handle_continue(:start_subprocess, state) do
    case start_subprocess(state) do
      {:ok, connected_state} ->
        {:noreply, connected_state}

      {:error, reason} ->
        {:stop, {:subprocess_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, ref, pid}, _from, state) do
    state = put_subscriber(state, ref, pid)

    # If no active subscriber, activate this one immediately
    new_active =
      if state.active_subscriber == nil do
        ref
      else
        state.active_subscriber
      end

    {:reply, :ok, %{state | active_subscriber: new_active}}
  end

  @impl true
  def handle_call(:get_session_id, _from, state) do
    case state.session_id do
      nil -> {:reply, {:error, :no_session_id}, state}
      id -> {:reply, {:ok, id}, state}
    end
  end

  @impl true
  def handle_call(:timeout_ms, _from, state) do
    {:reply, timeout_ms_for_options(state.options), state}
  end

  @impl true
  def handle_cast({:send_message, message, ref}, state) do
    # Only send if this subscriber is active
    if state.active_subscriber == ref do
      # Send JSON message to Claude via stdin
      json_msg =
        Jason.encode!(%{
          "type" => "user",
          "message" => %{
            "role" => "user",
            "content" => message
          }
        })

      case state.subprocess do
        {pid, _os_pid} ->
          :ok = :exec.send(pid, json_msg <> "\n")
          Logger.debug("Sent message to Claude (#{byte_size(message)} bytes)")

        nil ->
          Logger.debug("Mock session ignoring send_message (#{byte_size(message)} bytes)")
      end

      {:noreply, state}
    else
      # Queue this message to be sent later
      queue = state.subscriber_queue ++ [{ref, message}]
      {:noreply, %{state | subscriber_queue: queue}}
    end
  end

  @impl true
  def handle_cast({:unsubscribe, ref}, state) do
    {:noreply, drop_subscriber(state, ref)}
  end

  @impl true
  def handle_info({:stdout, os_pid, data}, %{subprocess: {_, subprocess_os_pid}} = state) do
    if os_pid == subprocess_os_pid do
      {:noreply, handle_stdout_data(state, data)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:stdout, _os_pid, _data}, state), do: {:noreply, state}

  def handle_info({:mock_stdout, data}, %{mock_stream?: true} = state) do
    {:noreply, handle_stdout_data(state, data)}
  end

  @impl true
  def handle_info({:stderr, os_pid, data}, %{subprocess: {_, subprocess_os_pid}} = state) do
    if os_pid == subprocess_os_pid do
      handle_stderr_data(data, state.options.stderr)
    end

    {:noreply, state}
  end

  def handle_info({:stderr, _os_pid, _data}, state), do: {:noreply, state}

  def handle_info({:DOWN, os_pid, :process, _pid, _reason}, %{subprocess: nil} = state)
      when is_integer(os_pid) do
    {:noreply, state}
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

  @impl true
  def handle_info({:DOWN, os_pid, :process, _pid, reason}, state) do
    # Subprocess died - match on os_pid (integer)
    {_erlexec_pid, subprocess_os_pid} = state.subprocess

    if os_pid == subprocess_os_pid do
      Logger.info("Claude subprocess terminated: #{inspect(reason)}")
      broadcast_complete(state.subscribers)
      {:stop, :normal, state}
    else
      # Different process
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, %{subprocess: nil}), do: :ok

  def terminate(_reason, state) do
    # Clean shutdown of subprocess
    {pid, _os_pid} = state.subprocess

    try do
      :exec.stop(pid)
    catch
      _, _ -> :ok
    end

    :ok
  end

  ## Private Functions

  defp startup_mode_from_opts(start_opts) do
    case Keyword.get(start_opts, :startup_mode, :eager) do
      :lazy -> :lazy
      _ -> :eager
    end
  end

  defp initial_state(opts, mock_stream?) do
    %__MODULE__{
      subprocess: nil,
      mock_stream?: mock_stream?,
      session_id: nil,
      options: opts,
      subscribers: %{},
      subscriber_monitors: %{},
      subscriber_queue: [],
      active_subscriber: nil,
      message_buffer: "",
      accumulated_text: "",
      stop_reason: nil,
      monitor_ref: nil
    }
  end

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

  defp start_subprocess(state) do
    args = build_streaming_args(state.options)

    case spawn_subprocess(args, state.options) do
      {:ok, subprocess, monitor_ref} ->
        {:ok, %{state | subprocess: subprocess, monitor_ref: monitor_ref}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_stderr_data(data, stderr_callback) when is_function(stderr_callback, 1) do
    data
    |> IO.iodata_to_binary()
    |> split_complete_lines()
    |> elem(0)
    |> Enum.map(&trim_ascii/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(stderr_callback)
  end

  defp handle_stderr_data(data, _stderr_callback) do
    Logger.warning("Claude stderr: #{data}")
  end

  defp split_complete_lines(""), do: {[], ""}

  defp split_complete_lines(buffer) when is_binary(buffer) do
    case :binary.split(buffer, "\n", [:global]) do
      [single] ->
        {[], single}

      parts ->
        {complete, [rest]} = Enum.split(parts, length(parts) - 1)
        {Enum.map(complete, &strip_trailing_cr/1), rest}
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

  defp handle_stdout_data(state, data) do
    new_buffer = state.message_buffer <> data

    {:ok, events, remaining_buffer, new_accumulated} =
      EventParser.parse_buffer(new_buffer, state.accumulated_text)

    new_session_id = extract_session_id(events) || state.session_id

    {stop_reason, message_complete?} = Termination.reduce(events, state.stop_reason)

    maybe_broadcast_events(state, events)

    state = %{
      state
      | message_buffer: remaining_buffer,
        accumulated_text: new_accumulated,
        session_id: new_session_id,
        stop_reason: stop_reason
    }

    if message_complete? do
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
    state =
      %{
        state
        | accumulated_text: "",
          stop_reason: nil
      }

    case state.subscriber_queue do
      [] ->
        %{state | active_subscriber: nil, subscriber_queue: []}

      [{next_ref, next_message} | rest] ->
        state = %{state | active_subscriber: next_ref, subscriber_queue: rest}
        :ok = send_queued_message(state, next_message)
        state
    end
  end

  defp send_queued_message(%{subprocess: nil}, _next_message), do: :ok

  defp send_queued_message(state, next_message) do
    json_msg =
      Jason.encode!(%{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => next_message
        }
      })

    {pid, _} = state.subprocess
    :ok = :exec.send(pid, json_msg <> "\n")
    Logger.debug("Sent queued message to Claude (#{byte_size(next_message)} bytes)")
    :ok
  end

  defp build_streaming_args(%Options{} = options) do
    base_args = [
      "--input-format",
      "stream-json",
      "--output-format",
      "stream-json",
      "--include-partial-messages",
      # Required for stream-json output
      "--verbose"
    ]

    # Add user options (but skip verbose/output_format since we already added them)
    user_args = Options.to_stream_json_args(options)
    base_args ++ user_args
  end

  defp spawn_subprocess(args, %Options{} = options) do
    Runtime.ensure_erlexec_started!()

    if is_binary(options.cwd) and not File.dir?(options.cwd) do
      {:error, {:cwd_not_found, options.cwd}}
    else
      # Find claude executable
      executable = CLI.resolve_executable!(options)

      # Build command string
      quoted_args = Enum.map(args, &shell_escape/1)
      cmd = Enum.join([executable | quoted_args], " ")

      # Build exec options with environment variables
      exec_opts = build_exec_opts(options)

      # Spawn subprocess
      case :exec.run(cmd, exec_opts) do
        {:ok, pid, os_pid} ->
          # Monitor the process using erlexec's monitor option
          # The :monitor flag in exec_opts already sets this up
          {:ok, {pid, os_pid}, :monitor_via_erlexec}

        {:error, reason} ->
          Logger.error("Failed to start Claude CLI subprocess",
            cmd: cmd,
            reason: reason,
            env_keys: env_keys(exec_opts)
          )

          {:error, reason}
      end
    end
  end

  defp shell_escape(arg) when is_binary(arg) do
    Shell.escape_arg(arg)
  end

  @doc false
  def __shell_escape__(arg) when is_binary(arg), do: shell_escape(arg)

  defp build_exec_opts(%Options{} = options) do
    ExecOptions.erlexec(options)
  end

  @doc false
  def __exec_opts__(%Options{} = options), do: build_exec_opts(options)

  defp env_keys(opts) do
    opts
    |> Enum.find_value([], fn
      {:env, env} -> env
      _ -> nil
    end)
    |> Enum.map(fn
      {key, _} when is_list(key) -> to_string(key)
      {key, _} -> inspect(key)
    end)
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
    :ok = send_queued_message(state, next_message)
    state
  end

  defp find_subscriber_ref_by_monitor(state, monitor_ref) when is_reference(monitor_ref) do
    Enum.find_value(state.subscriber_monitors, fn {subscriber_ref, ref} ->
      if ref == monitor_ref, do: subscriber_ref
    end)
  end

  defp extract_session_id(events) do
    # Look for session ID in system message (if present)
    # Note: Claude CLI may not emit session_id in all events
    # We'll try to extract it when available
    Enum.find_value(events, fn event ->
      case event do
        %{session_id: id} when is_binary(id) -> id
        _ -> nil
      end
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
    # Send complete to all remaining subscribers
    Enum.each(subscribers, fn {ref, pid} ->
      send(pid, {:stream_complete, ref})
    end)
  end
end
