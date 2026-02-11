defmodule ClaudeAgentSDK.Tool.Registry do
  @moduledoc """
  GenServer that manages tool registration and execution for SDK MCP servers.

  The Registry maintains a mapping of tool names to their metadata and execution modules,
  enabling:
  - Tool registration at server startup
  - Tool lookup by name
  - Tool execution dispatch
  - Concurrent access to tool definitions

  ## Usage

      {:ok, pid} = Registry.start_link([])

      tool = %{
        name: "calculator",
        description: "Calculate",
        input_schema: %{type: "object"},
        module: MyTools.Calculator
      }

      :ok = Registry.register_tool(pid, tool)
      {:ok, result} = Registry.execute_tool(pid, "calculator", %{"expression" => "2+2"})
  """

  use GenServer
  alias ClaudeAgentSDK.Config.Timeouts
  alias ClaudeAgentSDK.Log, as: Logger
  alias ClaudeAgentSDK.TaskSupervisor

  @type tool_name :: String.t() | atom()

  @type tool_metadata :: %{
          required(:name) => tool_name(),
          required(:description) => String.t(),
          required(:input_schema) => map(),
          required(:module) => module(),
          optional(:annotations) => map()
        }

  @type state :: %{
          tools: %{String.t() => tool_metadata()},
          pending_executions: %{
            reference() => %{
              from: GenServer.from(),
              pid: pid(),
              monitor_ref: reference(),
              timeout_ref: reference()
            }
          }
        }

  ## Client API

  @doc """
  Starts the registry GenServer.

  ## Options

  - `:name` - Optional name for the registry

  ## Examples

      {:ok, pid} = Registry.start_link([])
      {:ok, pid} = Registry.start_link(name: :my_registry)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, :ok, name: name)
    else
      GenServer.start_link(__MODULE__, :ok)
    end
  end

  @doc """
  Registers a tool with the registry.

  ## Parameters

  - `registry` - Registry PID or name
  - `tool` - Tool metadata map

  ## Returns

  - `:ok` - Successfully registered
  - `{:error, :already_registered}` - Tool already exists

  ## Examples

      tool = %{
        name: "add",
        description: "Add numbers",
        input_schema: %{type: "object"},
        module: MyTools.Add
      }

      :ok = Registry.register_tool(pid, tool)
  """
  @spec register_tool(GenServer.server(), tool_metadata()) :: :ok | {:error, :already_registered}
  def register_tool(registry, tool) do
    GenServer.call(registry, {:register_tool, tool})
  end

  @doc """
  Gets a tool by name from the registry.

  ## Parameters

  - `registry` - Registry PID or name
  - `name` - Tool name (atom)

  ## Returns

  - `{:ok, tool}` - Tool found
  - `{:error, :not_found}` - Tool not found

  ## Examples

      {:ok, tool} = Registry.get_tool(pid, "calculator")
  """
  @spec get_tool(GenServer.server(), tool_name()) ::
          {:ok, tool_metadata()} | {:error, :not_found}
  def get_tool(registry, name) do
    GenServer.call(registry, {:get_tool, name})
  end

  @doc """
  Lists all registered tools.

  ## Parameters

  - `registry` - Registry PID or name

  ## Returns

  `{:ok, tools}` where tools is a list of tool metadata maps.

  ## Examples

      {:ok, tools} = Registry.list_tools(pid)
      Enum.each(tools, fn tool -> IO.puts(tool.name) end)
  """
  @spec list_tools(GenServer.server()) :: {:ok, [tool_metadata()]}
  def list_tools(registry) do
    GenServer.call(registry, :list_tools)
  end

  @doc """
  Executes a tool with given input.

  ## Parameters

  - `registry` - Registry PID or name
  - `name` - Tool name (atom)
  - `input` - Input map matching tool's input_schema

  ## Returns

  - `{:ok, result}` - Tool executed successfully
  - `{:error, reason}` - Execution failed

  ## Examples

      {:ok, result} = Registry.execute_tool(pid, "add", %{"a" => 5, "b" => 3})
  """
  @spec execute_tool(GenServer.server(), tool_name(), map()) ::
          {:ok, map()} | {:error, term()}
  def execute_tool(registry, name, input) do
    GenServer.call(registry, {:execute_tool, name, input}, :infinity)
  end

  ## GenServer Callbacks

  @impl true
  def init(:ok) do
    {:ok, %{tools: %{}, pending_executions: %{}}}
  end

  @impl true
  def handle_call({:register_tool, tool}, _from, state) do
    name = normalize_tool_name(tool.name)
    tool = Map.put(tool, :name, name)

    if Map.has_key?(state.tools, name) do
      {:reply, {:error, :already_registered}, state}
    else
      new_tools = Map.put(state.tools, name, tool)
      {:reply, :ok, %{state | tools: new_tools}}
    end
  end

  @impl true
  def handle_call({:get_tool, name}, _from, state) do
    name = normalize_tool_name(name)

    case Map.get(state.tools, name) do
      nil -> {:reply, {:error, :not_found}, state}
      tool -> {:reply, {:ok, tool}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    tools = Map.values(state.tools)
    {:reply, {:ok, tools}, state}
  end

  @impl true
  def handle_call({:execute_tool, name, input}, from, state) do
    name = normalize_tool_name(name)

    case Map.get(state.tools, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tool ->
        start_tool_execution(state, from, tool, input)
    end
  end

  @impl true
  def handle_info({:tool_execution_result, execution_ref, result}, state) do
    case pop_execution(state, execution_ref) do
      {nil, state} ->
        {:noreply, state}

      {execution, state} ->
        cleanup_execution(execution)
        GenServer.reply(execution.from, result)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tool_execution_timeout, execution_ref}, state) do
    case pop_execution(state, execution_ref) do
      {nil, state} ->
        {:noreply, state}

      {execution, state} ->
        cleanup_execution(execution)
        Process.exit(execution.pid, :kill)
        GenServer.reply(execution.from, tool_error("Tool execution timed out"))
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case find_execution_by_monitor_ref(state, monitor_ref) do
      nil ->
        {:noreply, state}

      _execution ->
        if reason in [:normal, :shutdown] do
          {:noreply, state}
        else
          {execution, state} = pop_execution_by_monitor_ref(state, monitor_ref)
          cleanup_execution(execution)

          GenServer.reply(
            execution.from,
            tool_error("Tool execution crashed: #{inspect(reason)}")
          )

          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  ## Private Functions

  defp start_tool_execution(state, from, tool, input) do
    execution_ref = make_ref()
    server = self()

    {:ok, pid} =
      TaskSupervisor.start_child(fn ->
        result = execute_tool_safely(tool, input)
        send(server, {:tool_execution_result, execution_ref, result})
      end)

    monitor_ref = Process.monitor(pid)

    timeout_ref =
      Process.send_after(
        self(),
        {:tool_execution_timeout, execution_ref},
        execution_timeout_ms()
      )

    pending_executions =
      Map.put(state.pending_executions, execution_ref, %{
        from: from,
        pid: pid,
        monitor_ref: monitor_ref,
        timeout_ref: timeout_ref
      })

    {:noreply, %{state | pending_executions: pending_executions}}
  end

  defp pop_execution(state, execution_ref) do
    {execution, pending_executions} = Map.pop(state.pending_executions, execution_ref)
    {execution, %{state | pending_executions: pending_executions}}
  end

  defp find_execution_by_monitor_ref(state, monitor_ref) do
    case Enum.find(state.pending_executions, fn {_execution_ref, execution} ->
           execution.monitor_ref == monitor_ref
         end) do
      nil -> nil
      {_execution_ref, execution} -> execution
    end
  end

  defp pop_execution_by_monitor_ref(state, monitor_ref) do
    case Enum.find(state.pending_executions, fn {_execution_ref, execution} ->
           execution.monitor_ref == monitor_ref
         end) do
      nil ->
        {nil, state}

      {execution_ref, execution} ->
        {_old, pending_executions} = Map.pop(state.pending_executions, execution_ref)
        {execution, %{state | pending_executions: pending_executions}}
    end
  end

  defp cleanup_execution(execution) do
    Process.demonitor(execution.monitor_ref, [:flush])
    _ = Process.cancel_timer(execution.timeout_ref)
    :ok
  end

  defp execution_timeout_ms, do: Timeouts.tool_execution_ms()

  defp tool_error(message) when is_binary(message) do
    {:error,
     %{
       "content" => [
         %{
           "type" => "text",
           "text" => message
         }
       ],
       "is_error" => true
     }}
  end

  defp execute_tool_safely(tool, input) do
    tool.module.execute(input)
  rescue
    error ->
      Logger.error("Tool execution error: #{inspect(error)}")
      tool_error("Error executing tool: #{Exception.message(error)}")
  end

  defp normalize_tool_name(name) when is_binary(name), do: name
  defp normalize_tool_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_tool_name(name), do: to_string(name)
end
