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

  alias ClaudeAgentSDK.{Options, Hooks, Message}
  alias ClaudeAgentSDK.Hooks.Registry
  alias ClaudeAgentSDK.ControlProtocol.Protocol

  @typedoc """
  Client state.

  Fields:
  - `port` - Port to Claude CLI process
  - `options` - Configuration options
  - `registry` - Hook callback registry
  - `subscribers` - List of pids subscribed to messages
  - `pending_requests` - Map of request_id => {from, ref}
  - `initialized` - Whether initialization handshake completed
  - `buffer` - Incomplete JSON buffer
  - `sdk_mcp_servers` - Map of server_name => registry_pid for SDK MCP servers
  """
  @type state :: %{
          port: port() | nil,
          options: Options.t(),
          registry: Registry.t(),
          subscribers: [pid()],
          pending_requests: %{String.t() => {GenServer.from(), reference()}},
          initialized: boolean(),
          buffer: String.t(),
          sdk_mcp_servers: %{String.t() => pid()}
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
  @spec start_link(Options.t()) :: GenServer.on_start()
  def start_link(%Options{} = options) do
    GenServer.start_link(__MODULE__, options)
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
      fn _state -> :ok end
    )
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
  def init(%Options{} = options) do
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
        options: updated_options,
        registry: Registry.new(),
        subscribers: [],
        pending_requests: %{},
        initialized: false,
        buffer: "",
        session_id: nil,
        sdk_mcp_servers: sdk_mcp_servers
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
  def handle_call({:send_message, _message}, _from, %{port: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send_message, message}, _from, %{port: port} = state) do
    json =
      if is_binary(message) do
        Jason.encode!(%{"type" => "user", "message" => %{"role" => "user", "content" => message}})
      else
        Jason.encode!(message)
      end

    try do
      Port.command(port, json <> "\n")
      {:reply, :ok, state}
    rescue
      e ->
        Logger.error("Failed to send message: #{Exception.message(e)}")
        {:reply, {:error, :send_failed}, state}
    end
  end

  def handle_call({:subscribe}, from, state) do
    {pid, _ref} = from
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end

  def handle_call({:set_permission_mode, mode}, _from, state) do
    # Validate permission mode
    if ClaudeAgentSDK.Permission.valid_mode?(mode) do
      # Update options with new permission mode
      new_options = %{state.options | permission_mode: mode}
      {:reply, :ok, %{state | options: new_options}}
    else
      {:reply, {:error, :invalid_permission_mode}, state}
    end
  end

  def handle_call({:set_agent, agent_name}, _from, state) do
    # Check if agents are configured
    agents = state.options.agents || %{}

    if agents == %{} do
      {:reply, {:error, :no_agents_configured}, state}
    else
      # Check if agent exists in the map
      if Map.has_key?(agents, agent_name) do
        # Update options with new active agent
        new_options = %{state.options | agent: agent_name}

        # Apply the agent's settings to options
        case apply_agent_settings(new_options) do
          {:ok, updated_options} ->
            {:reply, :ok, %{state | options: updated_options}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      else
        {:reply, {:error, :agent_not_found}, state}
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
  def terminate(reason, %{port: port}) when is_port(port) do
    Logger.debug("Terminating client", reason: reason)

    # Close port gracefully to avoid EPIPE errors
    # Port.close will wait for the process to finish pending writes
    try do
      Port.close(port)
    catch
      :error, :badarg ->
        # Port already closed, that's fine
        :ok
    end

    :ok
  end

  def terminate(reason, _state) do
    Logger.debug("Terminating client (no port)", reason: reason)
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

  defp start_cli_process(state) do
    # Register hooks and build configuration
    registry = register_hooks(state.registry, state.options.hooks)

    # Build CLI command
    case build_cli_command(state.options) do
      {:ok, cmd} ->
        # Open port with bidirectional communication
        port =
          Port.open({:spawn, cmd}, [
            :binary,
            :exit_status,
            {:line, 65536},
            :use_stdio,
            :hide
          ])

        # Send initialize request
        hooks_config = build_hooks_config(registry, state.options.hooks)
        {request_id, init_json} = Protocol.encode_initialize_request(hooks_config, nil)

        Port.command(port, init_json <> "\n")

        Logger.debug("Sent initialize request", request_id: request_id)

        {:ok,
         %{
           state
           | port: port,
             registry: registry,
             initialized: false
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp register_hooks(registry, nil), do: registry

  defp register_hooks(registry, hooks) when is_map(hooks) do
    Enum.reduce(hooks, registry, fn {_event, matchers}, acc ->
      Enum.reduce(matchers, acc, fn matcher, reg ->
        Enum.reduce(matcher.hooks, reg, fn callback, r ->
          Registry.register(r, callback)
        end)
      end)
    end)
  end

  defp build_hooks_config(_registry, nil), do: nil

  defp build_hooks_config(registry, hooks) do
    hooks
    |> Enum.map(fn {event, matchers} ->
      event_str = Hooks.event_to_string(event)

      matchers_config =
        Enum.map(matchers, fn matcher ->
          callback_ids =
            Enum.map(matcher.hooks, fn callback ->
              Registry.get_id(registry, callback)
            end)

          %{
            "matcher" => matcher.matcher,
            "hookCallbackIds" => callback_ids
          }
        end)

      {event_str, matchers_config}
    end)
    |> Map.new()
  end

  defp build_cli_command(options) do
    executable = System.find_executable("claude")

    if executable do
      # Build arguments for streaming mode
      args = ["--output-format", "stream-json", "--input-format", "stream-json", "--verbose"]

      # Add other options
      args = args ++ Options.to_args(options)

      # Redirect stderr to /dev/null to suppress benign EPIPE errors during cleanup
      # These errors occur when the Elixir side closes the connection while the CLI
      # is still writing output - they're harmless but noisy
      cmd = Enum.join([executable | args], " ") <> " 2>/dev/null"
      {:ok, cmd}
    else
      {:error, :claude_not_found}
    end
  end

  ## Private Functions - Message Handling

  defp handle_decoded_message(:control_request, data, state) do
    # CLI is requesting something from us
    handle_control_request(data, state)
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
        send_error_response(state.port, request_id, "Unsupported request: #{other}")
        state
    end
  end

  defp handle_control_response(response_data, state) do
    response = response_data["response"]
    request_id = response["request_id"]

    case response["subtype"] do
      "success" ->
        Logger.debug("Received successful control response", request_id: request_id)

        # Mark as initialized if this was initialize response
        if not state.initialized do
          Logger.info("Client initialized successfully")
          %{state | initialized: true}
        else
          state
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
        # Invoke callback with timeout protection
        task =
          Task.async(fn ->
            try do
              context = %{}
              result = callback_fn.(input, tool_use_id, context)

              # Convert to JSON-compatible format
              if is_map(result) do
                {:ok, Hooks.Output.to_json_map(result)}
              else
                {:error, "Hook must return a map"}
              end
            rescue
              e ->
                {:error, "Hook exception: #{Exception.message(e)}"}
            end
          end)

        result =
          case Task.yield(task, 60_000) || Task.shutdown(task) do
            {:ok, {:ok, output}} ->
              {:ok, output}

            {:ok, {:error, reason}} ->
              {:error, reason}

            nil ->
              {:error, "Hook callback timeout after 60s"}
          end

        case result do
          {:ok, output} ->
            json = Protocol.encode_hook_response(request_id, output, :success)
            Port.command(state.port, json <> "\n")
            Logger.debug("Sent hook callback response", request_id: request_id)

          {:error, reason} ->
            json = Protocol.encode_hook_response(request_id, reason, :error)
            Port.command(state.port, json <> "\n")
            Logger.error("Hook callback failed", request_id: request_id, reason: reason)
        end

        state

      :error ->
        error_msg = "Callback not found: #{callback_id}"
        json = Protocol.encode_hook_response(request_id, error_msg, :error)
        Port.command(state.port, json <> "\n")
        Logger.error("Hook callback not found", callback_id: callback_id)
        state
    end
  end

  defp handle_can_use_tool_request(request_id, request, state) do
    tool_name = request["tool_name"]
    tool_input = request["input"]
    suggestions = request["permission_suggestions"] || []

    Logger.debug("Permission request for tool",
      request_id: request_id,
      tool: tool_name
    )

    # Check if we have a permission callback
    case state.options.can_use_tool do
      nil ->
        # No callback, default to allow
        json = encode_permission_response(request_id, :allow, nil)
        Port.command(state.port, json <> "\n")
        Logger.debug("No permission callback, allowing tool", tool: tool_name)
        state

      callback when is_function(callback, 1) ->
        # Build permission context
        context =
          ClaudeAgentSDK.Permission.Context.new(
            tool_name: tool_name,
            tool_input: tool_input,
            session_id: state.session_id || "unknown",
            suggestions: suggestions
          )

        # Invoke callback with timeout protection
        task =
          Task.async(fn ->
            try do
              result = callback.(context)

              # Validate result
              case ClaudeAgentSDK.Permission.Result.validate(result) do
                :ok -> {:ok, result}
                {:error, reason} -> {:error, "Invalid result: #{reason}"}
              end
            rescue
              e ->
                {:error, "Permission callback exception: #{Exception.message(e)}"}
            end
          end)

        result =
          case Task.yield(task, 60_000) || Task.shutdown(task) do
            {:ok, {:ok, permission_result}} ->
              {:ok, permission_result}

            {:ok, {:error, reason}} ->
              {:error, reason}

            nil ->
              {:error, "Permission callback timeout after 60s"}
          end

        case result do
          {:ok, permission_result} ->
            json =
              encode_permission_response(
                request_id,
                permission_result.behavior,
                permission_result
              )

            Port.command(state.port, json <> "\n")

            Logger.debug("Sent permission response",
              request_id: request_id,
              behavior: permission_result.behavior
            )

          {:error, reason} ->
            # On error, deny by default
            json = encode_permission_error_response(request_id, reason)
            Port.command(state.port, json <> "\n")
            Logger.error("Permission callback failed", request_id: request_id, reason: reason)
        end

        state
    end
  end

  defp encode_permission_response(request_id, :allow, result) do
    response = %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "result" =>
          ClaudeAgentSDK.Permission.Result.to_json_map(
            result || ClaudeAgentSDK.Permission.Result.allow()
          )
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
        "result" => ClaudeAgentSDK.Permission.Result.to_json_map(result)
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

  defp send_error_response(port, request_id, error_message) do
    json = Protocol.encode_hook_response(request_id, error_message, :error)
    Port.command(port, json <> "\n")
  end

  defp broadcast_message(message_data, state) do
    # Parse into Message struct
    case Message.from_json(Jason.encode!(message_data)) do
      {:ok, message} ->
        # Send to all subscribers
        Enum.each(state.subscribers, fn pid ->
          send(pid, {:claude_message, message})
        end)

      {:error, reason} ->
        Logger.warning("Failed to parse SDK message", reason: reason)
    end
  end

  defp subscribe(client) do
    GenServer.call(client, {:subscribe})
    client
  end

  defp receive_next_message(client) when is_pid(client) do
    receive do
      {:claude_message, message} ->
        {[message], client}
    after
      30_000 ->
        # No message for 30 seconds, check if client still alive
        if Process.alive?(client) do
          receive_next_message(client)
        else
          {:halt, client}
        end
    end
  end

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
            "code" => -32601,
            "message" => "Server '#{server_name}' not found"
          }
        }

        send_sdk_mcp_response(state.port, request_id, error_response)
        state

      registry_pid ->
        # Route to JSONRPC handler
        response = handle_sdk_mcp_jsonrpc(registry_pid, server_name, message)
        send_sdk_mcp_response(state.port, request_id, response)
        state
    end
  end

  @doc false
  @spec handle_sdk_mcp_jsonrpc(pid(), String.t(), map()) :: map()
  defp handle_sdk_mcp_jsonrpc(registry_pid, server_name, message) do
    method = message["method"]
    params = message["params"] || %{}
    message_id = message["id"]

    case method do
      "initialize" ->
        # MCP initialization - return capabilities
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

      "tools/list" ->
        # List all tools from registry
        case ClaudeAgentSDK.Tool.Registry.list_tools(registry_pid) do
          {:ok, tools} ->
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

          {:error, reason} ->
            %{
              "jsonrpc" => "2.0",
              "id" => message_id,
              "error" => %{
                "code" => -32603,
                "message" => "Failed to list tools: #{inspect(reason)}"
              }
            }
        end

      "tools/call" ->
        # Execute tool
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
                "code" => -32603,
                "message" => "Tool execution failed: #{inspect(reason)}"
              }
            }
        end

      _ ->
        # Method not found
        %{
          "jsonrpc" => "2.0",
          "id" => message_id,
          "error" => %{
            "code" => -32601,
            "message" => "Method not found: #{method}"
          }
        }
    end
  end

  @doc false
  @spec send_sdk_mcp_response(port(), String.t(), map()) :: :ok
  defp send_sdk_mcp_response(port, request_id, jsonrpc_response) do
    # Wrap JSONRPC response in control protocol response
    response = %{
      "type" => "control_response",
      "id" => request_id,
      "response" => jsonrpc_response
    }

    json = Jason.encode!(response)
    Port.command(port, json <> "\n")
    Logger.debug("Sent SDK MCP response", request_id: request_id)
    :ok
  end
end
