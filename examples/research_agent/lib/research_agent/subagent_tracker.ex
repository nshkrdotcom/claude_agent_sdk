defmodule ResearchAgent.SubagentTracker do
  @moduledoc """
  Tracks subagent lifecycle events using ETS for concurrent access.

  The SubagentTracker monitors all subagents spawned during a research session,
  recording their spawn time, role, status, and completion. This enables:

  - Real-time monitoring of parallel research tasks
  - Post-session analysis of agent coordination patterns
  - Debugging and auditing of multi-agent workflows

  ## Agent States

  - `:running` - Agent has been spawned and is executing
  - `:completed` - Agent has finished and returned results

  ## Example

      {:ok, tracker} = SubagentTracker.start_link(name: :my_tracker)

      # Track agent spawn
      SubagentTracker.track_spawn(tracker, "agent_1", "researcher", %{topic: "AI"})

      # Track completion
      SubagentTracker.track_complete(tracker, "agent_1", %{findings: [...]})

      # Get summary
      summary = SubagentTracker.get_summary(tracker)
      # => %{total: 1, completed: 1, running: 0, ...}
  """

  use GenServer
  require Logger

  @typedoc "Agent tracking record"
  @type agent_record :: %{
          id: String.t(),
          role: String.t(),
          status: :running | :completed,
          spawned_at: integer(),
          completed_at: integer() | nil,
          metadata: map(),
          result: term() | nil
        }

  @typedoc "Tracker summary statistics"
  @type summary :: %{
          total: non_neg_integer(),
          completed: non_neg_integer(),
          running: non_neg_integer(),
          by_role: %{String.t() => non_neg_integer()}
        }

  # Client API

  @doc """
  Starts the SubagentTracker.

  ## Options

  - `:name` - Required. The name for the ETS table (atom)

  ## Example

      {:ok, pid} = SubagentTracker.start_link(name: :research_tracker)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, name, [])
  end

  @doc """
  Records a subagent spawn event.

  ## Parameters

  - `tracker` - The tracker process
  - `agent_id` - Unique identifier for the agent (typically tool_use_id)
  - `role` - The agent's role (e.g., "researcher", "analyst", "writer")
  - `metadata` - Optional metadata about the agent's task

  ## Example

      SubagentTracker.track_spawn(tracker, "toolu_123", "researcher", %{
        topic: "quantum computing",
        depth: "deep"
      })
  """
  @spec track_spawn(pid(), String.t(), String.t(), map()) :: :ok
  def track_spawn(tracker, agent_id, role, metadata \\ %{}) do
    GenServer.cast(tracker, {:track_spawn, agent_id, role, metadata})
  end

  @doc """
  Marks an agent as completed.

  ## Parameters

  - `tracker` - The tracker process
  - `agent_id` - The agent's unique identifier
  - `result` - Optional result data from the agent

  ## Example

      SubagentTracker.track_complete(tracker, "toolu_123", %{
        findings: ["Finding 1", "Finding 2"],
        sources: ["source1.com"]
      })
  """
  @spec track_complete(pid(), String.t(), term()) :: :ok
  def track_complete(tracker, agent_id, result \\ nil) do
    GenServer.cast(tracker, {:track_complete, agent_id, result})
  end

  @doc """
  Retrieves an agent record by ID.

  ## Returns

  - `{:ok, agent_record}` if found
  - `{:error, :not_found}` if not found
  """
  @spec get_agent(pid(), String.t()) :: {:ok, agent_record()} | {:error, :not_found}
  def get_agent(tracker, agent_id) do
    GenServer.call(tracker, {:get_agent, agent_id})
  end

  @doc """
  Lists all tracked agents.
  """
  @spec list_agents(pid()) :: [agent_record()]
  def list_agents(tracker) do
    GenServer.call(tracker, :list_agents)
  end

  @doc """
  Lists agents filtered by role.
  """
  @spec list_by_role(pid(), String.t()) :: [agent_record()]
  def list_by_role(tracker, role) do
    GenServer.call(tracker, {:list_by_role, role})
  end

  @doc """
  Returns summary statistics about tracked agents.
  """
  @spec get_summary(pid()) :: summary()
  def get_summary(tracker) do
    GenServer.call(tracker, :get_summary)
  end

  @doc """
  Clears all tracked agents.
  """
  @spec clear(pid()) :: :ok
  def clear(tracker) do
    GenServer.cast(tracker, :clear)
  end

  # Server Callbacks

  @impl true
  def init(table_name) do
    table = :ets.new(table_name, [:named_table, :set, :public, {:read_concurrency, true}])
    {:ok, %{table: table, table_name: table_name}}
  end

  @impl true
  def handle_cast({:track_spawn, agent_id, role, metadata}, state) do
    record = %{
      id: agent_id,
      role: role,
      status: :running,
      spawned_at: System.monotonic_time(:millisecond),
      completed_at: nil,
      metadata: metadata,
      result: nil
    }

    :ets.insert(state.table, {agent_id, record})

    Logger.debug("Subagent spawned: #{agent_id} (#{role})")

    {:noreply, state}
  end

  @impl true
  def handle_cast({:track_complete, agent_id, result}, state) do
    case :ets.lookup(state.table, agent_id) do
      [{^agent_id, record}] ->
        updated = %{
          record
          | status: :completed,
            completed_at: System.monotonic_time(:millisecond),
            result: result
        }

        :ets.insert(state.table, {agent_id, updated})
        Logger.debug("Subagent completed: #{agent_id}")

      [] ->
        Logger.warning("Attempted to complete unknown agent: #{agent_id}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(state.table)
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_agent, agent_id}, _from, state) do
    result =
      case :ets.lookup(state.table, agent_id) do
        [{^agent_id, record}] -> {:ok, record}
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    agents =
      :ets.tab2list(state.table)
      |> Enum.map(fn {_id, record} -> record end)

    {:reply, agents, state}
  end

  @impl true
  def handle_call({:list_by_role, role}, _from, state) do
    agents =
      :ets.tab2list(state.table)
      |> Enum.map(fn {_id, record} -> record end)
      |> Enum.filter(&(&1.role == role))

    {:reply, agents, state}
  end

  @impl true
  def handle_call(:get_summary, _from, state) do
    agents =
      :ets.tab2list(state.table)
      |> Enum.map(fn {_id, record} -> record end)

    summary = %{
      total: length(agents),
      completed: Enum.count(agents, &(&1.status == :completed)),
      running: Enum.count(agents, &(&1.status == :running)),
      by_role:
        agents
        |> Enum.group_by(& &1.role)
        |> Enum.map(fn {role, list} -> {role, length(list)} end)
        |> Map.new()
    }

    {:reply, summary, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up ETS table
    if :ets.whereis(state.table_name) != :undefined do
      :ets.delete(state.table)
    end

    :ok
  end
end
