defmodule ClaudeAgentSDK.TestSupport.MockCLI do
  @moduledoc """
  Mock CLI process for integration testing streaming + tools scenarios.

  Simulates Claude CLI behavior by:
  - Accepting control protocol initialization
  - Emitting streaming events (text deltas, tool calls, etc.)
  - Responding to control requests (tool use, permissions, etc.)
  - Supporting scripted interaction sequences

  ## Usage

      # Create a mock CLI with predefined script
      script = [
        {:emit, stream_event(:message_start)},
        {:emit, stream_event(:text_delta, "Hello")},
        {:emit, stream_event(:message_stop)}
      ]

      {:ok, mock} = MockCLI.start_link(script: script)
      MockCLI.send_control_request(mock, initialize_request())
      events = MockCLI.receive_all_events(timeout: 1000)
  """

  use GenServer
  require Logger

  defstruct [
    :script,
    :script_index,
    :test_pid,
    :recorded_requests,
    :subscribers,
    :status
  ]

  ## Public API

  @doc "Starts a mock CLI process with optional script"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Sends a control protocol request to the mock"
  def send_control_request(mock, request) do
    GenServer.call(mock, {:control_request, request})
  end

  @doc "Emits a streaming event to all subscribers"
  def emit_event(mock, event) do
    GenServer.cast(mock, {:emit, event})
  end

  @doc "Advances the script by one step"
  def advance_script(mock) do
    GenServer.cast(mock, :advance_script)
  end

  @doc "Gets all recorded requests"
  def recorded_requests(mock) do
    GenServer.call(mock, :get_recorded)
  end

  @doc "Subscribes a process to receive events"
  def subscribe(mock, pid \\ self()) do
    GenServer.call(mock, {:subscribe, pid})
  end

  @doc "Resets the mock to initial state"
  def reset(mock) do
    GenServer.call(mock, :reset)
  end

  ## Convenience helpers for building events

  @doc "Creates a message_start event"
  def message_start_event(opts \\ []) do
    %{
      "type" => "message_start",
      "message" => %{
        "model" => Keyword.get(opts, :model, "claude-sonnet-4-5"),
        "role" => "assistant",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 0}
      }
    }
  end

  @doc "Creates a text_delta event"
  def text_delta_event(text) do
    %{
      "type" => "content_block_delta",
      "delta" => %{"type" => "text_delta", "text" => text},
      "index" => 0
    }
  end

  @doc "Creates a tool_use_start event"
  def tool_use_start_event(name, id \\ "tool_1") do
    %{
      "type" => "content_block_start",
      "content_block" => %{
        "type" => "tool_use",
        "name" => name,
        "id" => id
      },
      "index" => 1
    }
  end

  @doc "Creates a tool_input_delta event"
  def tool_input_delta_event(json) do
    %{
      "type" => "content_block_delta",
      "delta" => %{"type" => "input_json_delta", "partial_json" => json},
      "index" => 1
    }
  end

  @doc "Creates a message_stop event"
  def message_stop_event do
    %{
      "type" => "message_stop"
    }
  end

  @doc "Creates a control_response for initialization"
  def init_response(request_id) do
    %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => request_id,
        "response" => %{"commands" => []}
      }
    }
  end

  ## GenServer callbacks

  @impl GenServer
  def init(opts) do
    script = Keyword.get(opts, :script, [])
    test_pid = Keyword.get(opts, :test_pid, self())

    state = %__MODULE__{
      script: script,
      script_index: 0,
      test_pid: test_pid,
      recorded_requests: [],
      subscribers: MapSet.new(),
      status: :initialized
    }

    # Auto-run script if requested
    if Keyword.get(opts, :auto_run, false) do
      send(self(), :run_script)
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:control_request, request}, _from, state) do
    # Record request
    new_state = %{state | recorded_requests: [request | state.recorded_requests]}

    # Generate appropriate response
    response =
      case request do
        %{"type" => "control_request", "request" => %{"subtype" => "initialize"}} ->
          init_response(request["request_id"])

        %{"type" => "control_request", "request" => %{"subtype" => "permission"}} ->
          # Default: allow all tools
          %{
            "type" => "control_response",
            "response" => %{
              "subtype" => "success",
              "request_id" => request["request_id"],
              "response" => %{"decision" => "allow"}
            }
          }

        _ ->
          %{
            "type" => "control_response",
            "response" => %{
              "subtype" => "success",
              "request_id" => request["request_id"]
            }
          }
      end

    # Broadcast response to subscribers
    broadcast(new_state, response)

    {:reply, {:ok, response}, new_state}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    new_state = %{state | subscribers: MapSet.put(state.subscribers, pid)}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_recorded, _from, state) do
    {:reply, Enum.reverse(state.recorded_requests), state}
  end

  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | script_index: 0,
        recorded_requests: [],
        status: :initialized
    }

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_cast({:emit, event}, state) do
    broadcast(state, event)
    {:noreply, state}
  end

  def handle_cast(:advance_script, state) do
    new_state = process_next_script_step(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:run_script, state) do
    new_state = run_full_script(state)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_state = %{state | subscribers: MapSet.delete(state.subscribers, pid)}
    {:noreply, new_state}
  end

  ## Private helpers

  defp broadcast(state, message) do
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:mock_cli_event, message})
    end)
  end

  defp process_next_script_step(%{script_index: idx, script: script} = state)
       when idx >= length(script) do
    # Script complete
    %{state | status: :script_complete}
  end

  defp process_next_script_step(%{script_index: idx, script: script} = state) do
    step = Enum.at(script, idx)

    case step do
      {:emit, event} ->
        broadcast(state, event)
        %{state | script_index: idx + 1}

      {:delay, ms} ->
        Process.send_after(self(), :advance_script_after_delay, ms)
        %{state | script_index: idx + 1}

      {:wait_for_request} ->
        # Pause script until next request
        %{state | status: :waiting_for_request}

      nil ->
        state
    end
  end

  defp run_full_script(state) do
    Enum.reduce(0..(length(state.script) - 1), state, fn _idx, acc_state ->
      if acc_state.status == :waiting_for_request do
        acc_state
      else
        process_next_script_step(acc_state)
      end
    end)
  end
end
