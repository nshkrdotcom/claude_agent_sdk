defmodule ClaudeAgentSDK.QueryStreamingTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Message, Options, Query}
  alias ClaudeAgentSDK.TestSupport.MockTransport

  defmodule FailingInputTransport do
    use GenServer

    import Kernel, except: [send: 2]

    @behaviour ClaudeAgentSDK.Transport

    @impl ClaudeAgentSDK.Transport
    def start(opts), do: GenServer.start(__MODULE__, opts)

    @impl ClaudeAgentSDK.Transport
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl ClaudeAgentSDK.Transport
    def send(transport, message), do: GenServer.call(transport, {:send, message})

    @impl ClaudeAgentSDK.Transport
    def subscribe(transport, pid), do: GenServer.call(transport, {:subscribe, pid})

    @impl ClaudeAgentSDK.Transport
    def close(transport), do: GenServer.stop(transport, :normal)

    @impl ClaudeAgentSDK.Transport
    def end_input(transport), do: GenServer.call(transport, :end_input)

    @impl ClaudeAgentSDK.Transport
    def status(_transport), do: :connected

    @impl true
    def init(opts) do
      {:ok, %{subscribers: MapSet.new(), test_pid: Keyword.get(opts, :test_pid)}}
    end

    @impl true
    def handle_call({:subscribe, pid}, _from, state) do
      {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
    end

    def handle_call({:send, _message}, _from, state) do
      {:reply, {:error, :simulated_send_failure}, state}
    end

    def handle_call(:end_input, _from, state) do
      if is_pid(state.test_pid) do
        Kernel.send(state.test_pid, :failing_input_transport_end_input_called)
      end

      {:reply, :ok, state}
    end
  end

  defmodule EndInputFailTransport do
    use GenServer

    import Kernel, except: [send: 2]

    @behaviour ClaudeAgentSDK.Transport

    @impl ClaudeAgentSDK.Transport
    def start(opts), do: GenServer.start(__MODULE__, opts)

    @impl ClaudeAgentSDK.Transport
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl ClaudeAgentSDK.Transport
    def send(_transport, _message), do: :ok

    @impl ClaudeAgentSDK.Transport
    def subscribe(transport, pid), do: GenServer.call(transport, {:subscribe, pid})

    @impl ClaudeAgentSDK.Transport
    def close(transport), do: GenServer.stop(transport, :normal)

    @impl ClaudeAgentSDK.Transport
    def end_input(_transport), do: {:error, :simulated_end_input_failure}

    @impl ClaudeAgentSDK.Transport
    def status(_transport), do: :connected

    @impl true
    def init(_opts) do
      {:ok, %{subscribers: MapSet.new()}}
    end

    @impl true
    def handle_call({:subscribe, pid}, _from, state) do
      {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
    end
  end

  test "streams responses while sending enumerable prompts through injected transport" do
    prompt = [
      %{
        "type" => "user",
        "message" => %{"role" => "user", "content" => "hi"}
      }
    ]

    stream = Query.run(prompt, %Options{}, {MockTransport, [test_pid: self()]})

    task = Task.async(fn -> Enum.take(stream, 1) end)

    assert_receive {:mock_transport_started, transport}, 1_000
    assert_receive {:mock_transport_subscribed, _pid}, 1_000
    assert_receive {:mock_transport_send, sent_prompt}, 1_000
    assert sent_prompt == hd(prompt)
    assert_receive {:mock_transport_end_input, ^transport}, 1_000

    assistant = %{
      "type" => "assistant",
      "message" => %{"role" => "assistant", "content" => "hello"},
      "session_id" => "sess"
    }

    MockTransport.push_message(transport, Jason.encode!(assistant))

    assert [%Message{type: :assistant}] = Task.await(task, 500)
  end

  test "surfaces input worker failures and still closes stdin" do
    prompt = [
      %{
        "type" => "user",
        "message" => %{"role" => "user", "content" => "hi"}
      }
    ]

    stream = Query.run(prompt, %Options{}, {FailingInputTransport, [test_pid: self()]})

    task = Task.async(fn -> Enum.take(stream, 1) end)

    assert [%Message{type: :result, subtype: :error_during_execution, data: data}] =
             Task.await(task, 1_000)

    assert data.is_error == true
    assert data.error =~ "Input stream worker failed"
    assert_receive :failing_input_transport_end_input_called, 1_000
  end

  test "propagates end_input startup failures immediately" do
    stream = Query.run("hi", %Options{}, EndInputFailTransport)

    assert [%Message{type: :result, subtype: :error_during_execution, data: data}] =
             Enum.take(stream, 1)

    assert data.is_error == true
    assert data.error =~ "end_input_failed"
  end
end
