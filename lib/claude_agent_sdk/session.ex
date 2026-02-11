defmodule ClaudeAgentSDK.Session do
  @moduledoc """
  Helper functions for working with Claude sessions.

  Provides utilities to extract session metadata from message lists.
  """

  alias ClaudeAgentSDK.Message

  @doc """
  Extracts the session ID from a list of messages.

  ## Examples

      messages = ClaudeAgentSDK.query("Hello") |> Enum.to_list()
      session_id = ClaudeAgentSDK.Session.extract_session_id(messages)
      # => "550e8400-e29b-41d4-a716-446655440000"
  """
  @spec extract_session_id([Message.t()]) :: String.t() | nil
  def extract_session_id(messages) do
    messages
    |> Enum.find(&(&1.type == :system))
    |> case do
      %{data: %{session_id: id}} -> id
      %{data: data} when is_map(data) -> data["session_id"]
      _ -> nil
    end
  end

  @doc """
  Calculates total cost from messages.

  ## Examples

      messages = ClaudeAgentSDK.query("Analyze code") |> Enum.to_list()
      cost = ClaudeAgentSDK.Session.calculate_cost(messages)
      # => 0.025
  """
  @spec calculate_cost([Message.t()]) :: float()
  def calculate_cost(messages) do
    messages
    |> Enum.find(&(&1.type == :result))
    |> case do
      %{data: %{total_cost_usd: cost}} -> cost
      %{data: data} when is_map(data) -> data["total_cost_usd"] || 0.0
      _ -> 0.0
    end
  end

  @doc """
  Counts conversation turns (assistant messages).

  ## Examples

      messages = ClaudeAgentSDK.query("Multi-step task") |> Enum.to_list()
      turns = ClaudeAgentSDK.Session.count_turns(messages)
      # => 5
  """
  @spec count_turns([Message.t()]) :: non_neg_integer()
  def count_turns(messages) do
    Enum.count(messages, &(&1.type == :assistant))
  end

  @doc """
  Extracts the model used from messages.

  ## Examples

      messages = ClaudeAgentSDK.query("Hello") |> Enum.to_list()
      model = ClaudeAgentSDK.Session.extract_model(messages)
      # => "sonnet"
  """
  @spec extract_model([Message.t()]) :: String.t() | nil
  def extract_model(messages) do
    messages
    |> Enum.find(&(&1.type == :system))
    |> case do
      %{data: %{model: model}} -> model
      %{data: data} when is_map(data) -> data["model"]
      _ -> nil
    end
  end

  @doc """
  Gets a summary of the conversation.

  Returns first assistant message (truncated to 200 chars).

  ## Examples

      messages = ClaudeAgentSDK.query("Build feature") |> Enum.to_list()
      summary = ClaudeAgentSDK.Session.get_summary(messages)
      # => "I'll help you build that feature. First, let me..."
  """
  @spec get_summary([Message.t()]) :: String.t()
  def get_summary(messages) do
    messages
    |> Enum.find(&(&1.type == :assistant))
    |> case do
      nil ->
        "No response"

      message ->
        ClaudeAgentSDK.ContentExtractor.extract_text(message)
        |> String.slice(0, 200)
    end
  end
end
