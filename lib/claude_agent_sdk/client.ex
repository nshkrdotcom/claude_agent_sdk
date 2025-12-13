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
  require Logger

  alias ClaudeAgentSDK.{AbortSignal, CLI, Hooks, Message, Model, Options}
  alias ClaudeAgentSDK.ControlProtocol.Protocol
  alias ClaudeAgentSDK.Hooks.{Matcher, Output, Registry}
  alias ClaudeAgentSDK.Permission.{Context, Result}
  alias ClaudeAgentSDK.Streaming.EventParser
  @default_hook_timeout_ms 60_000
  @default_init_timeout_ms 60_000
  @init_timeout_env_var "CLAUDE_CODE_STREAM_CLOSE_TIMEOUT"

  @typedoc """
  Client state.

  Fields:
  - `port` - Port to Claude CLI process
  - `options` - Configuration options
  - `registry` - Hook callback registry
  - `hook_callback_timeouts` - Map of callback_id => timeout_ms
  - `subscribers` - Map of ref => pid for streaming subscriptions, or list of pids for legacy
  - `pending_requests` - Map of request_id => {from, ref}
  - `pending_callbacks` - Map of request_id => %{pid, signal, type} for in-flight control callbacks
  - `initialized` - Whether initialization handshake completed
  - `buffer` - Incomplete JSON buffer
  - `sdk_mcp_servers` - Map of server_name => registry_pid for SDK MCP servers
  - `accumulated_text` - Buffer for partial text (streaming, v0.6.0)
  - `active_subscriber` - Current streaming consumer reference (v0.6.0)
  - `subscriber_queue` - Pending message queue (v0.6.0)
  """
  @type state :: %{
          port: port() | nil,
          transport: pid() | nil,
          transport_module: module() | nil,
          transport_opts: keyword(),
          options: Options.t(),
          registry: Registry.t(),
          hook_callback_timeouts: %{String.t() => pos_integer()},
          subscribers: %{reference() => pid()} | [pid()],
          pending_requests: %{String.t() => {GenServer.from(), reference()}},
          pending_callbacks: %{
            String.t() => %{
              pid: pid(),
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
          accumulated_text: String.t(),
          active_subscriber: reference() | nil,
          subscriber_queue: [{reference(), String.t()}],
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
  Sets the permission mode at runtime.

  Changes how tool permissions are handled for subsequent tool uses.

  ## Parameters

  - `client` - Client PID
  - `mode` - Permission mode atom (`:default`, `:accept_edits`, `:plan`, `:bypass_permissions`)

  ## Returns

  - `:ok` - Successfully changed mode
  - `{:error, :invalid_permission_mode}` - Invalid mode provided

  ## Examples

      Client.set_permission_mode(pid, :plan)
      Client.set_permission_mode(pid, :accept_edits)
      Client.set_permission_mode(pid, :bypass_permissions)
  """
  @spec set_permission_mode(pid(), ClaudeAgentSDK.Permission.permission_mode()) ::
          :ok | {:error, :invalid_permission_mode}
  def set_permission_mode(client, mode) when is_pid(client) do
    GenServer.call(client, {:set_permission_mode, mode})
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
    transport_module = Keyword.get(opts, :transport)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    # Validate hooks and permission callback configuration before starting
    with :ok <- validate_hooks(options.hooks),
         :ok <- validate_permission_callback(options.can_use_tool),
         {:ok, updated_options} <- apply_agent_settings(options) do
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
        # Streaming support fields (v0.6.0)
        accumulated_text: "",
        active_subscriber: nil,
        subscriber_queue: [],
        server_info: nil,
        init_request_id: nil,
        init_timeout_ref: nil,
        init_timeout_ms: nil
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
        {:noreply, new_state}

      {:error, reason} ->
        {:stop, {:cli_start_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    if connected?(state) do
      json = encode_outgoing_message(message)

      case send_payload(state, json) do
        :ok ->
          {:reply, :ok, state}

        {:error, reason} ->
          Logger.error("Failed to send message", reason: inspect(reason))
          {:reply, {:error, :send_failed}, state}
      end
    else
      {:reply, {:error, :not_connected}, state}
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

    # Add to subscribers map
    subscribers = Map.put(state.subscribers, ref, pid)

    # Activate if no active subscriber, otherwise subscriber waits
    new_active =
      if state.active_subscriber == nil do
        ref
      else
        state.active_subscriber
      end

    {:reply, {:ok, ref},
     %{
       state
       | subscribers: subscribers,
         active_subscriber: new_active
     }}
  end

  # Legacy subscribe (backwards compatibility) - generate a ref for the pid
  def handle_call({:subscribe}, from, state) do
    {pid, _ref} = from
    # For backwards compat, create a ref for this pid subscription
    ref = make_ref()
    subscribers = Map.put(state.subscribers, ref, pid)
    {:reply, :ok, %{state | subscribers: subscribers}}
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
            pending_requests =
              Map.put(state.pending_requests, request_id, {:set_permission_mode, from, mode})

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
        pending_requests = Map.put(state.pending_requests, request_id, {:interrupt, from})
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
            pending_requests = Map.put(state.pending_requests, request_id, {:rewind_files, from})
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
      pending_requests =
        Map.put(state.pending_requests, request_id, {:set_model, from, normalized})

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
  def handle_info({:transport_message, payload}, state) do
    case decode_transport_payload(payload) do
      {:ok, {message_type, message_data}} ->
        new_state = handle_decoded_message(message_type, message_data, state)
        {:noreply, new_state}

      {:error, :empty_message} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Failed to decode transport message", reason: inspect(reason))
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
  def handle_info({:callback_result, request_id, :permission, signal, result}, state) do
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
                permission_result
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
    state = cancel_pending_callbacks(state)
    {:stop, :normal, %{state | transport: nil}}
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
        Logger.warning("Failed to decode message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    # Accumulate data in buffer (for non-EOL mode)
    full_data = state.buffer <> data

    # Split by newlines and process complete messages
    lines = String.split(full_data, "\n")

    # Last element might be incomplete
    {complete_lines, remaining} =
      if lines == [] do
        {[], ""}
      else
        case List.pop_at(lines, -1) do
          {last, rest} when last == "" ->
            # Ends with newline, all complete
            {rest, ""}

          {last, rest} when is_binary(last) and is_list(rest) ->
            # Last line might be incomplete
            {rest, last}

          _ ->
            {[], ""}
        end
      end

    # Process each complete line
    new_state =
      Enum.reduce(complete_lines, state, fn line, acc_state ->
        case Protocol.decode_message(line) do
          {:ok, {message_type, message_data}} ->
            handle_decoded_message(message_type, message_data, acc_state)

          {:error, :empty_message} ->
            acc_state

          {:error, reason} ->
            Logger.warning("Failed to decode message: #{inspect(reason)}")
            acc_state
        end
      end)

    {:noreply, %{new_state | buffer: remaining}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("CLI process exited with status: #{status}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.info("CLI process terminated: #{inspect(reason)}")
    {:stop, :normal, state}
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

    if Mix.env() != :test do
      Logger.debug("Terminating client", reason: reason)
    end

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
          # Don't log in test env - this is expected behavior when stopping quickly
          if Mix.env() != :test do
            Logger.debug("CLI didn't exit within timeout, forcing close")
          end

          :ok
      end

      # Now it's safe to close the port (CLI is already done)
      Port.close(port)
    catch
      :error, :badarg ->
        # Port already closed, that's fine
        :ok
    end

    :ok
  end

  def terminate(reason, state) do
    state
    |> cancel_init_timeout()
    |> cancel_pending_callbacks()

    if Mix.env() != :test do
      Logger.debug("Terminating client (no port)", reason: reason)
    end

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
      {:ok, cmd} ->
        port =
          Port.open({:spawn, cmd}, [
            :binary,
            :exit_status,
            {:line, 65_536},
            :use_stdio,
            :hide
          ])

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
             init_timeout_ms: init_timeout_ms
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
    case CLI.find_executable() do
      {:ok, executable} ->
        # Build arguments for streaming mode
        args = ["--output-format", "stream-json", "--input-format", "stream-json", "--verbose"]

        # Add other options
        args = args ++ Options.to_args(options)

        # Redirect stderr to /dev/null to suppress benign EPIPE errors during cleanup
        # These errors occur when the Elixir side closes the connection while the CLI
        # is still writing output - they're harmless but noisy
        cmd = Enum.join([executable | args], " ") <> " 2>/dev/null"
        {:ok, cmd}

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
    state
  end

  defp handle_decoded_message(:stream_event, data, state) do
    # Streaming event (v0.6.0) - handle both wrapped and unwrapped formats
    # Real CLI: {"type": "stream_event", "event": {"type": "message_start", ...}}
    # Tests: {"type": "message_start", ...}
    event_data = if data["type"] == "stream_event", do: data["event"], else: data
    handle_stream_event(event_data, state)
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

    dispatch_control_response(pending_entry, response_data, response, request_id, updated_state)
  end

  defp dispatch_control_response(
         {:set_model, from, requested_model},
         response_data,
         response,
         request_id,
         state
       ) do
    handle_set_model_response(from, requested_model, response_data, response, request_id, state)
  end

  defp dispatch_control_response(
         {:set_permission_mode, from, requested_mode},
         _response_data,
         response,
         request_id,
         state
       ) do
    handle_set_permission_mode_response(from, requested_mode, response, request_id, state)
  end

  defp dispatch_control_response({:interrupt, from}, _response_data, response, request_id, state) do
    handle_simple_control_response(:interrupt, from, response, request_id, state)
  end

  defp dispatch_control_response(
         {:rewind_files, from},
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
          Task.start(fn ->
            result =
              execute_hook_callback(callback_fn, input, tool_use_id, signal, timeout_ms)

            send(server, {:callback_result, request_id, :hook, signal, result})
          end)

        put_pending_callback(state, request_id, pid, signal, :hook)

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
    session_id = state.session_id || "unknown"

    Logger.debug("Permission request for tool",
      request_id: request_id,
      tool: tool_name
    )

    # Check if we have a permission callback
    case state.options.can_use_tool do
      nil ->
        # No callback, default to allow
        json = encode_permission_response(request_id, :allow, nil)
        _ = send_payload(state, json)
        Logger.debug("No permission callback, allowing tool", tool: tool_name)
        state

      callback when is_function(callback, 1) ->
        signal = AbortSignal.new()
        server = self()

        {:ok, pid} =
          Task.start(fn ->
            result =
              execute_permission_callback(
                callback,
                tool_name,
                tool_input,
                suggestions,
                session_id,
                signal
              )

            send(server, {:callback_result, request_id, :permission, signal, result})
          end)

        put_pending_callback(state, request_id, pid, signal, :permission)
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

  defp encode_permission_response(request_id, :allow, result) do
    response = %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "result" => Result.to_json_map(result || Result.allow())
      }
    }

    Jason.encode!(response)
  end

  defp encode_permission_response(request_id, :deny, result) do
    response = %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "result" => Result.to_json_map(result)
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

  defp put_pending_callback(state, request_id, pid, signal, type) do
    pending =
      Map.put(state.pending_callbacks, request_id, %{pid: pid, signal: signal, type: type})

    %{state | pending_callbacks: pending}
  end

  defp pop_pending_callback(state, request_id) do
    {entry, pending} = Map.pop(state.pending_callbacks, request_id)
    {entry, %{state | pending_callbacks: pending}}
  end

  defp cancel_pending_callbacks(state) do
    Enum.each(state.pending_callbacks, fn {_id, %{pid: pid, signal: signal}} ->
      AbortSignal.cancel(signal)
      Process.exit(pid, :kill)
    end)

    %{state | pending_callbacks: %{}}
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
        # Send to all subscribers (now a map of ref => pid)
        Enum.each(state.subscribers, fn {_ref, pid} ->
          send(pid, {:claude_message, message})
        end)

      {:error, reason} ->
        Logger.warning("Failed to parse SDK message", reason: reason)
    end
  end

  defp receive_next_message({client, ref}) when is_pid(client) do
    receive do
      {:claude_message, message} ->
        {[message], {client, ref}}

      {:stream_event, ^ref, event} ->
        {[%{type: :stream_event, event: event}], {client, ref}}
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
    server_name = request["serverName"]
    message = request["message"]

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
        response = handle_sdk_mcp_jsonrpc(registry_pid, server_name, message)
        send_sdk_mcp_response(state, request_id, response)
        state
    end
  end

  @doc false
  @spec handle_sdk_mcp_jsonrpc(pid(), String.t(), map()) :: map()
  defp handle_sdk_mcp_jsonrpc(registry_pid, server_name, message) do
    method = message["method"]
    params = message["params"] || %{}
    message_id = message["id"]

    dispatch_sdk_mcp_method(method, registry_pid, server_name, message_id, params)
  end

  defp dispatch_sdk_mcp_method("initialize", _registry_pid, server_name, message_id, _params) do
    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{
          "tools" => %{}
        },
        "serverInfo" => %{
          "name" => server_name,
          "version" => "1.0.0"
        }
      }
    }
  end

  defp dispatch_sdk_mcp_method("tools/list", registry_pid, _server_name, message_id, _params) do
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

  defp dispatch_sdk_mcp_method("tools/call", registry_pid, _server_name, message_id, params) do
    tool_name = String.to_atom(params["name"])
    tool_input = params["arguments"] || %{}

    case ClaudeAgentSDK.Tool.Registry.execute_tool(registry_pid, tool_name, tool_input) do
      {:ok, result} ->
        %{
          "jsonrpc" => "2.0",
          "id" => message_id,
          "result" => result
        }

      {:error, reason} ->
        %{
          "jsonrpc" => "2.0",
          "id" => message_id,
          "error" => %{
            "code" => -32_603,
            "message" => "Tool execution failed: #{inspect(reason)}"
          }
        }
    end
  end

  defp dispatch_sdk_mcp_method("resources/list", _registry_pid, _server_name, message_id, _params) do
    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "result" => %{"resources" => []}
    }
  end

  defp dispatch_sdk_mcp_method("prompts/list", _registry_pid, _server_name, message_id, _params) do
    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "result" => %{"prompts" => []}
    }
  end

  defp dispatch_sdk_mcp_method(
         "notifications/initialized",
         _registry_pid,
         _server_name,
         message_id,
         _params
       ) do
    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "result" => %{}
    }
  end

  defp dispatch_sdk_mcp_method(method, _registry_pid, _server_name, message_id, _params) do
    %{
      "jsonrpc" => "2.0",
      "id" => message_id,
      "error" => %{
        "code" => -32_601,
        "message" => "Method not found: #{method}"
      }
    }
  end

  @doc false
  @spec send_sdk_mcp_response(state(), String.t(), map()) :: :ok
  defp send_sdk_mcp_response(state, request_id, jsonrpc_response) do
    # Wrap JSONRPC response in control protocol response
    response = %{
      "type" => "control_response",
      "id" => request_id,
      "response" => jsonrpc_response
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

  defp handle_stream_event(event_data, state) do
    # Parse streaming event via EventParser (always returns {:ok, events, accumulated})
    {:ok, events, new_accumulated} =
      EventParser.parse_event(event_data, state.accumulated_text)

    # Broadcast to active subscriber only (queue model)
    if state.active_subscriber do
      broadcast_events_to_subscriber(
        state.active_subscriber,
        state.subscribers,
        events
      )
    end

    # Check for message completion
    message_complete? = Enum.any?(events, &(&1.type == :message_stop))

    if message_complete? do
      handle_stream_completion(state, new_accumulated)
    else
      %{state | accumulated_text: new_accumulated}
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
    case mode do
      :accept_edits -> "acceptEdits"
      :bypass_permissions -> "bypassPermissions"
      other -> to_string(other)
    end
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
end
