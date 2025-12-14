defmodule Examples.RuntimeControl.MockTransport do
  @moduledoc false

  use GenServer

  import Kernel, except: [send: 2]

  @behaviour ClaudeAgentSDK.Transport

  defstruct subscribers: MapSet.new(),
            messages: [],
            status: :connected,
            owner: nil,
            delay_ms: 0

  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def send(transport, message) do
    GenServer.call(transport, {:send, message})
  end

  @impl true
  def subscribe(transport, pid) do
    GenServer.call(transport, {:subscribe, pid})
  end

  @impl true
  def close(transport) do
    GenServer.stop(transport, :normal)
  end

  @impl true
  def status(transport) do
    GenServer.call(transport, :status)
  end

  def push_json(transport, payload) when is_map(payload) do
    payload
    |> Jason.encode!()
    |> push_raw(transport)
  end

  def push_raw(payload, transport) when is_binary(payload) do
    GenServer.cast(transport, {:push, payload})
  end

  def recorded(transport) do
    GenServer.call(transport, :recorded)
  end

  @impl true
  def init(opts) do
    owner = Keyword.get(opts, :owner)
    delay_ms = Keyword.get(opts, :delay_ms, 0)
    if owner, do: Kernel.send(owner, {:mock_transport_started, self()})

    {:ok, %__MODULE__{owner: owner, delay_ms: delay_ms}}
  end

  @impl true
  def handle_call({:send, message}, _from, state) do
    if state.delay_ms > 0, do: Process.sleep(state.delay_ms)
    if state.owner, do: Kernel.send(state.owner, {:mock_transport_send, message})
    {:reply, :ok, %{state | messages: [message | state.messages]}}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_call(:recorded, _from, state) do
    {:reply, Enum.reverse(state.messages), state}
  end

  @impl true
  def handle_cast({:push, payload}, state) do
    Enum.each(state.subscribers, fn pid ->
      Kernel.send(pid, {:transport_message, payload})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end
end
