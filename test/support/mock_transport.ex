defmodule ClaudeAgentSDK.TestSupport.MockTransport do
  @moduledoc """
  Test transport that records outbound messages and allows pushing inbound frames.
  """
  use GenServer

  import Kernel, except: [send: 2]

  @behaviour ClaudeAgentSDK.Transport

  defstruct subscribers: MapSet.new(),
            messages: [],
            status: :connected,
            test_pid: nil

  ## Public helpers for tests

  def recorded_messages(transport) do
    GenServer.call(transport, :recorded)
  end

  def push_message(transport, payload) do
    GenServer.cast(transport, {:push, payload})
  end

  ## Transport behaviour callbacks

  @impl ClaudeAgentSDK.Transport
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl ClaudeAgentSDK.Transport
  def send(transport, message) do
    GenServer.call(transport, {:send, message})
  end

  @impl ClaudeAgentSDK.Transport
  def subscribe(transport, pid) do
    GenServer.call(transport, {:subscribe, pid})
  end

  @impl ClaudeAgentSDK.Transport
  def close(transport) do
    GenServer.stop(transport, :normal)
  end

  @impl ClaudeAgentSDK.Transport
  def status(transport) do
    GenServer.call(transport, :status)
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    test_pid = Keyword.get(opts, :test_pid)
    if test_pid, do: Kernel.send(test_pid, {:mock_transport_started, self()})

    {:ok, %__MODULE__{test_pid: test_pid}}
  end

  @impl GenServer
  def handle_call({:send, message}, _from, state) do
    if state.test_pid, do: Kernel.send(state.test_pid, {:mock_transport_send, message})
    {:reply, :ok, %{state | messages: [message | state.messages]}}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    if state.test_pid, do: Kernel.send(state.test_pid, {:mock_transport_subscribed, pid})
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:recorded, _from, state) do
    {:reply, Enum.reverse(state.messages), state}
  end

  @impl GenServer
  def handle_cast({:push, payload}, state) do
    Enum.each(state.subscribers, fn pid ->
      Kernel.send(pid, {:transport_message, payload})
    end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end
end
