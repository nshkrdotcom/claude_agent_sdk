defmodule ClaudeAgentSDK.Mock do
  @moduledoc """
  Mock implementation for the Claude Code CLI for testing purposes.

  This module provides a GenServer-based mock system that allows testing and development
  without making actual API calls to the Claude service. It can be configured with
  predefined responses for different prompt patterns.

  ## Features

  - **Pattern-based responses**: Configure responses for specific prompt patterns
  - **Default fallback**: Provides realistic default responses for unmatched prompts
  - **Integration testing**: Seamlessly integrates with the main SDK for testing
  - **Cost-free development**: Enables development without incurring API costs

  ## Usage

  Start the mock server and configure responses:

      {:ok, _pid} = ClaudeAgentSDK.Mock.start_link()
      
      # Set up a specific response
      ClaudeAgentSDK.Mock.set_response("hello", [
        %{"type" => "system", "subtype" => "init", "session_id" => "mock-123"},
        %{"type" => "assistant", "message" => %{"content" => "Hello from mock!"}},
        %{"type" => "result", "subtype" => "success", "total_cost_usd" => 0.001}
      ])

  Enable mocking in your application configuration:

      Application.put_env(:claude_agent_sdk, :use_mock, true)

  ## Response Format

  Mock responses should follow the same format as the actual Claude CLI output:
  - Each response is a list of message maps
  - Each message has a "type" field (system, assistant, user, result)
  - Messages may include optional "subtype" fields for categorization
  - Result messages should include cost and timing information for realistic testing

  ## Testing Integration

  The mock system is designed to work seamlessly with testing frameworks:

      test "queries return expected responses" do
        ClaudeAgentSDK.Mock.set_response("test prompt", expected_messages)
        
        result = ClaudeAgentSDK.query("test prompt", options)
        
        assert length(Enum.to_list(result)) == length(expected_messages)
      end
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc """
  Starts the mock server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec set_response(String.t(), list(map())) :: :ok
  @doc """
  Sets a mock response for a given prompt pattern.

  ## Examples

      ClaudeAgentSDK.Mock.set_response("Hello", [
        %{type: "system", subtype: "init", session_id: "mock-123"},
        %{type: "assistant", message: %{"content" => "Hello from mock!"}},
        %{type: "result", subtype: "success", total_cost_usd: 0.001}
      ])
  """
  def set_response(prompt_pattern, messages) do
    GenServer.call(__MODULE__, {:set_response, prompt_pattern, messages})
  end

  @spec clear_responses() :: :ok
  @doc """
  Clears all mock responses.
  """
  def clear_responses do
    GenServer.call(__MODULE__, :clear_responses)
  end

  @spec get_response(String.t()) :: list(map())
  @doc """
  Gets the response for a prompt.
  """
  def get_response(prompt) do
    GenServer.call(__MODULE__, {:get_response, prompt})
  end

  @spec set_default_response(list(map())) :: :ok
  @doc """
  Sets the default response for any unmatched prompt.
  """
  def set_default_response(messages) do
    GenServer.call(__MODULE__, {:set_default_response, messages})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{responses: %{}, default_response: default_messages()}}
  end

  @impl true
  def handle_call({:set_response, pattern, messages}, _from, state) do
    new_state = %{state | responses: Map.put(state.responses, pattern, messages)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:clear_responses, _from, state) do
    # Reset to initial state with default messages
    {:reply, :ok, %{state | responses: %{}, default_response: default_messages()}}
  end

  @impl true
  def handle_call({:get_response, prompt}, _from, state) do
    # Find the first pattern that matches the prompt
    response =
      case Enum.find(state.responses, fn {pattern, _messages} ->
             String.contains?(prompt, pattern)
           end) do
        {_pattern, messages} -> messages
        nil -> state.default_response
      end

    {:reply, response, state}
  end

  @impl true
  def handle_call({:set_default_response, messages}, _from, state) do
    {:reply, :ok, %{state | default_response: messages}}
  end

  # Default messages that simulate a typical Claude response
  defp default_messages do
    [
      %{
        "type" => "system",
        "subtype" => "init",
        "session_id" => "mock-session-#{:rand.uniform(10000)}",
        "cwd" => "/mock/dir",
        "tools" => ["bash", "editor"],
        "model" => ClaudeAgentSDK.Model.default_model(),
        "permissionMode" => "default",
        "apiKeySource" => "mock"
      },
      %{
        "type" => "assistant",
        "message" => %{
          "role" => "assistant",
          "content" => "This is a mock response. Your prompt was received."
        },
        "session_id" => "mock-session"
      },
      %{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "mock-session",
        "result" => "Task completed",
        "total_cost_usd" => 0.001,
        "duration_ms" => 100,
        "duration_api_ms" => 50,
        "num_turns" => 1,
        "is_error" => false
      }
    ]
  end
end
