defmodule ClaudeAgentSDK.TestSupport.MockTransport do
  @moduledoc """
  Test transport that records outbound messages and allows pushing inbound frames.
  """
  use GenServer

  import Kernel, except: [send: 2]

  @event_tag :claude_agent_sdk_transport

  defstruct subscribers: %{},
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

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send(transport, message) do
    GenServer.call(transport, {:send, message})
  end

  def subscribe(transport, pid) do
    GenServer.call(transport, {:subscribe, pid})
  end

  def subscribe(transport, pid, tag) do
    GenServer.call(transport, {:subscribe, pid, tag})
  end

  def close(transport) do
    GenServer.stop(transport, :normal)
  end

  def end_input(transport) do
    GenServer.call(transport, :end_input)
  end

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

  def handle_call({:subscribe, pid}, from, state) do
    handle_call({:subscribe, pid, :legacy}, from, state)
  end

  def handle_call({:subscribe, pid, tag}, _from, state) do
    Process.monitor(pid)

    if state.test_pid do
      Kernel.send(state.test_pid, {:mock_transport_subscribed, {pid, tag}})
    end

    {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, pid, tag)}}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:recorded, _from, state) do
    {:reply, Enum.reverse(state.messages), state}
  end

  def handle_call(:end_input, _from, state) do
    if state.test_pid, do: Kernel.send(state.test_pid, {:mock_transport_end_input, self()})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:push, payload}, state) do
    Enum.each(state.subscribers, fn {pid, tag} ->
      dispatch_event(pid, tag, {:message, payload})
    end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  defp dispatch_event(pid, :legacy, {:message, payload}) do
    Kernel.send(pid, {:transport_message, payload})
  end

  defp dispatch_event(pid, ref, event) when is_reference(ref) do
    Kernel.send(pid, {@event_tag, ref, event})
  end
end
