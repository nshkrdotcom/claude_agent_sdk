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
        name: :calculator,
        description: "Calculate",
        input_schema: %{type: "object"},
        module: MyTools.Calculator
      }

      :ok = Registry.register_tool(pid, tool)
      {:ok, result} = Registry.execute_tool(pid, :calculator, %{"expression" => "2+2"})
  """

  use GenServer
  require Logger

  @type tool_metadata :: %{
          name: atom(),
          description: String.t(),
          input_schema: map(),
          module: module()
        }

  @type state :: %{
          tools: %{atom() => tool_metadata()}
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
        name: :add,
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

      {:ok, tool} = Registry.get_tool(pid, :calculator)
  """
  @spec get_tool(GenServer.server(), atom()) :: {:ok, tool_metadata()} | {:error, :not_found}
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

      {:ok, result} = Registry.execute_tool(pid, :add, %{"a" => 5, "b" => 3})
  """
  @spec execute_tool(GenServer.server(), atom(), map()) ::
          {:ok, map()} | {:error, term()}
  def execute_tool(registry, name, input) do
    GenServer.call(registry, {:execute_tool, name, input}, :infinity)
  end

  ## GenServer Callbacks

  @impl true
  def init(:ok) do
    {:ok, %{tools: %{}}}
  end

  @impl true
  def handle_call({:register_tool, tool}, _from, state) do
    name = tool.name

    if Map.has_key?(state.tools, name) do
      {:reply, {:error, :already_registered}, state}
    else
      new_tools = Map.put(state.tools, name, tool)
      {:reply, :ok, %{state | tools: new_tools}}
    end
  end

  @impl true
  def handle_call({:get_tool, name}, _from, state) do
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
  def handle_call({:execute_tool, name, input}, _from, state) do
    case Map.get(state.tools, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tool ->
        result = execute_tool_safely(tool, input)
        {:reply, result, state}
    end
  end

  ## Private Functions

  defp execute_tool_safely(tool, input) do
    try do
      # Call the tool module's execute function
      tool.module.execute(input)
    rescue
      error ->
        # Only log in non-test environments (tests verify error handling works)
        if Mix.env() != :test do
          Logger.error("Tool execution error: #{inspect(error)}")
        end

        {:error,
         %{
           "content" => [
             %{
               "type" => "text",
               "text" => "Error executing tool: #{Exception.message(error)}"
             }
           ],
           "isError" => true
         }}
    end
  end
end
