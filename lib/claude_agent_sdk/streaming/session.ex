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
  require Logger

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Streaming.EventParser

  @type subscriber_ref :: reference()
  @type subscriber_pid :: pid()

  defstruct [
    # {erlexec_pid, os_pid}
    :subprocess,
    # Claude session ID
    :session_id,
    # Configuration options
    :options,
    # %{ref => pid} - all subscribers
    :subscribers,
    # [{ref, message}] - FIFO queue of pending subscribers with their messages
    :subscriber_queue,
    # ref - currently active subscriber receiving events
    :active_subscriber,
    # Incomplete JSON buffer
    :message_buffer,
    # Currently assembling text
    :accumulated_text,
    # Monitor reference for subprocess
    :monitor_ref
  ]

  # 5 minutes
  @default_timeout 300_000

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
    GenServer.start_link(__MODULE__, options)
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

    # Subscribe to receive events
    :ok = GenServer.call(session, {:subscribe, ref, self()}, @default_timeout)

    # Send the message to Claude
    :ok = GenServer.cast(session, {:send_message, message, ref})

    # Return stream that receives events
    Stream.resource(
      fn -> {session, ref, :active} end,
      fn state ->
        {session, ref, status} = state

        if status == :complete do
          {:halt, state}
        else
          receive do
            {:stream_event, ^ref, event} ->
              # Check if this is a completion event
              new_status =
                case event.type do
                  :message_stop -> :complete
                  _ -> :active
                end

              {[event], {session, ref, new_status}}

            {:stream_error, ^ref, reason} ->
              error_event = %{type: :error, error: reason}
              {[error_event], {session, ref, :complete}}

            {:stream_complete, ^ref} ->
              {:halt, {session, ref, :complete}}
          after
            @default_timeout ->
              Logger.warning("Streaming timeout after #{@default_timeout}ms")
              timeout_event = %{type: :error, error: :timeout}
              {[timeout_event], {session, ref, :complete}}
          end
        end
      end,
      fn {session, ref, _status} ->
        # Unsubscribe on stream completion
        GenServer.cast(session, {:unsubscribe, ref})
      end
    )
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
    GenServer.stop(session, :normal, @default_timeout)
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
    GenServer.call(session, :get_session_id, @default_timeout)
  end

  ## GenServer Callbacks

  @impl true
  def init(options) do
    opts = options || %Options{}

    # Build CLI command with streaming flags
    args = build_streaming_args(opts)

    # Start subprocess with stdin/stdout/stderr pipes
    case spawn_subprocess(args) do
      {:ok, subprocess, monitor_ref} ->
        state = %__MODULE__{
          subprocess: subprocess,
          session_id: nil,
          options: opts,
          subscribers: %{},
          subscriber_queue: [],
          active_subscriber: nil,
          message_buffer: "",
          accumulated_text: "",
          monitor_ref: monitor_ref
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:subprocess_failed, reason}}
    end
  end

  @impl true
  def handle_call({:subscribe, ref, pid}, _from, state) do
    # Add to subscribers map
    subscribers = Map.put(state.subscribers, ref, pid)

    # If no active subscriber, activate this one immediately
    new_active =
      if state.active_subscriber == nil do
        ref
      else
        state.active_subscriber
      end

    {:reply, :ok, %{state | subscribers: subscribers, active_subscriber: new_active}}
  end

  @impl true
  def handle_call(:get_session_id, _from, state) do
    case state.session_id do
      nil -> {:reply, {:error, :no_session_id}, state}
      id -> {:reply, {:ok, id}, state}
    end
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

      {pid, _os_pid} = state.subprocess

      :ok = :exec.send(pid, json_msg <> "\n")
      Logger.debug("Sent message to Claude (#{byte_size(message)} bytes)")
      {:noreply, state}
    else
      # Queue this message to be sent later
      queue = state.subscriber_queue ++ [{ref, message}]
      {:noreply, %{state | subscriber_queue: queue}}
    end
  end

  @impl true
  def handle_cast({:unsubscribe, ref}, state) do
    subscribers = Map.delete(state.subscribers, ref)
    queue = Enum.reject(state.subscriber_queue, fn {r, _msg} -> r == ref end)

    # If this was the active subscriber, activate next in queue
    {new_active, new_queue} =
      if state.active_subscriber == ref do
        case queue do
          [] -> {nil, []}
          # Will be activated by message_stop
          _ -> {nil, queue}
        end
      else
        {state.active_subscriber, queue}
      end

    {:noreply,
     %{
       state
       | subscribers: subscribers,
         subscriber_queue: new_queue,
         active_subscriber: new_active
     }}
  end

  @impl true
  def handle_info({:stdout, os_pid, data}, state) do
    # Match on subprocess os_pid
    {_erlexec_pid, subprocess_os_pid} = state.subprocess

    if os_pid == subprocess_os_pid do
      # Parse streaming JSON events
      new_buffer = state.message_buffer <> data

      {:ok, events, remaining_buffer, new_accumulated} =
        EventParser.parse_buffer(new_buffer, state.accumulated_text)

      # Extract session ID from first message_start event
      new_session_id = extract_session_id(events) || state.session_id

      # Check if message completed
      message_complete? = Enum.any?(events, &(&1.type == :message_stop))

      # Broadcast events to ACTIVE subscriber only
      if state.active_subscriber do
        broadcast_events_to(state.active_subscriber, state.subscribers, events)
      end

      # If message complete, activate next subscriber and send their message
      new_state =
        if message_complete? do
          case state.subscriber_queue do
            [{next_ref, next_message} | rest] ->
              # Activate next subscriber
              new_state = %{
                state
                | active_subscriber: next_ref,
                  subscriber_queue: rest,
                  # Reset for next message
                  accumulated_text: "",
                  message_buffer: remaining_buffer,
                  session_id: new_session_id
              }

              # Send their queued message immediately (synchronously within this handler)
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

              new_state

            [] ->
              # No more subscribers
              %{
                state
                | active_subscriber: nil,
                  subscriber_queue: [],
                  accumulated_text: "",
                  message_buffer: remaining_buffer,
                  session_id: new_session_id
              }
          end
        else
          %{
            state
            | message_buffer: remaining_buffer,
              accumulated_text: new_accumulated,
              session_id: new_session_id
          }
        end

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:stderr, os_pid, data}, state) do
    {_erlexec_pid, subprocess_os_pid} = state.subprocess

    if os_pid == subprocess_os_pid do
      # Log stderr but continue
      Logger.warning("Claude stderr: #{data}")
      {:noreply, state}
    else
      {:noreply, state}
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

    # Add user options (but skip verbose since we already added it)
    user_args = Options.to_args(options)

    user_args =
      user_args
      |> Enum.reject(&(&1 == "--verbose"))
      |> strip_flag_with_value("--output-format")

    base_args ++ user_args
  end

  defp spawn_subprocess(args) do
    # Find claude executable
    executable =
      System.find_executable("claude-code") || System.find_executable("claude") || "claude"

    # Build command string
    quoted_args = Enum.map(args, &shell_escape/1)
    cmd = Enum.join([executable | quoted_args], " ")

    # Build exec options with environment variables
    exec_opts = [
      :stdin,
      :stdout,
      :stderr,
      :monitor,
      {:env, build_env_vars()}
    ]

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

  defp strip_flag_with_value(args, flag) do
    args
    |> Enum.reduce({[], false}, fn
      ^flag, {acc, _skip_next} ->
        {acc, true}

      _value, {acc, true} ->
        {acc, false}

      value, {acc, false} ->
        {[value | acc], false}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp shell_escape(arg) when is_binary(arg) do
    # Simple shell escaping - wrap in quotes if contains special chars
    if String.contains?(arg, [" ", "\"", "'", "$", "`", "\\", "&", "|", ";", "(", ")", "<", ">"]) do
      ~s("#{String.replace(arg, "\"", "\\\"")}")
    else
      arg
    end
  end

  defp build_env_vars do
    # Pass authentication environment variables to subprocess
    base_vars =
      []
      |> add_env_var("CLAUDE_AGENT_OAUTH_TOKEN")
      |> add_env_var("ANTHROPIC_API_KEY")
      |> add_env_var("PATH")
      |> add_env_var("HOME")

    # Add SDK identification (matching Process.ex behavior)
    sdk_vars = [
      {~c"CLAUDE_CODE_ENTRYPOINT", ~c"sdk-elixir"},
      {~c"CLAUDE_AGENT_SDK_VERSION", version_string() |> String.to_charlist()}
    ]

    base_vars ++ sdk_vars
  end

  defp version_string do
    case Application.spec(:claude_agent_sdk, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  defp add_env_var(env_vars, var_name) do
    case System.get_env(var_name) do
      nil -> env_vars
      "" -> env_vars
      value -> [{String.to_charlist(var_name), String.to_charlist(value)} | env_vars]
    end
  end

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
