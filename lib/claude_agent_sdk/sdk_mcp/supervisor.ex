defmodule ClaudeAgentSDK.SDKMCP.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ClaudeAgentSDK.Tool.Registry

  @spec start(keyword()) :: Supervisor.on_start()
  def start(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start(DynamicSupervisor, {__MODULE__, :ok, name}, opts)
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: name)
  end

  @spec ensure_started() :: {:ok, pid()} | {:error, term()}
  def ensure_started do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        :global.trans({__MODULE__, :start}, &ensure_started_locked/0)
    end
  end

  @spec start_registry() :: pid()
  def start_registry do
    case ensure_started() do
      {:ok, _pid} ->
        start_registry(__MODULE__)

      {:error, reason} ->
        raise ArgumentError,
              "failed to start internal SDK MCP supervisor: #{inspect(reason)}"
    end
  end

  @spec start_registry(pid() | atom()) :: pid()
  def start_registry(supervisor) do
    case DynamicSupervisor.start_child(supervisor, registry_child_spec()) do
      {:ok, registry_pid} ->
        registry_pid

      {:error, {:already_started, registry_pid}} ->
        registry_pid

      {:error, reason} ->
        raise ArgumentError,
              "failed to start SDK MCP Tool.Registry under supervisor #{inspect(supervisor)}: #{inspect(reason)}"
    end
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp ensure_started_locked do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        case start(name: __MODULE__) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp registry_child_spec do
    %{
      id: {Registry, make_ref()},
      start: {Registry, :start_link, [[]]},
      restart: :temporary,
      type: :worker
    }
  end
end
