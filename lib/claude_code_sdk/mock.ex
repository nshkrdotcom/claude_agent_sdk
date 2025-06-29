defmodule ClaudeCodeSDK.Mock do
  @moduledoc """
  Mock implementation for the Claude Code CLI for testing purposes.

  This module provides a way to mock CLI responses without making actual API calls.
  It can be configured with predefined responses for different prompts.
  """

  use GenServer

  @doc """
  Starts the mock server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sets a mock response for a given prompt pattern.

  ## Examples

      ClaudeCodeSDK.Mock.set_response("Hello", [
        %{type: "system", subtype: "init", session_id: "mock-123"},
        %{type: "assistant", message: %{"content" => "Hello from mock!"}},
        %{type: "result", subtype: "success", total_cost_usd: 0.001}
      ])
  """
  def set_response(prompt_pattern, messages) do
    GenServer.call(__MODULE__, {:set_response, prompt_pattern, messages})
  end

  @doc """
  Clears all mock responses.
  """
  def clear_responses do
    GenServer.call(__MODULE__, :clear_responses)
  end

  @doc """
  Gets the response for a prompt.
  """
  def get_response(prompt) do
    GenServer.call(__MODULE__, {:get_response, prompt})
  end

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
        "model" => "claude-3-opus-20240229",
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
