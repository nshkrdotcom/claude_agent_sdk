defmodule ClaudeCodeSDK.Query do
  @moduledoc """
  Handles querying Claude Code and processing responses.
  """

  alias ClaudeCodeSDK.{Options, Process}

  @doc """
  Runs a query with the given prompt and options.
  """
  def run(prompt, %Options{} = options) do
    args = build_args(prompt, options)
    Process.stream(args, options)
  end

  @doc """
  Continues the most recent conversation.
  """
  def continue(prompt, %Options{} = options) do
    base_args = Options.to_args(options)
    # For continue, we need to ensure --print is included if we have a prompt
    args = if prompt do
      ["--print", "--continue", prompt] ++ Enum.reject(base_args, & &1 == "--print")
    else
      ["--continue"] ++ base_args
    end
    Process.stream(args, options)
  end

  @doc """
  Resumes a specific conversation by session ID.
  """
  def resume(session_id, prompt, %Options{} = options) do
    base_args = Options.to_args(options)
    # For resume, we need to ensure --print is included if we have a prompt
    args = if prompt do
      ["--print", "--resume", session_id, prompt] ++ Enum.reject(base_args, & &1 == "--print")
    else
      ["--resume", session_id] ++ base_args
    end
    Process.stream(args, options)
  end

  defp build_args(prompt, options) do
    # Add --print to run non-interactively
    ["--print"] ++ Options.to_args(options) ++ [prompt]
  end
end