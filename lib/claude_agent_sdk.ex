defmodule ClaudeAgentSDK do
  @moduledoc """
  An Elixir SDK for Claude Code.

  This module provides a simple interface for interacting with Claude Code programmatically.

  ## Basic Usage

      # Simple query
      for message <- ClaudeAgentSDK.query("Write a hello world function") do
        IO.inspect(message)
      end

      # With options
      opts = %ClaudeAgentSDK.Options{
        max_turns: 3,
        output_format: :json,
        system_prompt: "You are a helpful assistant"
      }
      
      for message <- ClaudeAgentSDK.query("Build a REST API", opts) do
        IO.inspect(message)
      end

  ## Authentication

  This SDK uses the already-authenticated Claude CLI. You must authenticate manually first:

      # In your terminal:
      claude login

  The SDK will use the stored authentication from your interactive Claude session.
  """

  alias ClaudeAgentSDK.{Options, Query}

  @doc """
  Runs a query against Claude Code and returns a stream of messages.

  ## Parameters

    * `prompt` - The prompt to send to Claude
    * `options` - Optional `ClaudeAgentSDK.Options` struct with configuration

  ## Returns

  Returns a `Stream` that yields `ClaudeAgentSDK.Message` structs.

  ## Examples

      # Simple query
      ClaudeAgentSDK.query("Write a function to calculate Fibonacci numbers")
      |> Enum.to_list()

      # With options
      opts = %ClaudeAgentSDK.Options{max_turns: 5}
      ClaudeAgentSDK.query("Build a web server", opts)
      |> Enum.to_list()
  """
  @spec query(String.t(), Options.t() | nil) :: Enumerable.t(ClaudeAgentSDK.Message.t())
  def query(prompt, options \\ nil) do
    opts = options || %Options{}
    Query.run(prompt, opts)
  end

  @doc """
  Continues the most recent conversation.

  ## Parameters

    * `prompt` - Optional new prompt to add to the conversation
    * `options` - Optional `ClaudeAgentSDK.Options` struct with configuration

  ## Examples

      # Continue without new prompt
      ClaudeAgentSDK.continue()
      |> Enum.to_list()

      # Continue with new prompt
      ClaudeAgentSDK.continue("Now add error handling")
      |> Enum.to_list()
  """
  @spec continue(String.t() | nil, Options.t() | nil) :: Enumerable.t(ClaudeAgentSDK.Message.t())
  def continue(prompt \\ nil, options \\ nil) do
    opts = options || %Options{}
    Query.continue(prompt, opts)
  end

  @doc """
  Resumes a specific conversation by session ID.

  ## Parameters

    * `session_id` - The session ID to resume
    * `prompt` - Optional new prompt to add to the conversation
    * `options` - Optional `ClaudeAgentSDK.Options` struct with configuration

  ## Examples

      ClaudeAgentSDK.resume("550e8400-e29b-41d4-a716-446655440000", "Add tests")
      |> Enum.to_list()
  """
  @spec resume(String.t(), String.t() | nil, Options.t() | nil) ::
          Enumerable.t(ClaudeAgentSDK.Message.t())
  def resume(session_id, prompt \\ nil, options \\ nil) do
    opts = options || %Options{}
    Query.resume(session_id, prompt, opts)
  end
end
