defmodule ClaudeCodeSDK.Query do
  @moduledoc """
  Handles querying Claude Code and processing responses.

  This module is responsible for building the appropriate command-line arguments
  for different types of Claude Code queries (new queries, continuations, and
  resumptions) and delegating to the Process module for execution.

  All functions in this module return a Stream of `ClaudeCodeSDK.Message` structs.
  """

  alias ClaudeCodeSDK.{Options, Process}

  @doc """
  Runs a new query with the given prompt and options.

  ## Parameters

  - `prompt` - The prompt to send to Claude (string)
  - `options` - Configuration options (see `t:ClaudeCodeSDK.Options.t/0`)

  ## Returns

  A stream of `t:ClaudeCodeSDK.Message.t/0` structs.

  ## Examples

      ClaudeCodeSDK.Query.run("Write a hello world function", %ClaudeCodeSDK.Options{})

  """
  @spec run(String.t(), Options.t()) :: Enumerable.t(ClaudeCodeSDK.Message.t())
  def run(prompt, %Options{} = options) do
    {args, stdin_prompt} = build_args(prompt, options)
    Process.stream(args, options, stdin_prompt)
  end

  @doc """
  Continues the most recent conversation.

  ## Parameters

  - `prompt` - Optional additional prompt to send (string or nil)
  - `options` - Configuration options (see `t:ClaudeCodeSDK.Options.t/0`)

  ## Returns

  A stream of `t:ClaudeCodeSDK.Message.t/0` structs.

  ## Examples

      ClaudeCodeSDK.Query.continue("Add error handling", %ClaudeCodeSDK.Options{})

  """
  @spec continue(String.t() | nil, Options.t()) :: Enumerable.t(ClaudeCodeSDK.Message.t())
  def continue(prompt, %Options{} = options) do
    base_args = Options.to_args(options)
    # For continue, we need to ensure --print is included if we have a prompt
    args =
      if prompt do
        ["--print", "--continue"] ++ Enum.reject(base_args, &(&1 == "--print"))
      else
        ["--continue"] ++ base_args
      end

    Process.stream(args, options, prompt)
  end

  @doc """
  Resumes a specific conversation by session ID.

  ## Parameters

  - `session_id` - The session ID to resume (string)
  - `prompt` - Optional additional prompt to send (string or nil)
  - `options` - Configuration options (see `t:ClaudeCodeSDK.Options.t/0`)

  ## Returns

  A stream of `t:ClaudeCodeSDK.Message.t/0` structs.

  ## Examples

      ClaudeCodeSDK.Query.resume("session-123", "Add tests", %ClaudeCodeSDK.Options{})

  """
  @spec resume(String.t(), String.t() | nil, Options.t()) ::
          Enumerable.t(ClaudeCodeSDK.Message.t())
  def resume(session_id, prompt, %Options{} = options) do
    base_args = Options.to_args(options)
    # For resume, we need to ensure --print is included if we have a prompt
    args =
      if prompt do
        ["--print", "--resume", session_id] ++ Enum.reject(base_args, &(&1 == "--print"))
      else
        ["--resume", session_id] ++ base_args
      end

    Process.stream(args, options, prompt)
  end

  defp build_args(prompt, options) do
    # Add --print to run non-interactively
    # The prompt needs to be passed separately since --print expects stdin input
    {["--print"] ++ Options.to_args(options), prompt}
  end
end
