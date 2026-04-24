defmodule ClaudeAgentSDK.Client do
  @moduledoc """
  Bidirectional client for Claude Code with hooks support.

  This GenServer maintains a persistent connection to the Claude CLI process,
  handles control protocol messages, and invokes hook callbacks.

  The Client enables:
  - Bidirectional streaming communication
  - Runtime hook callback invocation
  - Control protocol request/response handling
  - Message queueing and delivery

  ## Usage

      # Define hook callbacks
      def check_bash(input, _tool_use_id, _context) do
        if dangerous?(input), do: Output.deny("Blocked"), else: Output.allow()
      end

      # Configure options with hooks
      options = %Options{
        allowed_tools: ["Bash", "Write"],
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [&check_bash/3])
          ]
        }
      }

      # Start client
      {:ok, pid} = Client.start_link(options)

      # Send query
      Client.send_message(pid, "Run: echo 'Hello'")

      # Receive messages
      stream = Client.stream_messages(pid)
      Enum.each(stream, &IO.inspect/1)

      # Stop client
      Client.stop(pid)

  ## With Streaming

      {:ok, pid} = Client.start_link(options)

      # Start listening in separate process
      task = Task.async(fn ->
        Client.stream_messages(pid)
        |> Enum.take_while(&(&1.type != :result))
        |> Enum.to_list()
      end)

      # Send message
      Client.send_message(pid, "Write a function")

      # Wait for completion
      messages = Task.await(task, :infinity)

  See: https://docs.anthropic.com/en/docs/claude-code/sdk

  ## Architecture Note

  `ClaudeAgentSDK.Client` remains SDK-local because it owns the advanced control
  protocol family: hooks, permission callbacks, SDK MCP routing, and related
  request/response state. The shared core now owns the control-session lifecycle
  through `CliSubprocessCore.ProtocolSession`; this module stays above that
  boundary and keeps only Claude-specific control semantics.

  `agent_session_manager` may optionally bridge into this module through
  `ASM.Extensions.ProviderSDK.Claude`, but the bridge does not redefine these
  control APIs. Runtime control ownership remains here.
  """

  use GenServer

  alias ClaudeAgentSDK.{
    AbortSignal,
    ControlProtocol.Adapter,
    Hooks,
    LineFraming,
    Message,
    Model,
    Options,
    TaskSupervisor
  }

  alias ClaudeAgentSDK.Config.{Buffers, Env, Timeouts}
  alias ClaudeAgentSDK.ControlProtocol.Protocol
  alias ClaudeAgentSDK.Hooks.{Matcher, Output, Registry}
  alias ClaudeAgentSDK.Log, as: Logger
  alias ClaudeAgentSDK.Permission.{Context, Result}
  alias ClaudeAgentSDK.Runtime.CLI, as: RuntimeCLI
  alias ClaudeAgentSDK.Streaming.{EventParser, Termination}
  alias CliSubprocessCore.{ProtocolSession, TaskSupport}
  @edit_tools ["Write", "Edit", "MultiEdit"]

  # Client state intentionally mirrors the control-protocol lifecycle and streaming buffers.
  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct protocol_session: nil,
            protocol_session_monitor_ref: nil,
            options: nil,
            registry: nil,
            hook_callback_timeouts: %{},
            subscribers: %{},
            subscriber_monitors: %{},
            pending_requests: %{},
            pending_outbound: :queue.new(),
            pending_callbacks: %{},
            initialized: false,
            stderr_buffer: "",
            session_id: nil,
            sdk_mcp_servers: %{},
            pending_permission_change: nil,
            control_request_timeout_ms: Timeouts.client_control_request_ms(),
            permission_bridge: nil,
            accumulated_text: "",
            stream_stop_reason: nil,
            active_subscriber: nil,
            subscriber_queue: [],
            init_waiters: [],
            initialized_waiters: [],
            pending_inbound: :queue.new(),
            pending_inbound_size: 0,
            pending_inbound_dropped: 0,
            stream_buffer_limit: Buffers.stream_buffer_limit(),
            server_info: nil,
            init_request_id: nil,
            init_timeout: nil

  @typedoc """
  Client state.

  Fields:
  - `protocol_session` - Shared core-owned control session
  - `options` - Configuration options
  - `registry` - Hook callback registry
  - `hook_callback_timeouts` - Map of callback_id => timeout_ms
  - `subscribers` - Map of ref => pid for streaming subscriptions
  - `subscriber_monitors` - Map of ref => monitor_ref for subscriber lifecycle cleanup
  - `pending_requests` - Map of request_id => request task tracking entries
  - `pending_outbound` - FIFO queue of outbound payloads accepted before initialize completes
  - `pending_callbacks` - Map of request_id => %{pid, monitor_ref, signal, type} for in-flight control callbacks
  - `initialized` - Whether initialization handshake completed
  - `sdk_mcp_servers` - Map of server_name => registry_pid for SDK MCP servers
  - `accumulated_text` - Buffer for partial text (streaming, v0.6.0)
  - `active_subscriber` - Current streaming consumer reference (v0.6.0)
  - `subscriber_queue` - Pending message queue (v0.6.0)
  - `init_waiters` - Callers waiting for initialize request send
  - `initialized_waiters` - Callers waiting for initialize completion
  - `pending_inbound` - Buffered inbound events/messages before first subscriber
  - `pending_inbound_size` - Number of buffered inbound entries before first subscriber
  - `pending_inbound_dropped` - Dropped inbound entries due to buffer limit
  - `stream_buffer_limit` - Max buffered inbound entries before first subscriber
  - `control_request_timeout_ms` - Per-client timeout for control requests in milliseconds
  """
  @type state :: %__MODULE__{
          protocol_session: pid() | nil,
          protocol_session_monitor_ref: reference() | nil,
          options: Options.t(),
          registry: Registry.t(),
          hook_callback_timeouts: %{String.t() => pos_integer()},
          subscribers: %{reference() => pid()},
          subscriber_monitors: %{reference() => reference()},
          pending_requests: %{String.t() => pending_request_entry()},
          pending_outbound: :queue.queue(binary()),
          pending_callbacks: %{
            String.t() => %{
              pid: pid(),
              monitor_ref: reference(),
              signal: ClaudeAgentSDK.AbortSignal.t(),
              type: :hook | :permission
            }
          },
          initialized: boolean(),
          stderr_buffer: String.t(),
          sdk_mcp_servers: %{String.t() => pid()},
          pending_permission_change: String.t() | nil,
          control_request_timeout_ms: pos_integer(),
          permission_bridge: :ets.tid() | nil,
          accumulated_text: String.t(),
          stream_stop_reason: String.t() | nil,
          active_subscriber: reference() | nil,
          subscriber_queue: [{reference(), String.t()}],
          init_waiters: [GenServer.from()],
          initialized_waiters: [GenServer.from()],
          pending_inbound: :queue.queue(),
          pending_inbound_size: non_neg_integer(),
          pending_inbound_dropped: non_neg_integer(),
          stream_buffer_limit: non_neg_integer(),
          server_info: map() | nil,
          init_request_id: String.t() | nil,
          init_timeout: {reference(), pos_integer()} | nil
        }

  @type pending_request_entry ::
          {:initialize, reference()}
          | {:set_model, GenServer.from(), String.t(), reference()}
          | {:set_permission_mode, GenServer.from(), atom(), reference()}
          | {:interrupt, GenServer.from(), reference()}
          | {:rewind_files, GenServer.from(), reference()}
          | {:mcp_status, GenServer.from(), reference()}

  ## Public API

  @doc """
  Starts the client GenServer.

  Validates hooks configuration, starts Claude CLI process, and performs
  initialization handshake.

  ## Parameters

  - `options` - ClaudeAgentSDK.Options struct with hooks configuration
  - `opts` - Optional runtime overrides (e.g. `:execution_surface`,
    `:control_request_timeout_ms`)

  ## Returns

  - `{:ok, pid}` - Successfully started
  - `{:error, reason}` - Failed to start

  ## Examples

      options = %Options{
        hooks: %{
          pre_tool_use: [Matcher.new("Bash", [&my_hook/3])]
        }
      }

      {:ok, pid} = Client.start_link(options)
  """
  @spec start_link(Options.t(), keyword()) :: GenServer.on_start()
  def start_link(%Options{} = options, opts \\ []) when is_list(opts) do
    GenServer.start_link(__MODULE__, {options, opts})
  end

  @doc """
  Sends a message to Claude.

  In streaming mode, this queues the message for sending.

  ## Parameters

  - `client` - Client PID
  - `message` - Message string or map

  ## Returns

  `:ok` or `{:error, reason}`

  ## Examples

      Client.send_message(pid, "Write a hello world function")
  """
  @spec send_message(pid(), String.t() | map()) :: :ok | {:error, term()}
  def send_message(client, message) when is_pid(client) do
    GenServer.call(client, {:send_message, message}, :infinity)
  end

  @doc """
  Sends a request in streaming mode, injecting `session_id` when missing.

  Matches Python SDK behavior:
  - String prompts are wrapped as a `"user"` message with `parent_tool_use_id: nil`
  - Map prompts (or enumerables of maps) get `session_id` injected if absent
  """
  @spec query(pid(), String.t() | Enumerable.t(), String.t()) :: :ok | {:error, term()}
  def query(client, prompt, session_id \\ "default")

  def query(client, prompt, session_id)
      when is_pid(client) and is_binary(prompt) and is_binary(session_id) do
    message = %{
      "type" => "user",
      "message" => %{"role" => "user", "content" => prompt},
      "parent_tool_use_id" => nil,
      "session_id" => session_id
    }

    send_message(client, message)
  end

  def query(client, prompts, session_id) when is_pid(client) and is_binary(session_id) do
    Enum.reduce_while(prompts, :ok, fn msg, :ok ->
      msg =
        if is_map(msg) and not Map.has_key?(msg, "session_id") do
          Map.put(msg, "session_id", session_id)
        else
          msg
        end

      case send_message(client, msg) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Returns a stream of messages from Claude.

  Subscribes to the client and yields messages as they arrive.

  ## Parameters

  - `client` - Client PID

  ## Returns

  Enumerable stream of Message structs

  ## Examples

      Client.stream_messages(pid)
      |> Stream.filter(&(&1.type == :assistant))
      |> Enum.to_list()
  """
  @spec stream_messages(pid()) :: Enumerable.t(Message.t())
  def stream_messages(client) when is_pid(client) do
    Stream.resource(
      fn -> subscribe(client) end,
      fn state -> receive_next_message(state) end,
      fn
        {client, ref} when is_pid(client) and is_reference(ref) ->
          GenServer.cast(client, {:unsubscribe, ref})

        _ ->
          :ok
      end
    )
  end

  @doc """
  Collects messages until a result frame is received.

  Useful for workflows that only care about a single response and want
  to avoid managing streaming state manually.
  """
  @spec receive_response(pid()) :: {:ok, [Message.t()]} | {:error, term()}
  def receive_response(client) when is_pid(client) do
    case collect_until_result(stream_messages(client)) do
      {:ok, messages} ->
        {:ok, messages}

      _ ->
        {:error, :no_result}
    end
  rescue
    exception ->
      {:error, exception}
  end

  @doc """
  Streams messages until a result frame is received.

  This provides a streaming equivalent of `receive_response/1`.
  """
  @spec receive_response_stream(pid()) :: Enumerable.t(Message.t())
  def receive_response_stream(client) when is_pid(client) do
    Stream.resource(
      fn ->
        {client_pid, ref} = subscribe(client)
        {client_pid, ref, :active}
      end,
      fn
        {client_pid, ref, :halt} ->
          {:halt, {client_pid, ref}}

        {client_pid, ref, :active} ->
          receive do
            {:claude_message, message} ->
              next_state =
                if Message.final?(message) do
                  {client_pid, ref, :halt}
                else
                  {client_pid, ref, :active}
                end

              {[message], next_state}

            {:stream_event, ^ref, event} ->
              msg = %Message{
                type: :stream_event,
                subtype: nil,
                data: stream_event_data(event),
                raw: %{}
              }

              {[msg], {client_pid, ref, :active}}
          after
            Timeouts.stream_receive_ms() ->
              if Process.alive?(client_pid) do
                {[], {client_pid, ref, :active}}
              else
                {:halt, {client_pid, ref}}
              end
          end
      end,
      fn
        {client_pid, ref} when is_pid(client_pid) and is_reference(ref) ->
          GenServer.cast(client_pid, {:unsubscribe, ref})

        _ ->
          :ok
      end
    )
  end

  defp stream_event_data(event) when is_map(event) do
    raw_event = Map.get(event, :raw_event, event)

    %{
      event: raw_event,
      uuid: Map.get(event, :uuid),
      session_id: Map.get(event, :session_id),
      parent_tool_use_id: Map.get(event, :parent_tool_use_id)
    }
  end

  @doc """
  Stops the client.

  Terminates the CLI process and cleans up resources.

  ## Parameters

  - `client` - Client PID

  ## Returns

  `:ok`

  ## Examples

      Client.stop(pid)
  """
  @spec stop(pid()) :: :ok
  def stop(client) when is_pid(client) do
    GenServer.stop(client, :normal, Timeouts.client_stop_ms())
  catch
    :exit, {:noproc, _} -> :ok
  end

  @doc """
  Requests a runtime model switch.

  Returns `:ok` when the CLI confirms the change or `{:error, reason}`
  when validation fails or the CLI rejects the request.
  """
  @spec set_model(pid(), String.t()) :: :ok | {:error, term()}
  def set_model(client, model) when is_pid(client) do
    GenServer.call(client, {:set_model, model}, :infinity)
  end

  @doc """
  Sends an interrupt control request to the CLI.
  """
  @spec interrupt(pid()) :: :ok | {:error, term()}
  def interrupt(client) when is_pid(client) do
    GenServer.call(client, :interrupt, :infinity)
  end

  @doc """
  Rewinds tracked files to their state at a specific user message.

  Requires `Options.enable_file_checkpointing` to be enabled when starting the client.
  """
  @spec rewind_files(pid(), String.t()) :: :ok | {:error, term()}
  def rewind_files(client, user_message_id) when is_pid(client) and is_binary(user_message_id) do
    GenServer.call(client, {:rewind_files, user_message_id}, :infinity)
  end

  @doc """
  Retrieves the currently active model name.
  """
  @spec get_model(pid()) :: {:ok, String.t()} | {:error, :model_not_set}
  def get_model(client) when is_pid(client) do
    GenServer.call(client, :get_model)
  end

  @doc """
  Waits for the client to finish initialization.

  Returns `:ok` once the initialize handshake completes, or `{:error, reason}`
  if the client is not alive or times out.
  """
  @spec await_initialized(pid(), pos_integer() | nil) :: :ok | {:error, term()}
  def await_initialized(client, timeout_ms \\ nil) when is_pid(client) do
    timeout_ms =
      if is_integer(timeout_ms) and timeout_ms > 0 do
        timeout_ms
      else
        (init_timeout_seconds_from_env() * 1_000) |> trunc()
      end

    try do
      GenServer.call(client, :await_initialized, timeout_ms)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, _ -> {:error, :client_not_alive}
    end
  end

  @doc """
  Waits until the initialize request has been sent to the transport.

  Returns `{:ok, request_id}` once the initialize request is sent, or
  `{:error, reason}` if the client is not alive or times out.
  """
  @spec await_init_sent(pid(), pos_integer() | nil) :: {:ok, String.t()} | {:error, term()}
  def await_init_sent(client, timeout_ms \\ nil) when is_pid(client) do
    timeout_ms =
      if is_integer(timeout_ms) and timeout_ms > 0 do
        timeout_ms
      else
        Timeouts.client_init_ms()
      end

    try do
      GenServer.call(client, :await_init_sent, timeout_ms)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, _ -> {:error, :client_not_alive}
    end
  end

  @doc """
  Sets the permission mode at runtime.

  Changes how tool permissions are handled for subsequent tool uses.

  ## Parameters

  - `client` - Client PID
  - `mode` - Permission mode atom (`:default`, `:accept_edits`, `:plan`, `:bypass_permissions`, `:auto`, `:dont_ask`)

  ## Returns

  - `:ok` - Successfully changed mode
  - `{:error, :invalid_permission_mode}` - Invalid mode provided

  ## Examples

      Client.set_permission_mode(pid, :plan)
      Client.set_permission_mode(pid, :accept_edits)
      Client.set_permission_mode(pid, :bypass_permissions)
      Client.set_permission_mode(pid, :auto)
  """
  @spec set_permission_mode(pid(), ClaudeAgentSDK.Permission.permission_mode()) ::
          :ok | {:error, :invalid_permission_mode}
  def set_permission_mode(client, mode) when is_pid(client) do
    GenServer.call(client, {:set_permission_mode, mode}, :infinity)
  end

  @doc """
  Subscribes to the client's message stream and returns a subscription reference.
  """
  @spec subscribe(pid()) :: {pid(), reference() | nil}
  def subscribe(client) when is_pid(client) do
    case GenServer.call(client, {:subscribe, make_ref()}) do
      {:ok, ref} -> {client, ref}
      :ok -> {client, nil}
    end
  end

  @doc """
  Returns the server initialization info provided by the CLI.
  """
  @spec get_server_info(pid()) :: {:ok, map()} | {:error, term()}
  def get_server_info(client) when is_pid(client) do
    GenServer.call(client, :get_server_info)
  end

  @doc """
  Switches to a different agent configuration.

  ## Parameters

    * `client` - The client PID
    * `agent_name` - The name of the agent to switch to (atom)

  ## Returns

  `:ok` or `{:error, reason}`

  ## Examples

      Client.set_agent(client, :researcher)
  """
  @spec set_agent(pid(), atom()) :: :ok | {:error, term()}
  def set_agent(client, agent_name) when is_pid(client) and is_atom(agent_name) do
    GenServer.call(client, {:set_agent, agent_name})
  end

  @doc """
  Gets the currently active agent.

  ## Parameters

    * `client` - The client PID

  ## Returns

  `{:ok, agent_name}` or `{:error, reason}`

  ## Examples

      {:ok, :coder} = Client.get_agent(client)
  """
  @spec get_agent(pid()) :: {:ok, atom()} | {:error, term()}
  def get_agent(client) when is_pid(client) do
    GenServer.call(client, :get_agent)
  end

  @doc """
  Gets the list of available agent names.

  ## Parameters

    * `client` - The client PID

  ## Returns

  `{:ok, [agent_name]}` or `{:error, reason}`

  ## Examples

      {:ok, [:coder, :researcher]} = Client.get_available_agents(client)
  """
  @spec get_available_agents(pid()) :: {:ok, [atom()]} | {:error, term()}
  def get_available_agents(client) when is_pid(client) do
    GenServer.call(client, :get_available_agents)
  end

  @doc """
  Gets current MCP server connection status.

  Returns a map with `"mcpServers"` key containing a list of server status
  objects, each with:
  - `"name"` - Server name
  - `"status"` - Connection status: `"connected"`, `"pending"`, `"failed"`,
    `"needs-auth"`, `"disabled"`

  ## Parameters

    * `client` - The client PID

  ## Returns

  `{:ok, map()}` or `{:error, reason}`

  ## Examples

      {:ok, status} = Client.get_mcp_status(client)
      for server <- status["mcpServers"] do
        IO.puts("\#{server["name"]}: \#{server["status"]}")
      end
  """
  @spec get_mcp_status(pid()) :: {:ok, map()} | {:error, term()}
  def get_mcp_status(client) when is_pid(client) do
    GenServer.call(client, :get_mcp_status, :infinity)
  end

  @doc """
  Gets the current context usage reported by the Claude CLI.
  """
  @spec get_context_usage(pid()) :: {:ok, map()} | {:error, term()}
  def get_context_usage(client) when is_pid(client) do
    GenServer.call(client, :get_context_usage, :infinity)
  end

  ## GenServer Callbacks

  @impl true
  def init({%Options{} = options, opts}) when is_list(opts) do
    do_init(options, opts)
  end

  @impl true
  def init(%Options{} = options) do
    do_init(options, [])
  end

  defp do_init(options, opts) do
    control_timeout_ms = resolve_control_request_timeout_ms(opts)

    # Validate hooks and permission callback configuration before starting
    with :ok <- validate_runtime_overrides(opts),
         {:ok, options} <-
           maybe_override_execution_surface(options, Keyword.get(opts, :execution_surface)),
         :ok <- validate_hooks(options.hooks),
         :ok <- validate_permission_callback(options.can_use_tool),
         :ok <- validate_transport_error_mode(options.transport_error_mode),
         {:ok, updated_options} <- apply_agent_settings(options),
         {:ok, updated_options} <- apply_permission_mode(updated_options),
         {:ok, updated_options} <- apply_permission_streaming(updated_options),
         {:ok, updated_options} <- apply_permission_prompt_tool(updated_options),
         {:ok, updated_options, permission_bridge} <-
           maybe_attach_permission_hook(updated_options) do
      updated_options = apply_client_entrypoint_env(updated_options)
      # Extract SDK MCP server registry PIDs
      sdk_mcp_servers = extract_sdk_mcp_servers(updated_options)

      # Initialize state without starting CLI yet
      # CLI will be started in handle_continue
      state = %__MODULE__{
        protocol_session: nil,
        protocol_session_monitor_ref: nil,
        options: updated_options,
        registry: Registry.new(),
        hook_callback_timeouts: %{},
        subscribers: %{},
        subscriber_monitors: %{},
        pending_requests: %{},
        pending_outbound: :queue.new(),
        pending_callbacks: %{},
        initialized: false,
        stderr_buffer: "",
        session_id: nil,
        sdk_mcp_servers: sdk_mcp_servers,
        pending_permission_change: nil,
        control_request_timeout_ms: control_timeout_ms,
        permission_bridge: permission_bridge,
        # Streaming support fields (v0.6.0)
        accumulated_text: "",
        stream_stop_reason: nil,
        active_subscriber: nil,
        subscriber_queue: [],
        init_waiters: [],
        initialized_waiters: [],
        pending_inbound: :queue.new(),
        pending_inbound_size: 0,
        pending_inbound_dropped: 0,
        stream_buffer_limit: stream_buffer_limit(updated_options),
        server_info: nil,
        init_request_id: nil,
        init_timeout: nil
      }

      {:ok, state, {:continue, :start_cli}}
    else
      {:error, {:agent_not_found, _} = reason} ->
        {:stop, {:agents_validation_failed, reason}}

      {:error, {:invalid_agent, _, _} = reason} ->
        {:stop, {:agents_validation_failed, reason}}

      {:error, reason} ->
        {:stop, {:validation_failed, reason}}
    end
  end

  @impl true
  def handle_continue(:start_cli, state) do
    case start_cli_process(state) do
      {:ok, new_state} ->
        {:noreply, notify_init_sent_waiters(new_state)}

      {:error, reason} ->
        {:stop, {:cli_start_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    json = encode_outgoing_message(message)

    if state.initialized do
      case send_payload(state, json) do
        :ok ->
          {:reply, :ok, state}

        {:error, :not_connected} ->
          {:reply, {:error, :not_connected}, state}

        {:error, reason} ->
          Logger.error("Failed to send message", reason: inspect(reason))
          {:reply, {:error, :send_failed}, state}
      end
    else
      {:reply, :ok, enqueue_pending_outbound(state, json)}
    end
  end

  def handle_call({:set_model, model}, from, state) do
    if model_change_in_progress?(state) do
      {:reply, {:error, :model_change_in_progress}, state}
    else
      set_model_request(model, from, state)
    end
  end

  def handle_call({:subscribe, ref}, from, state) do
    {pid, _from_ref} = from
    was_empty = map_size(state.subscribers) == 0

    state = put_subscriber(state, ref, pid)

    # Activate if no active subscriber, otherwise subscriber waits
    new_active =
      if state.active_subscriber == nil do
        ref
      else
        state.active_subscriber
      end

    state = %{
      state
      | active_subscriber: new_active
    }

    state =
      if was_empty do
        flush_pending_inbound(state, ref, pid)
      else
        state
      end

    {:reply, {:ok, ref}, state}
  end

  def handle_call(:await_init_sent, from, state) do
    if is_binary(state.init_request_id) do
      {:reply, {:ok, state.init_request_id}, state}
    else
      {:noreply, %{state | init_waiters: [from | state.init_waiters]}}
    end
  end

  def handle_call(:await_initialized, from, state) do
    if state.initialized do
      {:reply, :ok, state}
    else
      {:noreply, %{state | initialized_waiters: [from | state.initialized_waiters]}}
    end
  end

  def handle_call(:stream_timeout_ms, _from, state) do
    {:reply, stream_timeout_ms(state.options), state}
  end

  # Legacy subscribe (backwards compatibility) - generate a ref for the pid
  def handle_call({:subscribe}, from, state) do
    {pid, _ref} = from
    # For backwards compat, create a ref for this pid subscription
    ref = make_ref()
    was_empty = map_size(state.subscribers) == 0
    state = put_subscriber(state, ref, pid)

    state =
      if state.active_subscriber == nil do
        %{state | active_subscriber: ref}
      else
        state
      end

    state =
      if was_empty do
        flush_pending_inbound(state, ref, pid)
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call({:set_permission_mode, mode}, from, state) do
    cond do
      state.pending_permission_change != nil ->
        {:reply, {:error, :permission_change_in_progress}, state}

      not ClaudeAgentSDK.Permission.valid_mode?(mode) ->
        {:reply, {:error, :invalid_permission_mode}, state}

      true ->
        mode_string = to_cli_permission_mode(mode)
        {request_id, json} = Protocol.encode_set_permission_mode_request(mode_string)

        start_protocol_request_task(
          state,
          request_id,
          json,
          fn task_ref -> {:set_permission_mode, from, mode, task_ref} end,
          fn next_state -> {:noreply, %{next_state | pending_permission_change: request_id}} end
        )
    end
  end

  def handle_call(:get_model, _from, state) do
    case state.options.model do
      nil -> {:reply, {:error, :model_not_set}, state}
      model -> {:reply, {:ok, model}, state}
    end
  end

  def handle_call({:set_agent, agent_name}, _from, state) do
    # Check if agents are configured
    agents = state.options.agents || %{}

    cond do
      agents == %{} ->
        {:reply, {:error, :no_agents_configured}, state}

      not Map.has_key?(agents, agent_name) ->
        {:reply, {:error, :agent_not_found}, state}

      true ->
        new_options = %{state.options | agent: agent_name}

        case apply_agent_settings(new_options) do
          {:ok, updated_options} ->
            {:reply, :ok, %{state | options: updated_options}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:get_server_info, _from, state) do
    case state.server_info do
      nil -> {:reply, {:error, :not_initialized}, state}
      info -> {:reply, {:ok, info}, state}
    end
  end

  def handle_call(:interrupt, from, state) do
    {request_id, json} = Protocol.encode_interrupt_request()

    start_protocol_request_task(
      state,
      request_id,
      json,
      fn task_ref -> {:interrupt, from, task_ref} end,
      fn next_state -> {:noreply, next_state} end
    )
  end

  def handle_call({:rewind_files, user_message_id}, from, state)
      when is_binary(user_message_id) do
    cond do
      not connected?(state) ->
        {:reply, {:error, :not_connected}, state}

      state.options.enable_file_checkpointing != true ->
        {:reply, {:error, :file_checkpointing_not_enabled}, state}

      true ->
        {request_id, json} = Protocol.encode_rewind_files_request(user_message_id)

        start_protocol_request_task(
          state,
          request_id,
          json,
          fn task_ref -> {:rewind_files, from, task_ref} end,
          fn next_state -> {:noreply, next_state} end
        )
    end
  end

  def handle_call(:get_agent, _from, state) do
    agents = state.options.agents || %{}

    case {agents, state.options.agent} do
      {agents, _} when agents == %{} ->
        {:reply, {:error, :no_agents_configured}, state}

      {_, nil} ->
        {:reply, {:error, :no_agent_configured}, state}

      {_, agent_name} when is_atom(agent_name) ->
        {:reply, {:ok, agent_name}, state}
    end
  end

  def handle_call(:get_available_agents, _from, state) do
    agents = state.options.agents || %{}
    agent_names = Map.keys(agents)
    {:reply, {:ok, agent_names}, state}
  end

  def handle_call(:get_mcp_status, from, state) do
    {req_id, json} = Protocol.encode_mcp_status_request()

    case start_request_task(
           state,
           req_id,
           fn task_ref -> {:mcp_status, from, task_ref} end,
           fn ->
             ProtocolSession.request(
               state.protocol_session,
               %{request_id: req_id, frame: json},
               timeout_ms: state.control_request_timeout_ms
             )
           end
         ) do
      {:ok, next_state} ->
        {:noreply, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_context_usage, from, state) do
    {req_id, json} = Protocol.encode_get_context_usage_request()

    case start_request_task(
           state,
           req_id,
           fn task_ref -> {:get_context_usage, from, task_ref} end,
           fn ->
             ProtocolSession.request(
               state.protocol_session,
               %{request_id: req_id, frame: json},
               timeout_ms: state.control_request_timeout_ms
             )
           end
         ) do
      {:ok, next_state} ->
        {:noreply, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:peer_request, request}, from, state) when is_map(request) do
    case Map.get(request, "subtype") do
      "hook_callback" ->
        handle_hook_callback(request, from, state)

      "can_use_tool" ->
        handle_can_use_tool_request(request, from, state)

      other ->
        Logger.warning("Unsupported control request subtype", subtype: other)
        {:reply, {:error, "Unsupported request: #{other}"}, state}
    end
  end

  defp set_model_request(model, from, state) do
    model_string = model |> to_string() |> String.trim()

    with {:ok, normalized} <- Model.validate(model_string),
         {request_id, json} = Protocol.encode_set_model_request(normalized),
         {:ok, next_state} <-
           start_request_task(
             state,
             request_id,
             fn task_ref -> {:set_model, from, normalized, task_ref} end,
             fn ->
               ProtocolSession.request(
                 state.protocol_session,
                 %{request_id: request_id, frame: json},
                 timeout_ms: state.control_request_timeout_ms
               )
             end
           ) do
      {:noreply, next_state}
    else
      {:error, :invalid_model} ->
        suggestions = Model.suggest(model_string)
        {:reply, {:error, {:invalid_model, suggestions}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp model_change_in_progress?(state) do
    Enum.any?(state.pending_requests, fn {_request_id, entry} ->
      match?({:set_model, _, _, _}, entry)
    end)
  end

  @impl true
  def handle_cast({:unsubscribe, ref}, state) do
    {:noreply, drop_subscriber(state, ref)}
  end

  @impl true
  def handle_info({:initialize_timeout, request_id}, state) do
    cond do
      state.initialized ->
        {:noreply, state}

      state.init_request_id != request_id ->
        {:noreply, state}

      true ->
        Logger.error("Initialization control request timed out",
          request_id: request_id,
          timeout_ms: elem(state.init_timeout, 1)
        )

        new_state =
          state
          |> cancel_init_timeout()
          |> Map.put(:init_request_id, nil)

        {:stop, {:initialize_timeout, request_id}, new_state}
    end
  end

  @impl true
  def handle_info({:callback_result, request_id, :hook, signal, result}, state) do
    {pending, updated_state} = pop_pending_callback(state, request_id)

    cond do
      AbortSignal.cancelled?(signal) ->
        {:noreply, updated_state}

      pending == nil ->
        {:noreply, updated_state}

      true ->
        case result do
          {:ok, output} ->
            GenServer.reply(pending.from, {:ok, {:hook_success, output}})
            Logger.debug("Sent hook callback response", request_id: request_id)

          {:error, reason} ->
            GenServer.reply(pending.from, {:error, reason})
            Logger.error("Hook callback failed", request_id: request_id, reason: reason)
        end

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info(
        {:callback_result, request_id, :permission, signal, original_input, result},
        state
      ) do
    {pending, updated_state} = pop_pending_callback(state, request_id)

    cond do
      AbortSignal.cancelled?(signal) ->
        {:noreply, updated_state}

      pending == nil ->
        {:noreply, updated_state}

      true ->
        case result do
          {:ok, permission_result} ->
            GenServer.reply(
              pending.from,
              {:ok,
               {:permission_response, permission_result.behavior, permission_result,
                original_input}}
            )

            Logger.debug("Sent permission response",
              request_id: request_id,
              behavior: permission_result.behavior
            )

          {:error, reason} ->
            GenServer.reply(pending.from, {:error, reason})
            Logger.error("Permission callback failed", request_id: request_id, reason: reason)
        end

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:protocol_notification, {:control_cancel_request, data}}, state) do
    {:noreply, handle_control_cancel_request(data, state)}
  end

  def handle_info({:protocol_notification, {:stream_event, data}}, state) do
    {:noreply, handle_decoded_message(:stream_event, data, state)}
  end

  def handle_info({:protocol_notification, {:sdk_message, data}}, state) do
    {:noreply, handle_decoded_message(:sdk_message, data, state)}
  end

  def handle_info({:protocol_error, reason}, state) do
    {:noreply, handle_protocol_error(reason, state)}
  end

  def handle_info({:protocol_stderr, data}, state) do
    {:noreply, handle_transport_stderr(data, state)}
  end

  def handle_info({task_ref, result}, state) when is_reference(task_ref) do
    case pop_pending_request_by_task_ref(state, task_ref) do
      {nil, next_state} ->
        {:noreply, next_state}

      {request_id, pending_entry, next_state} ->
        handle_pending_request_result(request_id, pending_entry, result, next_state)
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    if ref == state.protocol_session_monitor_ref do
      handle_protocol_session_down(reason, state)
    else
      handle_non_session_down(ref, reason, state)
    end
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("Ignoring unexpected client mailbox message",
      payload_preview: inspect(message, pretty: true, limit: 20)
    )

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    _state =
      state
      |> flush_transport_stderr()
      |> cancel_init_timeout()
      |> cancel_pending_callbacks()

    if is_pid(state.protocol_session) do
      _ = ProtocolSession.close(state.protocol_session)
    end

    Logger.debug("Terminating client", reason: reason)

    :ok
  end

  ## Private Functions - Initialization

  defp validate_hooks(nil), do: :ok
  defp validate_hooks(hooks), do: Hooks.validate_config(hooks)

  defp validate_runtime_overrides(opts) when is_list(opts) do
    case Enum.find(
           [:transport, :transport_opts, :transport_api, :transport_spec],
           &Keyword.has_key?(opts, &1)
         ) do
      nil ->
        :ok

      key ->
        {:error,
         {:unsupported_runtime_override, key,
          "custom transport injection has been removed; use execution_surface instead"}}
    end
  end

  defp validate_permission_callback(nil), do: :ok

  defp validate_permission_callback(callback) do
    ClaudeAgentSDK.Permission.validate_callback(callback)
  end

  defp validate_transport_error_mode(nil), do: :ok
  defp validate_transport_error_mode(mode) when mode in [:result, :raise], do: :ok
  defp validate_transport_error_mode(_mode), do: {:error, :invalid_transport_error_mode}

  defp maybe_override_execution_surface(%Options{} = options, nil), do: {:ok, options}

  defp maybe_override_execution_surface(%Options{} = options, execution_surface) do
    {:ok, %{options | execution_surface: execution_surface}}
  end

  # Apply agent settings to options
  defp apply_agent_settings(%Options{agent: nil} = options), do: {:ok, options}

  defp apply_agent_settings(%Options{agent: agent_name, agents: agents} = options)
       when is_map(agents) and is_atom(agent_name) do
    case Map.get(agents, agent_name) do
      nil ->
        {:error, {:agent_not_found, agent_name}}

      agent ->
        # Validate the agent
        case ClaudeAgentSDK.Agent.validate(agent) do
          :ok ->
            updated_options =
              options
              |> maybe_replace_agent_model(agent.model)
              |> Map.put(:system_prompt, agent.prompt)
              |> Map.put(:allowed_tools, agent.allowed_tools)

            {:ok, updated_options}

          {:error, reason} ->
            {:error, {:invalid_agent, agent_name, reason}}
        end
    end
  end

  defp apply_agent_settings(options), do: {:ok, options}

  defp maybe_replace_agent_model(%Options{} = options, model) when is_binary(model) do
    Options.replace_model(options, model)
  end

  defp maybe_replace_agent_model(%Options{} = options, _model), do: options

  defp apply_permission_mode(%Options{permission_mode: nil} = options), do: {:ok, options}

  defp apply_permission_mode(%Options{permission_mode: mode} = options) do
    if ClaudeAgentSDK.Permission.valid_mode?(mode) do
      {:ok, options}
    else
      {:error, {:invalid_permission_mode, mode}}
    end
  end

  defp apply_permission_streaming(%Options{can_use_tool: nil} = options), do: {:ok, options}

  defp apply_permission_streaming(%Options{include_partial_messages: nil} = options) do
    {:ok, %{options | include_partial_messages: true}}
  end

  defp apply_permission_streaming(options), do: {:ok, options}

  defp apply_permission_prompt_tool(%Options{can_use_tool: nil} = options), do: {:ok, options}

  defp apply_permission_prompt_tool(
         %Options{can_use_tool: _callback, permission_prompt_tool: nil} = options
       ) do
    {:ok, %{options | permission_prompt_tool: "stdio"}}
  end

  defp apply_permission_prompt_tool(%Options{can_use_tool: _callback}),
    do: {:error, :permission_prompt_tool_conflict}

  defp apply_permission_prompt_tool(options), do: {:ok, options}

  defp stream_buffer_limit(%Options{stream_buffer_limit: limit})
       when is_integer(limit) and limit >= 0 do
    limit
  end

  defp stream_buffer_limit(_options), do: Buffers.stream_buffer_limit()

  defp stream_timeout_ms(%Options{timeout_ms: timeout_ms})
       when is_integer(timeout_ms) and timeout_ms > 0 do
    timeout_ms
  end

  defp stream_timeout_ms(_options), do: Timeouts.streaming_session_ms()

  defp maybe_attach_permission_hook(%Options{can_use_tool: nil} = options) do
    {:ok, options, nil}
  end

  defp maybe_attach_permission_hook(%Options{can_use_tool: callback} = options) do
    bridge = init_permission_bridge(options.permission_mode)
    hook = permission_hook(callback, bridge)
    hooks = attach_permission_hook(options.hooks, hook)
    {:ok, %{options | hooks: hooks}, bridge}
  end

  defp init_permission_bridge(permission_mode) do
    bridge = :ets.new(:permission_hook_state, [:set, :protected])
    :ets.insert(bridge, {:can_use_tool_seen, false})
    :ets.insert(bridge, {:permission_mode, permission_mode})
    bridge
  end

  defp attach_permission_hook(nil, hook) do
    matcher = Matcher.new("*", [hook])
    %{pre_tool_use: [matcher]}
  end

  defp attach_permission_hook(%{} = hooks, hook) do
    matcher = Matcher.new("*", [hook])

    updated_matchers =
      case Map.get(hooks, :pre_tool_use) do
        nil -> [matcher]
        matchers when is_list(matchers) -> [matcher | matchers]
      end

    Map.put(hooks, :pre_tool_use, updated_matchers)
  end

  defp permission_hook(callback, bridge) when is_function(callback, 1) do
    fn input, _tool_use_id, context ->
      tool_name = Map.get(input, "tool_name") || Map.get(input, :tool_name) || "unknown"
      tool_input = Map.get(input, "tool_input") || Map.get(input, :tool_input) || %{}
      session_id = Map.get(input, "session_id") || "unknown"
      mode = permission_bridge_get(bridge, :permission_mode, nil)

      cond do
        permission_bridge_get(bridge, :can_use_tool_seen, false) ->
          Output.allow("Permission handled by can_use_tool")

        permission_hook_skip_callback?(mode, tool_name) ->
          Output.allow("Auto-approved by permission mode")

        true ->
          signal = Map.get(context, :signal)

          result =
            execute_permission_callback(
              callback,
              %{
                tool_name: tool_name,
                tool_input: tool_input,
                suggestions: [],
                blocked_path: nil,
                session_id: session_id,
                tool_use_id: nil,
                agent_id: nil
              },
              signal
            )

          permission_result_to_hook_output(result, tool_name)
      end
    end
  end

  defp permission_hook_skip_callback?(:bypass_permissions, _tool_name), do: true

  defp permission_hook_skip_callback?(:dont_ask, _tool_name), do: true

  defp permission_hook_skip_callback?(:accept_edits, tool_name)
       when tool_name in @edit_tools,
       do: true

  defp permission_hook_skip_callback?(_mode, _tool_name), do: false

  defp permission_result_to_hook_output({:ok, %Result{} = result}, tool_name) do
    if is_list(result.updated_permissions) and result.updated_permissions != [] do
      Logger.warning("Permission updates ignored when using hook-based callbacks",
        tool: tool_name
      )
    end

    case result.behavior do
      :allow ->
        output = Output.allow("Approved")

        if is_map(result.updated_input) do
          Output.with_updated_input(output, result.updated_input)
        else
          output
        end

      :deny ->
        reason = result.message || "Denied"
        output = Output.deny(reason)

        if result.interrupt do
          Map.merge(output, Output.stop(reason))
        else
          output
        end
    end
  end

  defp permission_result_to_hook_output({:error, reason}, tool_name) do
    Logger.error("Permission callback failed during hook handling",
      tool: tool_name,
      reason: inspect(reason)
    )

    Output.deny("Permission callback failed")
  end

  defp permission_bridge_get(nil, _key, default), do: default

  defp permission_bridge_get(bridge, key, default) do
    case :ets.lookup(bridge, key) do
      [{^key, value}] -> value
      _ -> default
    end
  rescue
    ArgumentError -> default
  end

  defp permission_bridge_put(nil, _key, _value), do: :ok

  defp permission_bridge_put(bridge, key, value) do
    :ets.insert(bridge, {key, value})
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp apply_client_entrypoint_env(%Options{} = options) do
    env = options.env || %{}

    entrypoint_key = Env.entrypoint()
    entrypoint_atom = env_atom_key(entrypoint_key)

    env =
      if Map.has_key?(env, entrypoint_key) or
           map_has_optional_key?(env, entrypoint_atom) do
        env
      else
        Map.put(env, entrypoint_key, "sdk-elixir-client")
      end

    %{options | env: env}
  end

  defp env_atom_key("CLAUDE_CODE_ENTRYPOINT"), do: :CLAUDE_CODE_ENTRYPOINT
  defp env_atom_key(_key), do: nil

  defp map_has_optional_key?(_map, nil), do: false
  defp map_has_optional_key?(map, key), do: Map.has_key?(map, key)

  @doc false
  @spec init_timeout_seconds_from_env() :: number()
  def init_timeout_seconds_from_env do
    env_value = System.get_env(Env.stream_close_timeout())

    parsed_ms =
      case env_value do
        value when is_binary(value) ->
          case Integer.parse(value) do
            {int, _} when int > 0 -> int
            _ -> Timeouts.client_init_ms()
          end

        _ ->
          Timeouts.client_init_ms()
      end

    timeout_ms = max(parsed_ms, Timeouts.client_init_ms())
    timeout_ms / 1_000
  end

  defp schedule_initialize_timeout(request_id) when is_binary(request_id) do
    timeout_ms =
      init_timeout_seconds_from_env()
      |> Kernel.*(1_000)
      |> trunc()

    ref = Process.send_after(self(), {:initialize_timeout, request_id}, timeout_ms)
    {ref, timeout_ms}
  end

  defp maybe_cancel_init_timeout(state, request_id) do
    if state.init_request_id == request_id and state.init_timeout != nil do
      _ = Process.cancel_timer(elem(state.init_timeout, 0))
      %{state | init_timeout: nil, init_request_id: nil}
    else
      state
    end
  end

  defp control_request_timeout_ms_from_config do
    case Application.get_env(
           :claude_agent_sdk,
           :control_request_timeout_ms,
           Timeouts.client_control_request_ms()
         ) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 ->
        timeout_ms

      _ ->
        Timeouts.client_control_request_ms()
    end
  end

  defp resolve_control_request_timeout_ms(opts) do
    case Keyword.get(opts, :control_request_timeout_ms) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 ->
        timeout_ms

      _ ->
        control_request_timeout_ms_from_config()
    end
  end

  defp fail_pending_control_requests(state, reason) do
    Enum.each(state.pending_requests, fn {_request_id, pending_entry} ->
      case pending_entry do
        {:set_model, from, _requested_model, _task_ref} ->
          GenServer.reply(from, {:error, reason})

        {:set_permission_mode, from, _requested_mode, _task_ref} ->
          GenServer.reply(from, {:error, reason})

        {:interrupt, from, _task_ref} ->
          GenServer.reply(from, {:error, reason})

        {:rewind_files, from, _task_ref} ->
          GenServer.reply(from, {:error, reason})

        {:mcp_status, from, _task_ref} ->
          GenServer.reply(from, {:error, reason})

        _ ->
          :ok
      end
    end)

    %{
      state
      | pending_requests: %{},
        pending_permission_change: nil
    }
  end

  defp notify_init_sent_waiters(%{init_waiters: []} = state), do: state

  defp notify_init_sent_waiters(%{init_request_id: request_id, init_waiters: waiters} = state)
       when is_binary(request_id) do
    Enum.each(waiters, fn from -> GenServer.reply(from, {:ok, request_id}) end)
    %{state | init_waiters: []}
  end

  defp notify_init_sent_waiters(state), do: state

  defp notify_initialized_waiters(%{initialized_waiters: []} = state), do: state

  defp notify_initialized_waiters(state) do
    Enum.each(state.initialized_waiters, &GenServer.reply(&1, :ok))
    %{state | initialized_waiters: []}
  end

  defp cancel_init_timeout(%{init_timeout: {ref, _ms}} = state) when is_reference(ref) do
    _ = Process.cancel_timer(ref)
    %{state | init_timeout: nil}
  end

  defp cancel_init_timeout(state), do: state

  defp enqueue_pending_outbound(%{pending_outbound: pending_outbound} = state, payload)
       when is_binary(payload) do
    %{state | pending_outbound: :queue.in(payload, pending_outbound)}
  end

  defp flush_pending_outbound(%{pending_outbound: pending_outbound} = state) do
    case :queue.out(pending_outbound) do
      {:empty, _queue} ->
        state

      {{:value, payload}, rest} ->
        next_state = %{state | pending_outbound: rest}

        case send_payload(next_state, payload) do
          :ok ->
            flush_pending_outbound(next_state)

          {:error, reason} ->
            Logger.error("Failed to flush buffered outbound payload", reason: inspect(reason))
            %{next_state | pending_outbound: :queue.in_r(payload, rest)}
        end
    end
  end

  defp start_cli_process(state) do
    owner = self()
    registry = register_hooks(state.registry, state.options.hooks)
    hook_callback_timeouts = build_hook_timeout_map(registry, state.options.hooks)
    hooks_config = build_hooks_config(registry, state.options.hooks)
    sdk_mcp_info = build_sdk_mcp_info(state.sdk_mcp_servers, state.options.mcp_servers)
    agents_for_init = Options.agents_for_initialize(state.options.agents)
    initialize_options = Options.initialize_options(state.options)

    peer_request_handler =
      build_peer_request_handler(
        owner,
        registry,
        hook_callback_timeouts,
        state.options,
        state.permission_bridge,
        state.sdk_mcp_servers
      )

    with {:ok, invocation} <- RuntimeCLI.build_invocation(options: state.options),
         {:ok, session} <-
           ProtocolSession.start(
             build_protocol_session_options(
               owner,
               invocation,
               state.options,
               peer_request_handler
             )
           ),
         :ok <- ProtocolSession.await_ready(session, Timeouts.client_init_ms()) do
      monitor_ref = Process.monitor(session)

      state = %{
        state
        | protocol_session: session,
          protocol_session_monitor_ref: monitor_ref,
          registry: registry,
          hook_callback_timeouts: hook_callback_timeouts,
          initialized: false
      }

      start_initialize_task(
        state,
        hooks_config,
        sdk_mcp_info,
        agents_for_init,
        initialize_options
      )
    else
      {:error, reason} ->
        {:error, {:protocol_session_failed, reason}}
    end
  end

  defp build_protocol_session_options(owner, invocation, options, peer_request_handler) do
    [
      adapter: Adapter,
      command: invocation,
      ready_mode: :immediate,
      notification_handler: fn notification ->
        send(owner, {:protocol_notification, notification})
      end,
      protocol_error_handler: fn reason ->
        send(owner, {:protocol_error, reason})
      end,
      stderr_handler: fn chunk ->
        send(owner, {:protocol_stderr, IO.iodata_to_binary(chunk)})
      end,
      peer_request_handler: peer_request_handler
    ] ++ Options.execution_surface_options(options)
  end

  defp build_peer_request_handler(
         owner,
         _registry,
         _hook_callback_timeouts,
         options,
         _permission_bridge,
         sdk_mcp_servers
       ) do
    sdk_mcp_info = build_sdk_mcp_info(sdk_mcp_servers, options.mcp_servers) || %{}

    fn request ->
      case Map.get(request, "subtype") do
        subtype when subtype in ["hook_callback", "can_use_tool"] ->
          GenServer.call(owner, {:peer_request, request}, :infinity)

        subtype when subtype in ["sdk_mcp_request", "mcp_message"] ->
          handle_sdk_mcp_peer_request(request, sdk_mcp_servers, sdk_mcp_info)

        other ->
          {:error, "Unsupported request: #{other}"}
      end
    end
  end

  defp start_initialize_task(
         state,
         hooks_config,
         sdk_mcp_info,
         agents_for_init,
         initialize_options
       ) do
    {init_request_id, init_json} =
      Protocol.encode_initialize_request(
        hooks_config,
        sdk_mcp_info,
        nil,
        agents_for_init,
        initialize_options
      )

    init_timeout = schedule_initialize_timeout(init_request_id)
    init_timeout_ms = elem(init_timeout, 1)

    case start_request_task(
           state,
           init_request_id,
           fn task_ref -> {:initialize, task_ref} end,
           fn ->
             ProtocolSession.request(
               state.protocol_session,
               %{request_id: init_request_id, frame: init_json},
               timeout_ms: init_timeout_ms
             )
           end
         ) do
      {:ok, state} ->
        {:ok, %{state | init_request_id: init_request_id, init_timeout: init_timeout}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_request_task(state, request_id, build_pending_entry, fun)
       when is_binary(request_id) and is_function(build_pending_entry, 1) and is_function(fun, 0) do
    case TaskSupport.async_nolink(fun) do
      {:ok, %Task{} = task} ->
        pending_requests =
          Map.put(state.pending_requests, request_id, build_pending_entry.(task.ref))

        {:ok, %{state | pending_requests: pending_requests}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_protocol_request_task(
         state,
         request_id,
         json,
         build_pending_entry,
         on_success
       )
       when is_binary(request_id) and is_binary(json) and is_function(build_pending_entry, 1) and
              is_function(on_success, 1) do
    case start_request_task(
           state,
           request_id,
           build_pending_entry,
           fn ->
             ProtocolSession.request(
               state.protocol_session,
               %{request_id: request_id, frame: json},
               timeout_ms: state.control_request_timeout_ms
             )
           end
         ) do
      {:ok, next_state} ->
        on_success.(next_state)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp pop_pending_request_by_task_ref(state, task_ref) when is_reference(task_ref) do
    Enum.reduce_while(state.pending_requests, {nil, state}, fn {request_id, pending_entry},
                                                               _acc ->
      if pending_request_task_ref(pending_entry) == task_ref do
        next_state = %{state | pending_requests: Map.delete(state.pending_requests, request_id)}
        {:halt, {request_id, pending_entry, next_state}}
      else
        {:cont, {nil, state}}
      end
    end)
  end

  defp pending_request_task_ref({:initialize, task_ref}) when is_reference(task_ref), do: task_ref

  defp pending_request_task_ref({_kind, _from, task_ref}) when is_reference(task_ref),
    do: task_ref

  defp pending_request_task_ref({_kind, _from, _requested, task_ref}) when is_reference(task_ref),
    do: task_ref

  defp pending_request_task_ref(_other), do: nil

  defp handle_pending_request_result(request_id, pending_entry, result, state) do
    case dispatch_request_result(request_id, pending_entry, result, state) do
      {:stop, reason, next_state} -> {:stop, reason, next_state}
      next_state -> {:noreply, next_state}
    end
  end

  defp dispatch_request_result(request_id, {:initialize, _task_ref}, result, state) do
    state = maybe_cancel_init_timeout(state, request_id)

    case result do
      {:ok, response} ->
        handle_initialize_response(response, request_id, state)

      {:error, reason} ->
        Logger.error("Initialize request failed", request_id: request_id, reason: inspect(reason))
        {:stop, {:initialize_failed, reason}, state}
    end
  end

  defp dispatch_request_result(request_id, pending_entry, {:ok, response}, state) do
    response_data = %{"response" => response}
    dispatch_control_response(pending_entry, response_data, response, request_id, state)
  end

  defp dispatch_request_result(request_id, pending_entry, {:error, reason}, state) do
    dispatch_control_request_failure(pending_entry, reason, request_id, state)
  end

  defp handle_initialize_response(response, request_id, state) do
    case response["subtype"] do
      "success" ->
        handle_untracked_control_response(response, request_id, state)

      "error" ->
        error = response["error"] || "initialize_failed"

        Logger.error("Initialize response rejected",
          request_id: request_id,
          error: error
        )

        {:stop, {:initialize_failed, error}, state}

      other ->
        Logger.warning("Unexpected initialize response subtype",
          request_id: request_id,
          subtype: other
        )

        {:stop, {:initialize_failed, {:unexpected_subtype, other}}, state}
    end
  end

  defp dispatch_control_request_failure(
         {:set_model, from, _requested_model, _task_ref},
         reason,
         request_id,
         state
       ) do
    Logger.error("Model change request failed", request_id: request_id, error: inspect(reason))
    GenServer.reply(from, {:error, reason})
    state
  end

  defp dispatch_control_request_failure(
         {:set_permission_mode, from, _requested_mode, _task_ref},
         reason,
         request_id,
         state
       ) do
    Logger.error("Permission mode change rejected",
      request_id: request_id,
      error: inspect(reason)
    )

    GenServer.reply(from, {:error, reason})
    %{state | pending_permission_change: nil}
  end

  defp dispatch_control_request_failure(
         {action, from, _task_ref},
         reason,
         request_id,
         state
       )
       when action in [:interrupt, :rewind_files] do
    Logger.error("#{action} request failed", request_id: request_id, error: inspect(reason))
    GenServer.reply(from, {:error, reason})
    state
  end

  defp dispatch_control_request_failure(
         {:mcp_status, from, _task_ref},
         reason,
         request_id,
         state
       ) do
    Logger.error("mcp_status request failed", request_id: request_id, error: inspect(reason))
    GenServer.reply(from, {:error, reason})
    state
  end

  defp dispatch_control_request_failure(nil, _reason, _request_id, state), do: state

  defp handle_non_session_down(ref, reason, state) do
    case find_subscriber_ref_by_monitor(state, ref) do
      nil ->
        handle_non_subscriber_down(ref, reason, state)

      subscriber_ref ->
        {:noreply, drop_subscriber(state, subscriber_ref, skip_demonitor: true)}
    end
  end

  defp handle_non_subscriber_down(ref, reason, state) do
    case find_callback_by_monitor_ref(state.pending_callbacks, ref) do
      nil ->
        handle_pending_request_down(ref, reason, state)

      {_request_id, _entry} when reason == :normal ->
        {:noreply, state}

      {request_id, entry} ->
        handle_callback_down(state, request_id, entry, reason)
    end
  end

  defp handle_pending_request_down(ref, reason, state) do
    case pop_pending_request_by_task_ref(state, ref) do
      {nil, next_state} ->
        {:noreply, next_state}

      {request_id, pending_entry, next_state} ->
        handle_pending_request_result(
          request_id,
          pending_entry,
          {:error, {:task_exit, reason}},
          next_state
        )
    end
  end

  defp handle_protocol_session_down(reason, state) do
    Logger.info("Protocol session terminated", reason: inspect(reason))

    next_state =
      state
      |> flush_transport_stderr()
      |> cancel_pending_callbacks()
      |> fail_pending_control_requests({:protocol_session_down, reason})
      |> cancel_init_timeout()
      |> Map.put(:protocol_session, nil)
      |> Map.put(:protocol_session_monitor_ref, nil)

    {:stop, :normal, next_state}
  end

  defp handle_protocol_error(reason, state) do
    error =
      %ClaudeAgentSDK.Errors.CLIJSONDecodeError{
        message: "Failed to decode protocol message: #{inspect(reason)}",
        line: inspect(reason, limit: 20),
        original_error: reason
      }

    if transport_error_mode?(state, :raise) do
      broadcast_transport_error(state, error)
      fail_pending_control_requests(state, {:decode_error, error})
    else
      Logger.warning("Failed to decode protocol message", reason: inspect(reason))
      state
    end
  end

  defp register_hooks(registry, nil), do: registry

  defp register_hooks(registry, hooks) when is_map(hooks) do
    hooks
    |> Enum.flat_map(fn {_event, matchers} ->
      Enum.flat_map(matchers, & &1.hooks)
    end)
    |> Enum.reduce(registry, fn callback, reg -> Registry.register(reg, callback) end)
  end

  defp build_hook_timeout_map(_registry, nil), do: %{}

  defp build_hook_timeout_map(registry, hooks) do
    hooks
    |> Enum.flat_map(fn {_event, matchers} ->
      Enum.flat_map(matchers, &matcher_hook_timeouts(registry, &1))
    end)
    |> Enum.reduce(%{}, fn {callback_id, timeout_ms}, acc ->
      Map.update(acc, callback_id, timeout_ms, &max(&1, timeout_ms))
    end)
  end

  defp matcher_hook_timeouts(registry, matcher) do
    timeout_ms = matcher_timeout_ms(matcher)

    matcher.hooks
    |> Enum.map(&Registry.get_id(registry, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&{&1, timeout_ms})
  end

  defp matcher_timeout_ms(matcher) do
    matcher.timeout_ms
    |> Matcher.sanitize_timeout_ms()
    |> case do
      nil -> Timeouts.client_hook_ms()
      value -> value
    end
  end

  defp build_hooks_config(_registry, nil), do: nil

  defp build_hooks_config(registry, hooks) do
    hooks
    |> Enum.map(fn {event, matchers} ->
      event_str = Hooks.event_to_string(event)

      {event_str, matchers_to_cli(matchers, registry)}
    end)
    |> Map.new()
  end

  defp matchers_to_cli(matchers, registry) do
    Enum.map(matchers, fn matcher ->
      Matcher.to_cli_format(matcher, fn callback -> Registry.get_id(registry, callback) end)
    end)
  end

  ## Private Functions - Message Handling

  defp handle_decoded_message(:sdk_message, data, state) do
    # Regular SDK message, broadcast to subscribers
    broadcast_message(data, state)
  end

  defp handle_decoded_message(:stream_event, data, state) do
    # Streaming event (v0.6.0) - handle both wrapped and unwrapped formats
    # Real CLI: {"type": "stream_event", "uuid": "...", "session_id": "...",
    #            "event": {"type": "message_start", ...}, "parent_tool_use_id": "toolu_xxx"}
    # Tests: {"type": "message_start", ...}
    {event_data, metadata} =
      if data["type"] == "stream_event" do
        event = Map.get(data, "event", %{})
        uuid = Map.get(data, "uuid")
        session_id = Map.get(data, "session_id")

        metadata = %{
          parent_tool_use_id: data["parent_tool_use_id"],
          uuid: uuid,
          session_id: session_id
        }

        {event, metadata}
      else
        {data, %{parent_tool_use_id: nil, uuid: nil, session_id: nil}}
      end

    handle_stream_event(event_data, metadata, state)
  end

  defp handle_control_cancel_request(request_data, state) do
    request_id = request_data["request_id"]
    {pending, updated_state} = pop_pending_callback(state, request_id)

    case pending do
      nil ->
        Logger.debug("Cancel request for unknown callback", request_id: request_id)
        updated_state

      %{pid: pid, signal: signal, type: type, from: from} ->
        AbortSignal.cancel(signal)
        Process.exit(pid, :kill)
        GenServer.reply(from, {:error, cancellation_reason(type)})
        updated_state
    end
  end

  defp dispatch_control_response(
         {:set_model, from, requested_model, _timer_ref},
         response_data,
         response,
         request_id,
         state
       ) do
    handle_set_model_response(from, requested_model, response_data, response, request_id, state)
  end

  defp dispatch_control_response(
         {:set_permission_mode, from, requested_mode, _timer_ref},
         _response_data,
         response,
         request_id,
         state
       ) do
    handle_set_permission_mode_response(from, requested_mode, response, request_id, state)
  end

  defp dispatch_control_response(
         {:interrupt, from, _timer_ref},
         _response_data,
         response,
         request_id,
         state
       ) do
    handle_simple_control_response(:interrupt, from, response, request_id, state)
  end

  defp dispatch_control_response(
         {:rewind_files, from, _timer_ref},
         _response_data,
         response,
         request_id,
         state
       ) do
    handle_simple_control_response(:rewind_files, from, response, request_id, state)
  end

  defp dispatch_control_response(
         {:mcp_status, from, _timer_ref},
         _response_data,
         response,
         request_id,
         state
       ) do
    handle_mcp_status_response(from, response, request_id, state)
  end

  defp dispatch_control_response(
         {:get_context_usage, from, _timer_ref},
         _response_data,
         response,
         request_id,
         state
       ) do
    handle_context_usage_response(from, response, request_id, state)
  end

  defp dispatch_control_response(nil, _response_data, response, request_id, state) do
    handle_untracked_control_response(response, request_id, state)
  end

  defp handle_set_model_response(
         from,
         requested_model,
         response_data,
         response,
         request_id,
         state
       ) do
    case response["subtype"] do
      "success" ->
        handle_set_model_success(from, requested_model, response_data, request_id, state)

      "error" ->
        error = response["error"] || "set_model_failed"
        Logger.error("Model change rejected", request_id: request_id, error: error)
        GenServer.reply(from, {:error, error})
        state

      other ->
        Logger.warning("Unexpected subtype for set_model response",
          request_id: request_id,
          subtype: other
        )

        GenServer.reply(from, {:error, :unexpected_response})
        state
    end
  end

  defp handle_set_model_success(from, requested_model, response_data, request_id, state) do
    case Protocol.decode_set_model_response(response_data) do
      {:ok, model} ->
        Logger.info("Model changed successfully", request_id: request_id, model: model)
        GenServer.reply(from, :ok)

        state
        |> put_current_model(model)

      {:error, :invalid_response} when is_binary(requested_model) ->
        Logger.info(
          "Model change acknowledged without explicit model; using requested value",
          request_id: request_id,
          model: requested_model
        )

        GenServer.reply(from, :ok)

        state
        |> put_current_model(requested_model)

      {:error, reason} ->
        Logger.error(
          "Failed to decode set_model response: #{inspect(response_data)} (reason=#{inspect(reason)})",
          request_id: request_id
        )

        GenServer.reply(from, {:error, reason})
        state
    end
  end

  defp put_current_model(%{options: %Options{} = options} = state, model) when is_binary(model) do
    %{state | options: Options.replace_model(options, model)}
  end

  defp handle_set_permission_mode_response(from, requested_mode, response, request_id, state) do
    case response["subtype"] do
      "success" ->
        Logger.info("Permission mode changed successfully",
          request_id: request_id,
          mode: requested_mode
        )

        updated_options = %{state.options | permission_mode: requested_mode}
        GenServer.reply(from, :ok)

        permission_bridge_put(state.permission_bridge, :permission_mode, requested_mode)

        %{
          state
          | options: updated_options,
            pending_permission_change: nil
        }

      "error" ->
        error = response["error"] || "set_permission_mode_failed"
        Logger.error("Permission mode change rejected", request_id: request_id, error: error)
        GenServer.reply(from, {:error, error})
        %{state | pending_permission_change: nil}

      other ->
        Logger.warning("Unexpected subtype for set_permission_mode response",
          request_id: request_id,
          subtype: other
        )

        GenServer.reply(from, {:error, :unexpected_response})
        %{state | pending_permission_change: nil}
    end
  end

  defp handle_simple_control_response(action, from, response, request_id, state) do
    case response["subtype"] do
      "success" ->
        Logger.info("#{action} acknowledged", request_id: request_id)
        GenServer.reply(from, :ok)
        state

      "error" ->
        error = response["error"] || "#{action}_failed"
        Logger.error("#{action} rejected", request_id: request_id, error: error)
        GenServer.reply(from, {:error, error})
        state

      other ->
        Logger.warning("Unexpected subtype for #{action} response",
          request_id: request_id,
          subtype: other
        )

        GenServer.reply(from, {:error, :unexpected_response})
        state
    end
  end

  defp handle_mcp_status_response(from, response, request_id, state) do
    case response["subtype"] do
      "success" ->
        status = response["response"] || %{}
        Logger.info("mcp_status acknowledged", request_id: request_id)
        GenServer.reply(from, {:ok, status})
        state

      "error" ->
        error = response["error"] || "mcp_status_failed"
        Logger.error("mcp_status rejected", request_id: request_id, error: error)
        GenServer.reply(from, {:error, error})
        state

      other ->
        Logger.warning("Unexpected subtype for mcp_status response",
          request_id: request_id,
          subtype: other
        )

        GenServer.reply(from, {:error, :unexpected_response})
        state
    end
  end

  defp handle_context_usage_response(from, response, request_id, state) do
    case response["subtype"] do
      "success" ->
        usage = response["response"] || %{}
        Logger.info("get_context_usage acknowledged", request_id: request_id)
        GenServer.reply(from, {:ok, usage})
        state

      "error" ->
        error = response["error"] || "get_context_usage_failed"
        Logger.error("get_context_usage rejected", request_id: request_id, error: error)
        GenServer.reply(from, {:error, error})
        state

      other ->
        Logger.warning("Unexpected subtype for get_context_usage response",
          request_id: request_id,
          subtype: other
        )

        GenServer.reply(from, {:error, :unexpected_response})
        state
    end
  end

  defp handle_untracked_control_response(response, request_id, state) do
    case response["subtype"] do
      "success" ->
        Logger.debug("Received successful control response", request_id: request_id)

        state_with_info = maybe_store_server_info(state, response)

        if state_with_info.initialized do
          state_with_info
        else
          Logger.info("Client initialized successfully")

          state_with_info
          |> Map.put(:initialized, true)
          |> flush_pending_outbound()
          |> notify_initialized_waiters()
        end

      "error" ->
        error = response["error"]
        Logger.error("Control response error", request_id: request_id, error: error)
        state

      other ->
        Logger.warning("Unknown control response subtype", subtype: other)
        state
    end
  end

  defp handle_hook_callback(request, from, state) do
    request_id = request["request_id"]
    callback_id = request["callback_id"]
    input = request["input"]
    tool_use_id = request["tool_use_id"]

    Logger.debug("Hook callback requested",
      request_id: request_id,
      callback_id: callback_id,
      tool: input["tool_name"]
    )

    # Look up callback in registry
    case Registry.get_callback(state.registry, callback_id) do
      {:ok, callback_fn} ->
        timeout_ms = hook_timeout_ms(state, callback_id)

        {:noreply,
         start_hook_callback_task(
           state,
           request_id,
           from,
           callback_fn,
           input,
           tool_use_id,
           timeout_ms
         )}

      :error ->
        error_msg = "Callback not found: #{callback_id}"
        Logger.error("Hook callback not found", callback_id: callback_id)
        {:reply, {:error, error_msg}, state}
    end
  end

  defp hook_timeout_ms(state, callback_id) do
    state
    |> Map.get(:hook_callback_timeouts, %{})
    |> Map.get(callback_id, Timeouts.client_hook_ms())
  end

  defp hook_timeout_error_message(timeout_ms) do
    "Hook callback timeout after #{format_timeout_ms(timeout_ms)}"
  end

  defp format_timeout_ms(timeout_ms) when is_integer(timeout_ms) do
    cond do
      timeout_ms >= 1_000 and rem(timeout_ms, 1_000) == 0 ->
        "#{div(timeout_ms, 1_000)}s"

      timeout_ms >= 1_000 ->
        seconds = timeout_ms / 1_000
        "#{Float.round(seconds, 1)}s"

      true ->
        "#{timeout_ms}ms"
    end
  end

  defp handle_can_use_tool_request(request, from, state) do
    request_id = request["request_id"]
    tool_name = request["tool_name"]
    tool_input = request["input"]
    suggestions = request["permission_suggestions"] || []
    blocked_path = request["blocked_path"]
    tool_use_id = request["tool_use_id"]
    agent_id = request["agent_id"]
    session_id = state.session_id || "unknown"

    Logger.debug("Permission request for tool",
      request_id: request_id,
      tool: tool_name
    )

    permission_bridge_put(state.permission_bridge, :can_use_tool_seen, true)

    # Check if we have a permission callback
    case state.options.can_use_tool do
      nil ->
        Logger.debug("No permission callback, allowing tool", tool: tool_name)
        {:reply, {:ok, {:permission_response, :allow, nil, tool_input}}, state}

      callback when is_function(callback, 1) ->
        permission_request = %{
          tool_name: tool_name,
          tool_input: tool_input,
          suggestions: suggestions,
          blocked_path: blocked_path,
          tool_use_id: tool_use_id,
          agent_id: agent_id,
          session_id: session_id
        }

        {:noreply,
         start_permission_callback_task(state, request_id, from, callback, permission_request)}
    end
  end

  defp start_hook_callback_task(
         state,
         request_id,
         from,
         callback_fn,
         input,
         tool_use_id,
         timeout_ms
       ) do
    start_callback_task(state, request_id, :hook, from, fn signal, server ->
      result =
        execute_hook_callback(callback_fn, input, tool_use_id, signal, timeout_ms)

      send(server, {:callback_result, request_id, :hook, signal, result})
    end)
  end

  defp start_permission_callback_task(state, request_id, from, callback, permission_request) do
    start_callback_task(state, request_id, :permission, from, fn signal, server ->
      result =
        execute_permission_callback(
          callback,
          permission_request,
          signal
        )

      send(
        server,
        {:callback_result, request_id, :permission, signal, permission_request.tool_input, result}
      )
    end)
  end

  defp start_callback_task(state, request_id, type, from, callback_runner)
       when is_function(callback_runner, 2) do
    signal = AbortSignal.new()
    server = self()

    case TaskSupervisor.start_child(fn -> callback_runner.(signal, server) end) do
      {:ok, pid} ->
        monitor_ref = Process.monitor(pid)
        put_pending_callback(state, request_id, pid, monitor_ref, signal, type, from)

      {:error, reason} ->
        Logger.error("Failed to start callback task",
          request_id: request_id,
          type: type,
          reason: inspect(reason)
        )

        GenServer.reply(from, {:error, callback_start_error_message(reason)})
        state
    end
  end

  defp execute_hook_callback(callback_fn, input, tool_use_id, signal, timeout_ms) do
    task =
      Task.async(fn ->
        try do
          context = %{signal: signal}
          result = callback_fn.(input, tool_use_id, context)

          if is_map(result) do
            {:ok, Output.to_json_map(result)}
          else
            {:error, "Hook must return a map"}
          end
        rescue
          e ->
            {:error, "Hook exception: #{Exception.message(e)}"}
        catch
          :exit, reason ->
            {:error, "Hook exit: #{format_exit_reason(reason)}"}

          :throw, reason ->
            {:error, "Hook throw: #{inspect(reason, limit: 10, printable_limit: 200)}"}
        end
      end)

    case Task.yield(task, timeout_ms) do
      {:ok, {:ok, output}} ->
        {:ok, output}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, hook_timeout_error_message(timeout_ms)}

      {:exit, _} ->
        {:error, hook_timeout_error_message(timeout_ms)}
    end
  end

  defp execute_permission_callback(callback, permission_request, signal) do
    task =
      Task.async(fn ->
        try do
          context =
            Context.new(
              tool_name: permission_value(permission_request, :tool_name),
              tool_input: permission_value(permission_request, :tool_input),
              session_id: permission_value(permission_request, :session_id),
              suggestions: permission_value(permission_request, :suggestions),
              blocked_path: permission_value(permission_request, :blocked_path),
              tool_use_id: permission_value(permission_request, :tool_use_id),
              agent_id: permission_value(permission_request, :agent_id),
              signal: signal
            )

          result = callback.(context)

          case Result.validate(result) do
            :ok -> {:ok, result}
            {:error, reason} -> {:error, "Invalid result: #{reason}"}
          end
        rescue
          e ->
            {:error, "Permission callback exception: #{Exception.message(e)}"}
        catch
          :exit, reason ->
            {:error, "Permission callback exit: #{format_exit_reason(reason)}"}

          :throw, reason ->
            {:error,
             "Permission callback throw: #{inspect(reason, limit: 10, printable_limit: 200)}"}
        end
      end)

    timeout = Timeouts.client_permission_yield_ms()

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, permission_result}} ->
        {:ok, permission_result}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, "Permission callback timeout after #{div(timeout, 1_000)}s"}

      {:exit, reason} ->
        {:error, "Permission callback failed: #{inspect(reason)}"}
    end
  end

  defp permission_value(permission_request, key) when is_map(permission_request) do
    Map.get(permission_request, key) || Map.get(permission_request, Atom.to_string(key))
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

    state =
      if skip_demonitor? do
        %{state | subscriber_monitors: Map.delete(state.subscriber_monitors, ref)}
      else
        remove_subscriber_monitor(state, ref)
      end

    subscribers = Map.delete(state.subscribers, ref)
    queue = Enum.reject(state.subscriber_queue, fn {queue_ref, _msg} -> queue_ref == ref end)

    {new_active, new_queue} =
      if state.active_subscriber == ref do
        case queue do
          [{next_ref, next_message} | rest] ->
            json = encode_outgoing_message(next_message)
            _ = send_payload(state, json)
            {next_ref, rest}

          [] ->
            {nil, []}
        end
      else
        {state.active_subscriber, queue}
      end

    %{
      state
      | subscribers: subscribers,
        subscriber_queue: new_queue,
        active_subscriber: new_active
    }
  end

  defp find_subscriber_ref_by_monitor(state, monitor_ref) when is_reference(monitor_ref) do
    Enum.find_value(state.subscriber_monitors, fn {subscriber_ref, ref} ->
      if ref == monitor_ref, do: subscriber_ref
    end)
  end

  defp put_pending_callback(state, request_id, pid, monitor_ref, signal, type, from) do
    pending =
      Map.put(state.pending_callbacks, request_id, %{
        pid: pid,
        monitor_ref: monitor_ref,
        signal: signal,
        type: type,
        from: from
      })

    %{state | pending_callbacks: pending}
  end

  defp pop_pending_callback(state, request_id) do
    {entry, pending} = Map.pop(state.pending_callbacks, request_id)

    # Demonitor the callback process if entry exists
    if entry != nil and Map.has_key?(entry, :monitor_ref) do
      Process.demonitor(entry.monitor_ref, [:flush])
    end

    {entry, %{state | pending_callbacks: pending}}
  end

  defp drop_pending_callback(state, request_id) do
    %{state | pending_callbacks: Map.delete(state.pending_callbacks, request_id)}
  end

  defp cancel_pending_callbacks(state) do
    Enum.each(state.pending_callbacks, fn {_id, entry} ->
      AbortSignal.cancel(entry.signal)

      # Demonitor if we have a monitor ref
      if Map.has_key?(entry, :monitor_ref) do
        Process.demonitor(entry.monitor_ref, [:flush])
      end

      Process.exit(entry.pid, :kill)
    end)

    %{state | pending_callbacks: %{}}
  end

  defp find_callback_by_monitor_ref(pending_callbacks, ref) do
    Enum.find_value(pending_callbacks, fn {request_id, entry} ->
      if Map.get(entry, :monitor_ref) == ref do
        {request_id, entry}
      else
        nil
      end
    end)
  end

  defp handle_callback_down(state, request_id, entry, reason) do
    cond do
      AbortSignal.cancelled?(entry.signal) ->
        {:noreply, drop_pending_callback(state, request_id)}

      shutdown_reason?(reason) ->
        {:noreply, drop_pending_callback(state, request_id)}

      true ->
        handle_callback_crash(state, request_id, entry, reason)
    end
  end

  defp handle_callback_crash(state, request_id, entry, reason) do
    Logger.error("Callback task crashed",
      request_id: request_id,
      type: entry.type,
      reason: inspect(reason)
    )

    error_message = callback_crash_message(reason)
    GenServer.reply(entry.from, {:error, error_message})

    {:noreply, drop_pending_callback(state, request_id)}
  end

  defp shutdown_reason?(reason) do
    reason == :shutdown or match?({:shutdown, _}, reason)
  end

  defp callback_crash_message(reason) do
    "Callback crashed: #{format_exit_reason(reason)}"
  end

  defp callback_start_error_message({:task_supervisor_unavailable, supervisor}) do
    "Callback unavailable: task supervisor #{inspect(supervisor)} is not running"
  end

  defp format_exit_reason(reason) do
    reason
    |> Exception.format_exit()
    |> String.replace("\n", " ")
    |> String.trim()
    |> trim_message(300)
  end

  defp trim_message(message, max_len) when is_integer(max_len) and max_len > 0 do
    if byte_size(message) > max_len do
      binary_part(message, 0, max_len) <> "..."
    else
      message
    end
  end

  defp cancellation_reason(:hook), do: "Callback cancelled"
  defp cancellation_reason(:permission), do: "Permission callback cancelled"
  defp cancellation_reason(_type), do: "Request cancelled"

  defp broadcast_message(message_data, state) do
    # Parse into Message struct
    case Message.from_json(Jason.encode!(message_data)) do
      {:ok, message} ->
        deliver_or_buffer_message(message, state)

      {:error, reason} ->
        Logger.warning("Failed to parse SDK message", reason: reason)
        state
    end
  end

  defp deliver_or_buffer_message(message, state) do
    if map_size(state.subscribers) == 0 do
      buffer_inbound(state, [{:claude_message, message}])
    else
      Enum.each(state.subscribers, fn {_ref, pid} ->
        send(pid, {:claude_message, message})
      end)

      state
    end
  end

  defp buffer_inbound(%{stream_buffer_limit: 0} = state, _entries), do: state

  defp buffer_inbound(state, entries) when is_list(entries) do
    Enum.reduce(entries, state, fn entry, acc ->
      queue = :queue.in(entry, acc.pending_inbound)
      size = acc.pending_inbound_size + 1

      {queue, size, dropped} =
        trim_inbound_queue(queue, size, acc.stream_buffer_limit, acc.pending_inbound_dropped)

      :ok = maybe_assert_inbound_size_invariant(queue, size)

      %{
        acc
        | pending_inbound: queue,
          pending_inbound_size: size,
          pending_inbound_dropped: dropped
      }
    end)
  end

  defp trim_inbound_queue(queue, size, limit, dropped)
       when is_integer(limit) and limit > 0 and size > limit do
    {{:value, _}, queue} = :queue.out(queue)
    trim_inbound_queue(queue, size - 1, limit, dropped + 1)
  end

  defp trim_inbound_queue(queue, size, _limit, dropped), do: {queue, size, dropped}

  defp flush_pending_inbound(
         %{pending_inbound_size: 0, pending_inbound: queue} = state,
         _ref,
         _pid
       ) do
    :ok = maybe_assert_inbound_size_invariant(queue, 0)
    state
  end

  defp flush_pending_inbound(state, ref, pid) do
    :ok = maybe_assert_inbound_size_invariant(state.pending_inbound, state.pending_inbound_size)

    if state.pending_inbound_dropped > 0 do
      Logger.warning("Dropped inbound messages before first subscriber",
        dropped: state.pending_inbound_dropped,
        buffer_limit: state.stream_buffer_limit
      )
    end

    state.pending_inbound
    |> :queue.to_list()
    |> Enum.each(fn
      {:claude_message, message} ->
        send(pid, {:claude_message, message})

      {:stream_event, event} ->
        send(pid, {:stream_event, ref, event})
    end)

    %{
      state
      | pending_inbound: :queue.new(),
        pending_inbound_size: 0,
        pending_inbound_dropped: 0
    }
  end

  defp maybe_assert_inbound_size_invariant(queue, size) do
    if check_inbound_size_invariant?() do
      actual = :queue.len(queue)

      if actual != size do
        raise ArgumentError,
              "pending_inbound_size invariant violated: expected #{size}, got #{actual}"
      end
    end

    :ok
  end

  defp check_inbound_size_invariant? do
    Application.get_env(:claude_agent_sdk, :check_inbound_size_invariant, false)
  end

  defp buffer_stream_events(state, events) do
    entries = Enum.map(events, &{:stream_event, &1})
    buffer_inbound(state, entries)
  end

  defp ensure_active_subscriber(%{active_subscriber: ref} = state) when is_reference(ref) do
    {ref, state}
  end

  defp ensure_active_subscriber(state) do
    case Map.keys(state.subscribers) do
      [] ->
        {nil, state}

      [ref | _] ->
        {ref, %{state | active_subscriber: ref}}
    end
  end

  defp receive_next_message({client, ref}) when is_pid(client) do
    receive do
      {:claude_message, message} ->
        {[message], {client, ref}}

      {:stream_event, ^ref, event} ->
        {[%Message{type: :stream_event, subtype: nil, data: stream_event_data(event), raw: %{}}],
         {client, ref}}
    after
      Timeouts.stream_receive_ms() ->
        # No message for timeout period, check if client still alive
        if process_running?(client) do
          receive_next_message({client, ref})
        else
          {:halt, {client, ref}}
        end
    end
  end

  defp collect_until_result(stream) do
    Enum.reduce_while(stream, [], fn message, acc ->
      acc_with_message = [message | acc]

      if message.type == :result do
        {:halt, {:ok, Enum.reverse(acc_with_message)}}
      else
        {:cont, acc_with_message}
      end
    end)
  end

  defp maybe_store_server_info(state, %{"response" => info}) when is_map(info) do
    %{state | server_info: info}
  end

  defp maybe_store_server_info(state, _), do: state

  ## SDK MCP Server Support

  @doc false
  @spec extract_sdk_mcp_servers(Options.t()) :: %{String.t() => pid()}
  defp extract_sdk_mcp_servers(%Options{mcp_servers: nil}), do: %{}

  defp extract_sdk_mcp_servers(%Options{mcp_servers: servers}) do
    for {name, %{type: :sdk, registry_pid: pid}} <- servers, into: %{} do
      {name, pid}
    end
  end

  defp handle_sdk_mcp_peer_request(request, sdk_mcp_servers, sdk_mcp_info) do
    server_name = request["serverName"] || request["server_name"]
    message = request["message"] || %{}
    message_id = message["id"]

    Logger.debug("SDK MCP request",
      request_id: request["request_id"],
      server: server_name,
      method: message["method"]
    )

    response =
      case Map.get(sdk_mcp_servers, server_name) do
        nil ->
          %{
            "jsonrpc" => "2.0",
            "id" => message_id,
            "error" => %{
              "code" => -32_601,
              "message" => "Server '#{server_name}' not found"
            }
          }

        registry_pid ->
          safe_handle_sdk_mcp_jsonrpc(
            registry_pid,
            server_name,
            message,
            sdk_mcp_info,
            message_id
          )
      end

    {:ok, {:sdk_mcp_response, response}}
  end

  defp safe_handle_sdk_mcp_jsonrpc(registry_pid, server_name, message, sdk_mcp_info, message_id) do
    handle_sdk_mcp_jsonrpc(registry_pid, server_name, message, sdk_mcp_info)
  rescue
    exception ->
      sdk_mcp_internal_error_response(message_id, Exception.message(exception))
  catch
    kind, reason ->
      sdk_mcp_internal_error_response(message_id, {kind, reason})
  end

  defp sdk_mcp_internal_error_response(message_id, reason) do
    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "error" => %{
        "code" => -32_603,
        "message" => "Internal error: #{format_sdk_mcp_internal_reason(reason)}"
      }
    }
  end

  defp format_sdk_mcp_internal_reason(reason) when is_binary(reason), do: reason
  defp format_sdk_mcp_internal_reason(reason), do: inspect(reason)

  @doc false
  @spec handle_sdk_mcp_jsonrpc(pid(), String.t(), map(), map()) :: map()
  defp handle_sdk_mcp_jsonrpc(registry_pid, server_name, message, sdk_mcp_info) do
    method = message["method"]
    params = message["params"] || %{}
    message_id = message["id"]

    dispatch_sdk_mcp_method(method, registry_pid, server_name, message_id, params, sdk_mcp_info)
  end

  defp dispatch_sdk_mcp_method(
         "initialize",
         _registry_pid,
         server_name,
         message_id,
         _params,
         sdk_mcp_info
       ) do
    server_info = Map.get(sdk_mcp_info, server_name, %{})

    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{
          "tools" => %{}
        },
        "serverInfo" => %{
          "name" => Map.get(server_info, "name", server_name),
          "version" => Map.get(server_info, "version", "1.0.0")
        }
      }
    }
  end

  defp dispatch_sdk_mcp_method(
         "tools/list",
         registry_pid,
         _server_name,
         message_id,
         _params,
         _sdk_mcp_info
       ) do
    {:ok, tools} = ClaudeAgentSDK.Tool.Registry.list_tools(registry_pid)

    tools_data =
      Enum.map(tools, fn tool ->
        base = %{
          "name" => to_string(tool.name),
          "description" => tool.description,
          "inputSchema" => tool.input_schema
        }

        base
        |> maybe_put_tool_annotations(tool)
        |> maybe_put_tool_meta(tool)
      end)

    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "result" => %{
        "tools" => tools_data
      }
    }
  end

  defp dispatch_sdk_mcp_method(
         "tools/call",
         registry_pid,
         _server_name,
         message_id,
         params,
         _sdk_mcp_info
       ) do
    tool_name = to_string(params["name"])
    tool_input = params["arguments"] || %{}

    case ClaudeAgentSDK.Tool.Registry.execute_tool(registry_pid, tool_name, tool_input) do
      {:ok, result} ->
        %{
          "jsonrpc" => "2.0",
          "id" => message_id,
          "result" => normalize_tool_result(result)
        }

      {:error, {:execution_failed, message}} ->
        sdk_mcp_internal_error_response(message_id, message)

      {:error, reason} ->
        %{
          "jsonrpc" => "2.0",
          "id" => message_id,
          "result" => normalize_tool_error(reason)
        }
    end
  end

  defp dispatch_sdk_mcp_method(
         "resources/list",
         _registry_pid,
         _server_name,
         message_id,
         _params,
         _sdk_mcp_info
       ) do
    method_not_found_response(message_id, "resources/list")
  end

  defp dispatch_sdk_mcp_method(
         "prompts/list",
         _registry_pid,
         _server_name,
         message_id,
         _params,
         _sdk_mcp_info
       ) do
    method_not_found_response(message_id, "prompts/list")
  end

  defp dispatch_sdk_mcp_method(
         "notifications/initialized",
         _registry_pid,
         _server_name,
         message_id,
         _params,
         _sdk_mcp_info
       ) do
    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "result" => %{}
    }
  end

  defp dispatch_sdk_mcp_method(
         method,
         _registry_pid,
         _server_name,
         message_id,
         _params,
         _sdk_mcp_info
       ) do
    method_not_found_response(message_id, method)
  end

  defp method_not_found_response(message_id, method) do
    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "error" => %{
        "code" => -32_601,
        "message" => "Method not found: #{method}"
      }
    }
  end

  defp maybe_put_tool_annotations(base, tool) do
    case Map.get(tool, :annotations) do
      nil -> base
      annotations when map_size(annotations) == 0 -> base
      annotations -> Map.put(base, "annotations", annotations)
    end
  end

  defp maybe_put_tool_meta(base, tool) do
    case Map.get(tool, :max_result_size_chars) do
      value when is_integer(value) and value > 0 ->
        Map.put(base, "_meta", %{"anthropic/maxResultSizeChars" => value})

      _other ->
        base
    end
  end

  defp normalize_tool_result(result) when is_map(result) do
    normalize_is_error(result)
  end

  defp normalize_tool_error(reason) do
    base =
      case reason do
        %{} = map -> normalize_tool_result(map)
        binary when is_binary(binary) -> %{"content" => [%{"type" => "text", "text" => binary}]}
        other -> %{"content" => [%{"type" => "text", "text" => inspect(other)}]}
      end

    base
    |> Map.put("is_error", true)
    |> Map.delete("isError")
  end

  defp normalize_is_error(%{} = result) do
    cond do
      Map.has_key?(result, "is_error") ->
        Map.delete(result, "isError")

      Map.has_key?(result, "isError") ->
        result
        |> Map.put("is_error", Map.get(result, "isError"))
        |> Map.delete("isError")

      true ->
        result
    end
  end

  @doc false
  @spec build_sdk_mcp_info(%{String.t() => pid()}, map() | nil) :: map() | nil
  defp build_sdk_mcp_info(sdk_mcp_servers, _mcp_servers_option)
       when map_size(sdk_mcp_servers) == 0 do
    nil
  end

  defp build_sdk_mcp_info(sdk_mcp_servers, mcp_servers_option) do
    # Build SDK MCP server info for initialization
    # We need to map server names to their metadata (name, version)
    for {server_name, _registry_pid} <- sdk_mcp_servers, into: %{} do
      # Look up server config from options to get name and version
      case Map.get(mcp_servers_option || %{}, server_name) do
        %{type: :sdk, name: name, version: version} ->
          {server_name, %{"name" => name, "version" => version}}

        %{type: :sdk, name: name} ->
          {server_name, %{"name" => name, "version" => "1.0.0"}}

        _ ->
          # Fallback if config not found
          {server_name, %{"name" => server_name, "version" => "1.0.0"}}
      end
    end
  end

  defp encode_outgoing_message(message) do
    if is_binary(message) do
      Jason.encode!(%{
        "type" => "user",
        "message" => %{"role" => "user", "content" => message}
      })
    else
      Jason.encode!(message)
    end
  end

  defp connected?(%{protocol_session: protocol_session}) when is_pid(protocol_session),
    do: Process.alive?(protocol_session)

  defp connected?(_), do: false

  defp process_running?(pid) when is_pid(pid), do: Process.info(pid, :status) != nil

  defp send_payload(%{protocol_session: protocol_session}, payload)
       when is_pid(protocol_session) do
    ProtocolSession.notify(protocol_session, %{frame: payload})
  end

  defp send_payload(_state, _payload), do: {:error, :not_connected}

  ## Stream Event Handling (v0.6.0)

  defp handle_stream_event(event_data, metadata, state) do
    # Parse streaming event via EventParser (always returns {:ok, events, accumulated})
    {:ok, events, new_accumulated} =
      EventParser.parse_event(event_data, state.accumulated_text)

    events_with_metadata = EventParser.attach_stream_metadata(events, metadata, event_data)

    {stop_reason, message_complete?} =
      Termination.reduce(events_with_metadata, state.stream_stop_reason)

    # Broadcast to active subscriber only (queue model), or buffer until subscribed
    {active_ref, state} = ensure_active_subscriber(state)

    state =
      case active_ref do
        nil ->
          buffer_stream_events(state, events_with_metadata)

        ref ->
          broadcast_events_to_subscriber(
            ref,
            state.subscribers,
            events_with_metadata
          )

          state
      end

    if message_complete? do
      state
      |> handle_stream_completion(new_accumulated)
      |> Map.put(:stream_stop_reason, nil)
    else
      %{state | accumulated_text: new_accumulated, stream_stop_reason: stop_reason}
    end
  end

  defp handle_stream_completion(state, accumulated_text) do
    # Process next queued message if any
    case state.subscriber_queue do
      [{next_ref, next_message} | rest] ->
        # Send the queued message
        json = encode_outgoing_message(next_message)
        _ = send_payload(state, json)

        # Activate next subscriber
        %{
          state
          | active_subscriber: next_ref,
            subscriber_queue: rest,
            accumulated_text: ""
        }

      [] ->
        # No queued messages, reset
        %{
          state
          | active_subscriber: nil,
            subscriber_queue: [],
            accumulated_text: accumulated_text
        }
    end
  end

  defp broadcast_events_to_subscriber(ref, subscribers, events) do
    # Look up pid for this ref
    case Map.get(subscribers, ref) do
      nil ->
        # No subscriber for this ref (possibly unsubscribed)
        :ok

      pid ->
        # Send events to the subscriber process
        Enum.each(events, fn event ->
          send(pid, {:stream_event, ref, event})
        end)
    end
  end

  defp to_cli_permission_mode(mode) do
    ClaudeAgentSDK.Permission.mode_to_string(mode)
  end

  defp broadcast_transport_error(state, error) do
    Enum.each(state.subscribers, fn {_ref, pid} ->
      send(pid, {:claude_error, error})
    end)
  end

  defp handle_transport_stderr(data, state) do
    data = IO.iodata_to_binary(data)
    {lines, stderr_buffer} = LineFraming.consume_trimmed_lines(state.stderr_buffer, data)
    dispatch_stderr_lines(lines, state.options.stderr)
    %{state | stderr_buffer: stderr_buffer}
  end

  defp flush_transport_stderr(%{stderr_buffer: ""} = state), do: state

  defp flush_transport_stderr(state) do
    state.stderr_buffer
    |> LineFraming.finalize_trimmed_lines()
    |> dispatch_stderr_lines(state.options.stderr)

    %{state | stderr_buffer: ""}
  end

  defp dispatch_stderr_lines(lines, callback) when is_function(callback, 1) and is_list(lines) do
    Enum.each(lines, callback)
  end

  defp dispatch_stderr_lines(lines, _callback) when is_list(lines) do
    Enum.each(lines, &log_stderr_line/1)
  end

  defp log_stderr_line(line) when is_binary(line) do
    rendered_line =
      if String.valid?(line) do
        line
      else
        inspect(line)
      end

    Logger.warning("CLI stderr: #{rendered_line}")
  end

  defp transport_error_mode?(state, mode) do
    state.options.transport_error_mode == mode
  end
end
