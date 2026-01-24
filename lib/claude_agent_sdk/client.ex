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
  """

  use GenServer
  alias ClaudeAgentSDK.Log, as: Logger

  alias ClaudeAgentSDK.{AbortSignal, CLI, Hooks, Message, Model, Options, TaskSupervisor}
  alias ClaudeAgentSDK.ControlProtocol.Protocol
  alias ClaudeAgentSDK.Hooks.{Matcher, Output, Registry}
  alias ClaudeAgentSDK.Permission.{Context, Result}
  alias ClaudeAgentSDK.Streaming.{EventParser, Termination}
  alias ClaudeAgentSDK.Transport.AgentsFile
  @default_hook_timeout_ms 60_000
  @default_init_timeout_ms 60_000
  @default_control_request_timeout_ms 60_000
  @default_stream_buffer_limit 1_000
  @init_timeout_env_var "CLAUDE_CODE_STREAM_CLOSE_TIMEOUT"
  @edit_tools ["Write", "Edit", "MultiEdit"]

  @typedoc """
  Client state.

  Fields:
  - `port` - Port to Claude CLI process
  - `options` - Configuration options
  - `registry` - Hook callback registry
  - `hook_callback_timeouts` - Map of callback_id => timeout_ms
  - `subscribers` - Map of ref => pid for streaming subscriptions
  - `pending_requests` - Map of request_id => {from, ref}
  - `pending_callbacks` - Map of request_id => %{pid, monitor_ref, signal, type} for in-flight control callbacks
  - `initialized` - Whether initialization handshake completed
  - `buffer` - Incomplete JSON buffer
  - `sdk_mcp_servers` - Map of server_name => registry_pid for SDK MCP servers
  - `accumulated_text` - Buffer for partial text (streaming, v0.6.0)
  - `active_subscriber` - Current streaming consumer reference (v0.6.0)
  - `subscriber_queue` - Pending message queue (v0.6.0)
  - `init_waiters` - Callers waiting for initialize request send
  - `pending_inbound` - Buffered inbound events/messages before first subscriber
  - `pending_inbound_count` - Count of buffered inbound entries
  - `pending_inbound_dropped` - Dropped inbound entries due to buffer limit
  - `stream_buffer_limit` - Max buffered inbound entries before first subscriber
  """
  @type state :: %{
          port: port() | nil,
          transport: pid() | nil,
          transport_module: module() | nil,
          transport_opts: keyword(),
          options: Options.t(),
          registry: Registry.t(),
          hook_callback_timeouts: %{String.t() => pos_integer()},
          subscribers: %{reference() => pid()},
          pending_requests: %{String.t() => {GenServer.from(), reference()}},
          pending_callbacks: %{
            String.t() => %{
              pid: pid(),
              monitor_ref: reference(),
              signal: ClaudeAgentSDK.AbortSignal.t(),
              type: :hook | :permission
            }
          },
          initialized: boolean(),
          buffer: String.t(),
          sdk_mcp_servers: %{String.t() => pid()},
          current_model: String.t() | nil,
          pending_model_change: {GenServer.from(), reference()} | nil,
          current_permission_mode: ClaudeAgentSDK.Permission.permission_mode() | nil,
          pending_permission_change: {GenServer.from(), reference()} | nil,
          permission_bridge: :ets.tid() | nil,
          accumulated_text: String.t(),
          active_subscriber: reference() | nil,
          subscriber_queue: [{reference(), String.t()}],
          init_waiters: [GenServer.from()],
          pending_inbound: :queue.queue(),
          pending_inbound_count: non_neg_integer(),
          pending_inbound_dropped: non_neg_integer(),
          stream_buffer_limit: non_neg_integer(),
          server_info: map() | nil,
          init_request_id: String.t() | nil,
          init_timeout_ref: reference() | nil,
          init_timeout_ms: pos_integer() | nil
        }

  ## Public API

  @doc """
  Starts the client GenServer.

  Validates hooks configuration, starts Claude CLI process, and performs
  initialization handshake.

  ## Parameters

  - `options` - ClaudeAgentSDK.Options struct with hooks configuration

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
            30_000 ->
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
    GenServer.stop(client, :normal, 5000)
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

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_initialized(client, deadline)
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
        @default_init_timeout_ms
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
  - `mode` - Permission mode atom (`:default`, `:accept_edits`, `:plan`, `:bypass_permissions`, `:delegate`, `:dont_ask`)

  ## Returns

  - `:ok` - Successfully changed mode
  - `{:error, :invalid_permission_mode}` - Invalid mode provided

  ## Examples

      Client.set_permission_mode(pid, :plan)
      Client.set_permission_mode(pid, :accept_edits)
      Client.set_permission_mode(pid, :bypass_permissions)
      Client.set_permission_mode(pid, :delegate)
  """
  @spec set_permission_mode(pid(), ClaudeAgentSDK.Permission.permission_mode()) ::
          :ok | {:error, :invalid_permission_mode}
  def set_permission_mode(client, mode) when is_pid(client) do
    GenServer.call(client, {:set_permission_mode, mode}, :infinity)
  end

  defp do_await_initialized(client, deadline_ms) do
    if System.monotonic_time(:millisecond) > deadline_ms do
      {:error, :timeout}
    else
      state = :sys.get_state(client)

      if Map.get(state, :initialized) == true do
        :ok
      else
        Process.sleep(50)
        do_await_initialized(client, deadline_ms)
      end
    end
  rescue
    _ -> {:error, :client_not_alive}
  catch
    :exit, _ -> {:error, :client_not_alive}
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
    transport_module = Keyword.get(opts, :transport) || default_transport_module(options)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    # Validate hooks and permission callback configuration before starting
    with :ok <- validate_hooks(options.hooks),
         :ok <- validate_permission_callback(options.can_use_tool),
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
      state = %{
        port: nil,
        transport: nil,
        transport_module: transport_module,
        transport_opts: transport_opts,
        options: updated_options,
        registry: Registry.new(),
        hook_callback_timeouts: %{},
        subscribers: %{},
        pending_requests: %{},
        pending_callbacks: %{},
        initialized: false,
        buffer: "",
        session_id: nil,
        sdk_mcp_servers: sdk_mcp_servers,
        current_model: updated_options.model,
        pending_model_change: nil,
        current_permission_mode: updated_options.permission_mode,
        pending_permission_change: nil,
        permission_bridge: permission_bridge,
        # Streaming support fields (v0.6.0)
        accumulated_text: "",
        stream_stop_reason: nil,
        active_subscriber: nil,
        subscriber_queue: [],
        init_waiters: [],
        pending_inbound: :queue.new(),
        pending_inbound_count: 0,
        pending_inbound_dropped: 0,
        stream_buffer_limit: stream_buffer_limit(updated_options),
        server_info: nil,
        init_request_id: nil,
        init_timeout_ref: nil,
        init_timeout_ms: nil,
        temp_files: []
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

  defp default_transport_module(%Options{user: user}) when is_binary(user),
    do: ClaudeAgentSDK.Transport.Erlexec

  defp default_transport_module(_), do: ClaudeAgentSDK.Transport.Port

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

    case send_payload(state, json) do
      :ok ->
        {:reply, :ok, state}

      {:error, :not_connected} ->
        {:reply, {:error, :not_connected}, state}

      {:error, reason} ->
        Logger.error("Failed to send message", reason: inspect(reason))
        {:reply, {:error, :send_failed}, state}
    end
  end

  def handle_call({:set_model, model}, from, state) do
    if state.pending_model_change != nil do
      {:reply, {:error, :model_change_in_progress}, state}
    else
      set_model_request(model, from, state)
    end
  end

  def handle_call({:subscribe, ref}, from, state) do
    {pid, _from_ref} = from
    was_empty = map_size(state.subscribers) == 0

    # Add to subscribers map
    subscribers = Map.put(state.subscribers, ref, pid)

    # Activate if no active subscriber, otherwise subscriber waits
    new_active =
      if state.active_subscriber == nil do
        ref
      else
        state.active_subscriber
      end

    state = %{
      state
      | subscribers: subscribers,
        active_subscriber: new_active
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

  # Legacy subscribe (backwards compatibility) - generate a ref for the pid
  def handle_call({:subscribe}, from, state) do
    {pid, _ref} = from
    # For backwards compat, create a ref for this pid subscription
    ref = make_ref()
    was_empty = map_size(state.subscribers) == 0
    subscribers = Map.put(state.subscribers, ref, pid)

    state =
      if state.active_subscriber == nil do
        %{state | subscribers: subscribers, active_subscriber: ref}
      else
        %{state | subscribers: subscribers}
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

        case send_payload(state, json) do
          :ok ->
            timer_ref = schedule_control_request_timeout(request_id)

            pending_requests =
              Map.put(
                state.pending_requests,
                request_id,
                {:set_permission_mode, from, mode, timer_ref}
              )

            {:noreply,
             %{
               state
               | pending_requests: pending_requests,
                 pending_permission_change: request_id
             }}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:get_model, _from, state) do
    case state.current_model do
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

    case send_payload(state, json) do
      :ok ->
        timer_ref = schedule_control_request_timeout(request_id)

        pending_requests =
          Map.put(state.pending_requests, request_id, {:interrupt, from, timer_ref})

        {:noreply, %{state | pending_requests: pending_requests}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
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

        case send_payload(state, json) do
          :ok ->
            timer_ref = schedule_control_request_timeout(request_id)

            pending_requests =
              Map.put(state.pending_requests, request_id, {:rewind_files, from, timer_ref})

            {:noreply, %{state | pending_requests: pending_requests}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
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

  defp set_model_request(model, from, state) do
    model_string = model |> to_string() |> String.trim()

    with {:ok, normalized} <- Model.validate(model_string),
         {request_id, json} = Protocol.encode_set_model_request(normalized),
         :ok <- send_payload(state, json) do
      timer_ref = schedule_control_request_timeout(request_id)

      pending_requests =
        Map.put(state.pending_requests, request_id, {:set_model, from, normalized, timer_ref})

      {:noreply,
       %{
         state
         | pending_requests: pending_requests,
           pending_model_change: request_id
       }}
    else
      {:error, :invalid_model} ->
        suggestions = Model.suggest(model_string)
        {:reply, {:error, {:invalid_model, suggestions}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:unsubscribe, ref}, state) do
    # Remove from subscribers map
    subscribers = Map.delete(state.subscribers, ref)

    # Remove from queue if present
    queue = Enum.reject(state.subscriber_queue, fn {r, _msg} -> r == ref end)

    # If this was the active subscriber, activate next in queue
    {new_active, new_queue} =
      if state.active_subscriber == ref do
        case queue do
          [{next_ref, next_message} | rest] ->
            # Send queued message and activate
            json = encode_outgoing_message(next_message)
            _ = send_payload(state, json)
            {next_ref, rest}

          [] ->
            {nil, []}
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
  def handle_info({:initialize_timeout, request_id}, state) do
    cond do
      state.initialized ->
        {:noreply, state}

      state.init_request_id != request_id ->
        {:noreply, state}

      true ->
        Logger.error("Initialization control request timed out",
          request_id: request_id,
          timeout_ms: state.init_timeout_ms
        )

        new_state =
          state
          |> cancel_init_timeout()
          |> Map.put(:init_request_id, nil)

        {:stop, {:initialize_timeout, request_id}, new_state}
    end
  end

  @impl true
  def handle_info({:transport_error, error}, state) do
    message = transport_error_message(error)

    Enum.each(state.subscribers, fn {_ref, pid} ->
      send(pid, {:claude_message, message})
    end)

    {:noreply, state}
  end

  def handle_info({:transport_message, payload}, state) do
    case decode_transport_payload(payload) do
      {:ok, {message_type, message_data}} ->
        new_state = handle_decoded_message(message_type, message_data, state)
        {:noreply, new_state}

      {:error, :empty_message} ->
        {:noreply, state}

      {:error, reason} ->
        # Log both the reason AND the payload (truncated) for debugging
        payload_preview = inspect(payload, limit: 50)

        Logger.warning("Failed to decode transport message",
          reason: inspect(reason),
          payload_preview: payload_preview
        )

        {:noreply, state}
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
            json = Protocol.encode_hook_response(request_id, output, :success)
            _ = send_payload(updated_state, json)
            Logger.debug("Sent hook callback response", request_id: request_id)

          {:error, reason} ->
            json = Protocol.encode_hook_response(request_id, reason, :error)
            _ = send_payload(updated_state, json)
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
            json =
              encode_permission_response(
                request_id,
                permission_result.behavior,
                permission_result,
                original_input
              )

            _ = send_payload(updated_state, json)

            Logger.debug("Sent permission response",
              request_id: request_id,
              behavior: permission_result.behavior
            )

          {:error, reason} ->
            json = encode_permission_error_response(request_id, reason)
            _ = send_payload(updated_state, json)
            Logger.error("Permission callback failed", request_id: request_id, reason: reason)
        end

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:transport_exit, reason}, state) do
    Logger.info("Transport disconnected", reason: inspect(reason))

    state =
      state
      |> cancel_pending_callbacks()
      |> fail_pending_control_requests({:transport_exit, reason})

    {:stop, :normal, %{state | transport: nil}}
  end

  @impl true
  def handle_info({:control_request_timeout, request_id}, state) when is_binary(request_id) do
    {pending_entry, pending_requests} = Map.pop(state.pending_requests, request_id)
    state = %{state | pending_requests: pending_requests}

    case pending_entry do
      nil ->
        {:noreply, state}

      {:set_model, from, _requested_model, _timer_ref} ->
        Logger.warning("Control request timed out", request_id: request_id, subtype: "set_model")
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_model_change: nil}}

      {:set_permission_mode, from, _requested_mode, _timer_ref} ->
        Logger.warning("Control request timed out",
          request_id: request_id,
          subtype: "set_permission_mode"
        )

        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_permission_change: nil}}

      {:interrupt, from, _timer_ref} ->
        Logger.warning("Control request timed out", request_id: request_id, subtype: "interrupt")
        GenServer.reply(from, {:error, :timeout})
        {:noreply, state}

      {:rewind_files, from, _timer_ref} ->
        Logger.warning("Control request timed out",
          request_id: request_id,
          subtype: "rewind_files"
        )

        GenServer.reply(from, {:error, :timeout})
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) when is_binary(line) do
    # Process complete line (EOL mode from port)
    case Protocol.decode_message(line) do
      {:ok, {message_type, message_data}} ->
        new_state = handle_decoded_message(message_type, message_data, state)
        {:noreply, new_state}

      {:error, :empty_message} ->
        {:noreply, state}

      {:error, reason} ->
        {:noreply, handle_decode_error(line, reason, state)}
    end
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    # Accumulate data in buffer (for non-EOL mode)
    full_data = state.buffer <> data

    {complete_lines, remaining} = split_complete_lines(full_data)

    new_state = Enum.reduce(complete_lines, state, &process_message_line/2)

    {:noreply, %{new_state | buffer: remaining}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("CLI process exited with status: #{status}")
    state = fail_pending_control_requests(state, {:exit_status, status})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.info("CLI process terminated: #{inspect(reason)}")
    state = fail_pending_control_requests(state, {:exit, reason})
    {:stop, :normal, state}
  end

  # Handle callback task crashes - OTP supervision compliance
  # When a callback task exits abnormally, we need to:
  # 1. Find the pending callback by monitor ref
  # 2. Send an error response to the CLI
  # 3. Clean up the pending_callbacks map
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    # Normal exits can arrive before the callback_result message; let the result handler clean up.
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case find_callback_by_monitor_ref(state.pending_callbacks, ref) do
      nil ->
        # Not a callback we're tracking, ignore
        {:noreply, state}

      {request_id, entry} ->
        Logger.error("Callback task crashed",
          request_id: request_id,
          type: entry.type,
          reason: inspect(reason)
        )

        # Send error response based on callback type
        error_message = "Callback crashed: #{inspect(reason)}"

        case entry.type do
          :hook ->
            json = Protocol.encode_hook_response(request_id, error_message, :error)
            _ = send_payload(state, json)

          :permission ->
            json = encode_permission_error_response(request_id, error_message)
            _ = send_payload(state, json)
        end

        # Remove the callback from pending_callbacks (no need to demonitor, it's already down)
        pending = Map.delete(state.pending_callbacks, request_id)
        {:noreply, %{state | pending_callbacks: pending}}
    end
  end

  defp split_complete_lines(full_data) do
    lines = String.split(full_data, "\n")

    case List.pop_at(lines, -1) do
      {nil, _rest} ->
        {[], ""}

      {"", rest} ->
        {rest, ""}

      {last, rest} when is_binary(last) and is_list(rest) ->
        {rest, last}

      _ ->
        {[], ""}
    end
  end

  defp process_message_line(line, state) do
    case Protocol.decode_message(line) do
      {:ok, {message_type, message_data}} ->
        handle_decoded_message(message_type, message_data, state)

      {:error, :empty_message} ->
        state

      {:error, reason} ->
        handle_decode_error(line, reason, state)
    end
  end

  defp handle_decode_error(line, reason, state) do
    if is_function(state.options.stderr, 1) do
      state.options.stderr.(line)
      state
    else
      Logger.warning("Failed to decode message: #{inspect(reason)}")
      state
    end
  end

  @impl true
  def terminate(reason, %{transport: transport, transport_module: module} = state)
      when is_pid(transport) do
    state =
      state
      |> cancel_init_timeout()
      |> cancel_pending_callbacks()

    try do
      module.close(transport)
    catch
      :exit, _ -> :ok
    end

    terminate(reason, %{state | transport: nil})
  end

  def terminate(reason, %{port: port} = state) when is_port(port) do
    _state = state |> cancel_init_timeout() |> cancel_pending_callbacks()

    Logger.debug("Terminating client", reason: reason)

    # Graceful shutdown to avoid EPIPE errors in Claude CLI
    #
    # ROOT CAUSE: Port.close() immediately closes stdin/stdout/stderr pipes,
    # but the CLI subprocess might still be writing output. This causes EPIPE
    # when CLI tries to write to a closed pipe.
    #
    # SOLUTION: Wait for the CLI process to exit naturally before closing port.
    # The CLI should exit when stdin is closed (EOF signal).
    try do
      # Wait for exit_status message (indicates process has fully exited)
      # This prevents EPIPE by ensuring CLI finishes all writes before we close
      receive do
        {^port, {:exit_status, status}} ->
          Logger.debug("CLI exited cleanly with status #{status}")
          :ok
      after
        200 ->
          # If CLI doesn't exit within 200ms, force close
          Logger.debug("CLI didn't exit within timeout, forcing close")
          :ok
      end

      # Now it's safe to close the port (CLI is already done)
      Port.close(port)
    catch
      :error, :badarg ->
        # Port already closed, that's fine
        :ok
    end

    _ = AgentsFile.cleanup_temp_files(state.temp_files || [])

    :ok
  end

  def terminate(reason, state) do
    state
    |> cancel_init_timeout()
    |> cancel_pending_callbacks()

    Logger.debug("Terminating client (no port)", reason: reason)

    _ = AgentsFile.cleanup_temp_files(state.temp_files || [])

    :ok
  end

  ## Private Functions - Initialization

  defp validate_hooks(nil), do: :ok
  defp validate_hooks(hooks), do: Hooks.validate_config(hooks)

  defp validate_permission_callback(nil), do: :ok

  defp validate_permission_callback(callback) do
    ClaudeAgentSDK.Permission.validate_callback(callback)
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
            # Apply agent's settings to options
            updated_options = %{
              options
              | system_prompt: agent.prompt,
                allowed_tools: agent.allowed_tools,
                model: agent.model
            }

            {:ok, updated_options}

          {:error, reason} ->
            {:error, {:invalid_agent, agent_name, reason}}
        end
    end
  end

  defp apply_agent_settings(options), do: {:ok, options}

  defp apply_permission_mode(options), do: {:ok, options}

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

  defp stream_buffer_limit(_options), do: @default_stream_buffer_limit

  defp maybe_attach_permission_hook(%Options{can_use_tool: nil} = options) do
    {:ok, options, nil}
  end

  defp maybe_attach_permission_hook(
         %Options{can_use_tool: _callback, permission_mode: :delegate} = options
       ) do
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
              tool_name,
              tool_input,
              [],
              nil,
              session_id,
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

    env =
      if Map.has_key?(env, "CLAUDE_CODE_ENTRYPOINT") or
           Map.has_key?(env, :CLAUDE_CODE_ENTRYPOINT) do
        env
      else
        Map.put(env, "CLAUDE_CODE_ENTRYPOINT", "sdk-elixir-client")
      end

    %{options | env: env}
  end

  @doc false
  @spec init_timeout_seconds_from_env() :: number()
  def init_timeout_seconds_from_env do
    env_value = System.get_env(@init_timeout_env_var)

    parsed_ms =
      case env_value do
        value when is_binary(value) ->
          case Integer.parse(value) do
            {int, _} when int > 0 -> int
            _ -> @default_init_timeout_ms
          end

        _ ->
          @default_init_timeout_ms
      end

    timeout_ms = max(parsed_ms, @default_init_timeout_ms)
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
    if state.init_request_id == request_id and is_reference(state.init_timeout_ref) do
      _ = Process.cancel_timer(state.init_timeout_ref)
      %{state | init_timeout_ref: nil, init_request_id: nil, init_timeout_ms: nil}
    else
      state
    end
  end

  defp control_request_timeout_ms do
    Application.get_env(
      :claude_agent_sdk,
      :control_request_timeout_ms,
      @default_control_request_timeout_ms
    )
  end

  defp schedule_control_request_timeout(request_id) when is_binary(request_id) do
    Process.send_after(
      self(),
      {:control_request_timeout, request_id},
      control_request_timeout_ms()
    )
  end

  defp cancel_control_request_timeout(nil), do: :ok

  defp cancel_control_request_timeout({:set_model, _from, _requested_model, timer_ref}),
    do: Process.cancel_timer(timer_ref)

  defp cancel_control_request_timeout({:set_permission_mode, _from, _requested_mode, timer_ref}),
    do: Process.cancel_timer(timer_ref)

  defp cancel_control_request_timeout({:interrupt, _from, timer_ref}),
    do: Process.cancel_timer(timer_ref)

  defp cancel_control_request_timeout({:rewind_files, _from, timer_ref}),
    do: Process.cancel_timer(timer_ref)

  defp cancel_control_request_timeout(_other), do: :ok

  defp fail_pending_control_requests(state, reason) do
    Enum.each(state.pending_requests, fn {_request_id, pending_entry} ->
      _ = cancel_control_request_timeout(pending_entry)

      case pending_entry do
        {:set_model, from, _requested_model, _timer_ref} ->
          GenServer.reply(from, {:error, reason})

        {:set_permission_mode, from, _requested_mode, _timer_ref} ->
          GenServer.reply(from, {:error, reason})

        {:interrupt, from, _timer_ref} ->
          GenServer.reply(from, {:error, reason})

        {:rewind_files, from, _timer_ref} ->
          GenServer.reply(from, {:error, reason})

        _ ->
          :ok
      end
    end)

    %{
      state
      | pending_requests: %{},
        pending_model_change: nil,
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

  defp cancel_init_timeout(%{init_timeout_ref: ref} = state) when is_reference(ref) do
    _ = Process.cancel_timer(ref)
    %{state | init_timeout_ref: nil, init_timeout_ms: nil}
  end

  defp cancel_init_timeout(state), do: state

  defp start_cli_process(%{transport_module: module} = state) when not is_nil(module) do
    registry = register_hooks(state.registry, state.options.hooks)
    hook_callback_timeouts = build_hook_timeout_map(registry, state.options.hooks)
    hooks_config = build_hooks_config(registry, state.options.hooks)
    sdk_mcp_info = build_sdk_mcp_info(state.sdk_mcp_servers, state.options.mcp_servers)

    # Pass Options to transport so it can build CLI command with streaming flags
    transport_opts = Keyword.put(state.transport_opts || [], :options, state.options)

    with {:ok, transport} <- module.start_link(transport_opts),
         :ok <- module.subscribe(transport, self()) do
      {init_request_id, init_json} =
        Protocol.encode_initialize_request(hooks_config, sdk_mcp_info, nil)

      {init_timeout_ref, init_timeout_ms} = schedule_initialize_timeout(init_request_id)

      _ = module.send(transport, ensure_newline(init_json))

      {:ok,
       %{
         state
         | transport: transport,
           registry: registry,
           hook_callback_timeouts: hook_callback_timeouts,
           initialized: false,
           init_request_id: init_request_id,
           init_timeout_ref: init_timeout_ref,
           init_timeout_ms: init_timeout_ms
       }}
    else
      {:error, reason} ->
        {:error, {:transport_failed, reason}}
    end
  end

  defp start_cli_process(state) do
    # Register hooks and build configuration
    registry = register_hooks(state.registry, state.options.hooks)
    hook_callback_timeouts = build_hook_timeout_map(registry, state.options.hooks)

    # Build CLI command
    case build_cli_command(state.options) do
      {:ok, {cmd, temp_files}} ->
        port_opts =
          [
            :binary,
            :exit_status,
            {:line, 65_536},
            :use_stdio,
            :hide
          ]

        port_opts =
          if is_function(state.options.stderr, 1) do
            [:stderr_to_stdout | port_opts]
          else
            port_opts
          end

        port =
          Port.open({:spawn, cmd}, port_opts)

        hooks_config = build_hooks_config(registry, state.options.hooks)
        sdk_mcp_info = build_sdk_mcp_info(state.sdk_mcp_servers, state.options.mcp_servers)

        {init_request_id, init_json} =
          Protocol.encode_initialize_request(hooks_config, sdk_mcp_info, nil)

        {init_timeout_ref, init_timeout_ms} = schedule_initialize_timeout(init_request_id)

        Port.command(port, ensure_newline(init_json))

        {:ok,
         %{
           state
           | port: port,
             registry: registry,
             hook_callback_timeouts: hook_callback_timeouts,
             initialized: false,
             init_request_id: init_request_id,
             init_timeout_ref: init_timeout_ref,
             init_timeout_ms: init_timeout_ms,
             temp_files: temp_files
         }}

      {:error, reason} ->
        {:error, reason}
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
      nil -> @default_hook_timeout_ms
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

  defp build_cli_command(options) do
    case CLI.resolve_executable(options) do
      {:ok, executable} ->
        # Build arguments for streaming mode.
        #
        # Claude Code CLI only enables stream-json input/output in `--print` mode.
        # (see `claude --help` for the current semantics)
        args = [
          "--print",
          "--output-format",
          "stream-json",
          "--input-format",
          "stream-json",
          "--verbose"
        ]

        # Add other options
        args = args ++ Options.to_stream_json_args(options)
        {args, temp_files} = AgentsFile.externalize_agents_if_needed(args)

        # Redirect stderr to /dev/null to suppress benign EPIPE errors during cleanup
        # These errors occur when the Elixir side closes the connection while the CLI
        # is still writing output - they're harmless but noisy
        stderr_redirect =
          if is_function(options.stderr, 1) do
            ""
          else
            " 2>/dev/null"
          end

        cmd = Enum.join([executable | args], " ") <> stderr_redirect
        {:ok, {cmd, temp_files}}

      {:error, :not_found} ->
        {:error, :claude_not_found}
    end
  end

  ## Private Functions - Message Handling

  defp handle_decoded_message(:control_request, data, state) do
    # CLI is requesting something from us
    handle_control_request(data, state)
  end

  defp handle_decoded_message(:control_cancel_request, data, state) do
    handle_control_cancel_request(data, state)
  end

  defp handle_decoded_message(:control_response, data, state) do
    # CLI is responding to our request
    handle_control_response(data, state)
  end

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
        event = Map.fetch!(data, "event")
        uuid = Map.fetch!(data, "uuid")
        session_id = Map.fetch!(data, "session_id")

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

  defp handle_control_request(request_data, state) do
    request_id = request_data["request_id"]
    request = request_data["request"]

    case request["subtype"] do
      "hook_callback" ->
        handle_hook_callback(request_id, request, state)

      "can_use_tool" ->
        handle_can_use_tool_request(request_id, request, state)

      "sdk_mcp_request" ->
        handle_sdk_mcp_request(request_id, request, state)

      # Python parity: accept the Python SDK MCP request subtype as well.
      "mcp_message" ->
        handle_sdk_mcp_request(request_id, request, state)

      other ->
        Logger.warning("Unsupported control request subtype", subtype: other)
        send_error_response(state, request_id, "Unsupported request: #{other}")
        state
    end
  end

  defp handle_control_cancel_request(request_data, state) do
    request_id = request_data["request_id"]
    {pending, updated_state} = pop_pending_callback(state, request_id)

    case pending do
      nil ->
        Logger.debug("Cancel request for unknown callback", request_id: request_id)
        updated_state

      %{pid: pid, signal: signal, type: type} ->
        AbortSignal.cancel(signal)
        Process.exit(pid, :kill)
        send_cancellation_response(updated_state, request_id, type)
        updated_state
    end
  end

  defp handle_control_response(response_data, state) do
    response = response_data["response"]
    request_id = response["request_id"]
    {pending_entry, pending_requests} = Map.pop(state.pending_requests, request_id)

    updated_state =
      state
      |> Map.put(:pending_requests, pending_requests)
      |> maybe_cancel_init_timeout(request_id)

    _ = cancel_control_request_timeout(pending_entry)

    dispatch_control_response(pending_entry, response_data, response, request_id, updated_state)
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
        %{state | pending_model_change: nil}

      other ->
        Logger.warning("Unexpected subtype for set_model response",
          request_id: request_id,
          subtype: other
        )

        GenServer.reply(from, {:error, :unexpected_response})
        %{state | pending_model_change: nil}
    end
  end

  defp handle_set_model_success(from, requested_model, response_data, request_id, state) do
    case Protocol.decode_set_model_response(response_data) do
      {:ok, model} ->
        Logger.info("Model changed successfully", request_id: request_id, model: model)
        GenServer.reply(from, :ok)
        %{state | current_model: model, pending_model_change: nil}

      {:error, :invalid_response} when is_binary(requested_model) ->
        Logger.info(
          "Model change acknowledged without explicit model; using requested value",
          request_id: request_id,
          model: requested_model
        )

        GenServer.reply(from, :ok)
        %{state | current_model: requested_model, pending_model_change: nil}

      {:error, reason} ->
        Logger.error(
          "Failed to decode set_model response: #{inspect(response_data)} (reason=#{inspect(reason)})",
          request_id: request_id
        )

        GenServer.reply(from, {:error, reason})
        %{state | pending_model_change: nil}
    end
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
            current_permission_mode: requested_mode,
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

  defp handle_untracked_control_response(response, request_id, state) do
    case response["subtype"] do
      "success" ->
        Logger.debug("Received successful control response", request_id: request_id)

        state_with_info = maybe_store_server_info(state, response)

        if state_with_info.initialized do
          state_with_info
        else
          Logger.info("Client initialized successfully")
          %{state_with_info | initialized: true}
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

  defp handle_hook_callback(request_id, request, state) do
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
        signal = AbortSignal.new()
        server = self()

        {:ok, pid} =
          TaskSupervisor.start_child(fn ->
            result =
              execute_hook_callback(callback_fn, input, tool_use_id, signal, timeout_ms)

            send(server, {:callback_result, request_id, :hook, signal, result})
          end)

        # Monitor the callback task to detect crashes
        monitor_ref = Process.monitor(pid)
        put_pending_callback(state, request_id, pid, monitor_ref, signal, :hook)

      :error ->
        error_msg = "Callback not found: #{callback_id}"
        json = Protocol.encode_hook_response(request_id, error_msg, :error)
        _ = send_payload(state, json)
        Logger.error("Hook callback not found", callback_id: callback_id)
        state
    end
  end

  defp hook_timeout_ms(state, callback_id) do
    state
    |> Map.get(:hook_callback_timeouts, %{})
    |> Map.get(callback_id, @default_hook_timeout_ms)
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

  defp handle_can_use_tool_request(request_id, request, state) do
    tool_name = request["tool_name"]
    tool_input = request["input"]
    suggestions = request["permission_suggestions"] || []
    blocked_path = request["blocked_path"]
    session_id = state.session_id || "unknown"

    Logger.debug("Permission request for tool",
      request_id: request_id,
      tool: tool_name
    )

    permission_bridge_put(state.permission_bridge, :can_use_tool_seen, true)

    # Check if we have a permission callback
    case state.options.can_use_tool do
      nil ->
        # No callback, default to allow
        json = encode_permission_response(request_id, :allow, nil, tool_input)
        _ = send_payload(state, json)
        Logger.debug("No permission callback, allowing tool", tool: tool_name)
        state

      callback when is_function(callback, 1) ->
        signal = AbortSignal.new()
        server = self()

        {:ok, pid} =
          TaskSupervisor.start_child(fn ->
            result =
              execute_permission_callback(
                callback,
                tool_name,
                tool_input,
                suggestions,
                blocked_path,
                session_id,
                signal
              )

            send(server, {:callback_result, request_id, :permission, signal, tool_input, result})
          end)

        # Monitor the callback task to detect crashes
        monitor_ref = Process.monitor(pid)
        put_pending_callback(state, request_id, pid, monitor_ref, signal, :permission)
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

  defp execute_permission_callback(
         callback,
         tool_name,
         tool_input,
         suggestions,
         blocked_path,
         session_id,
         signal
       ) do
    task =
      Task.async(fn ->
        try do
          context =
            Context.new(
              tool_name: tool_name,
              tool_input: tool_input,
              session_id: session_id,
              suggestions: suggestions,
              blocked_path: blocked_path,
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
        end
      end)

    case Task.yield(task, 60_000) || Task.shutdown(task) do
      {:ok, {:ok, permission_result}} ->
        {:ok, permission_result}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, "Permission callback timeout after 60s"}

      {:exit, reason} ->
        {:error, "Permission callback failed: #{inspect(reason)}"}
    end
  end

  defp encode_permission_response(request_id, :allow, result, original_input) do
    original_input = if is_map(original_input), do: original_input, else: %{}

    result_map =
      result
      |> then(&(&1 || Result.allow()))
      |> Result.to_json_map()
      |> Map.put_new("updatedInput", original_input)

    response = %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "response" => result_map
      }
    }

    Jason.encode!(response)
  end

  defp encode_permission_response(request_id, :deny, result, _original_input) do
    response = %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "response" => Result.to_json_map(result)
      }
    }

    Jason.encode!(response)
  end

  defp encode_permission_error_response(request_id, error_message) do
    response = %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "error",
        "error" => error_message
      }
    }

    Jason.encode!(response)
  end

  defp put_pending_callback(state, request_id, pid, monitor_ref, signal, type) do
    pending =
      Map.put(state.pending_callbacks, request_id, %{
        pid: pid,
        monitor_ref: monitor_ref,
        signal: signal,
        type: type
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

  defp send_cancellation_response(state, request_id, :hook) do
    json = Protocol.encode_hook_response(request_id, "Callback cancelled", :error)
    _ = send_payload(state, json)
    Logger.debug("Sent hook cancellation response", request_id: request_id)
  end

  defp send_cancellation_response(state, request_id, :permission) do
    json = encode_permission_error_response(request_id, "Permission callback cancelled")
    _ = send_payload(state, json)
    Logger.debug("Sent permission cancellation response", request_id: request_id)
  end

  defp send_cancellation_response(_state, _request_id, _type), do: :ok

  defp send_error_response(state, request_id, error_message) do
    json = Protocol.encode_hook_response(request_id, error_message, :error)
    _ = send_payload(state, json)
  end

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
      count = acc.pending_inbound_count + 1

      {queue, count, dropped} =
        trim_inbound_queue(queue, count, acc.stream_buffer_limit, acc.pending_inbound_dropped)

      %{
        acc
        | pending_inbound: queue,
          pending_inbound_count: count,
          pending_inbound_dropped: dropped
      }
    end)
  end

  defp trim_inbound_queue(queue, count, limit, dropped)
       when is_integer(limit) and limit > 0 and count > limit do
    {{:value, _}, queue} = :queue.out(queue)
    trim_inbound_queue(queue, count - 1, limit, dropped + 1)
  end

  defp trim_inbound_queue(queue, count, _limit, dropped), do: {queue, count, dropped}

  defp flush_pending_inbound(%{pending_inbound_count: 0} = state, _ref, _pid), do: state

  defp flush_pending_inbound(state, ref, pid) do
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
        pending_inbound_count: 0,
        pending_inbound_dropped: 0
    }
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
      30_000 ->
        # No message for 30 seconds, check if client still alive
        if Process.alive?(client) do
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

  @doc false
  @spec handle_sdk_mcp_request(String.t(), map(), state()) :: state()
  defp handle_sdk_mcp_request(request_id, request, state) do
    server_name = request["serverName"] || request["server_name"]
    message = request["message"]
    sdk_mcp_info = build_sdk_mcp_info(state.sdk_mcp_servers, state.options.mcp_servers) || %{}

    Logger.debug("SDK MCP request",
      request_id: request_id,
      server: server_name,
      method: message["method"]
    )

    # Look up server registry PID
    case Map.get(state.sdk_mcp_servers, server_name) do
      nil ->
        # Server not found
        error_response = %{
          "jsonrpc" => "2.0",
          "id" => message["id"],
          "error" => %{
            "code" => -32_601,
            "message" => "Server '#{server_name}' not found"
          }
        }

        send_sdk_mcp_response(state, request_id, error_response)
        state

      registry_pid ->
        # Route to JSONRPC handler
        response = handle_sdk_mcp_jsonrpc(registry_pid, server_name, message, sdk_mcp_info)
        send_sdk_mcp_response(state, request_id, response)
        state
    end
  end

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
        %{
          "name" => to_string(tool.name),
          "description" => tool.description,
          "inputSchema" => tool.input_schema
        }
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
  @spec send_sdk_mcp_response(state(), String.t(), map()) :: :ok
  defp send_sdk_mcp_response(state, request_id, jsonrpc_response) do
    # Wrap JSONRPC response in control protocol response
    # Must match Python SDK format: {"type": "control_response", "response": {"subtype": "success", ...}}
    # The mcp_response is nested inside response.response.mcp_response (see Python query.py line 311)
    response = %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => request_id,
        "response" => %{
          "mcp_response" => jsonrpc_response
        }
      }
    }

    json = Jason.encode!(response)
    _ = send_payload(state, json)
    Logger.debug("Sent SDK MCP response", request_id: request_id)
    :ok
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

  defp connected?(%{transport: transport}) when is_pid(transport), do: true
  defp connected?(%{port: port}) when is_port(port), do: true
  defp connected?(_), do: false

  defp send_payload(%{transport: transport, transport_module: module}, payload)
       when is_pid(transport) do
    module.send(transport, ensure_newline(payload))
  end

  defp send_payload(%{port: port}, payload) when is_port(port) do
    Port.command(port, ensure_newline(payload))
    :ok
  rescue
    e -> {:error, e}
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

  defp ensure_newline(payload) when is_binary(payload) do
    if String.ends_with?(payload, "\n") do
      payload
    else
      payload <> "\n"
    end
  end

  defp decode_transport_payload(payload) when is_binary(payload) do
    Protocol.decode_message(payload)
  end

  defp decode_transport_payload(payload) when is_map(payload) do
    payload
    |> Jason.encode!()
    |> Protocol.decode_message()
  end

  defp decode_transport_payload(payload) when is_list(payload) do
    payload
    |> Jason.encode!()
    |> Protocol.decode_message()
  end

  defp transport_error_message(%ClaudeAgentSDK.Errors.CLIJSONDecodeError{} = error) do
    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: Exception.message(error),
        error_struct: error,
        session_id: "error",
        is_error: true
      }
    }
  end

  defp transport_error_message(error) do
    %Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: "Transport error: #{inspect(error)}",
        error_struct: error,
        session_id: "error",
        is_error: true
      }
    }
  end
end
