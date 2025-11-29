defmodule ClaudeAgentSDK.Query do
  @moduledoc """
  Handles querying Claude Code and processing responses.

  This module is responsible for building the appropriate command-line arguments
  for different types of Claude Code queries (new queries, continuations, and
  resumptions) and delegating to the Process module for execution.

  All functions in this module return a Stream of `ClaudeAgentSDK.Message` structs.

  ## SDK MCP Server Support

  When SDK MCP servers are detected in options, the query automatically uses
  the Client GenServer (which supports bidirectional control protocol) instead
  of the simpler Process.stream approach. This is transparent to the caller -
  you still get the same Stream interface.
  """

  alias ClaudeAgentSDK.{Options, Process}
  alias ClaudeAgentSDK.Query.ClientStream
  alias ClaudeAgentSDK.Transport.StreamingRouter

  @doc """
  Runs a new query with the given prompt and options.

  Automatically detects if SDK MCP servers are present in options and routes
  to the appropriate backend:
  - SDK MCP servers present → Uses Client GenServer (bidirectional control protocol)
  - No SDK MCP servers → Uses Process.stream (simple unidirectional streaming)

  ## Parameters

  - `prompt` - The prompt to send to Claude (string)
  - `options` - Configuration options (see `t:ClaudeAgentSDK.Options.t/0`)

  ## Returns

  A stream of `t:ClaudeAgentSDK.Message.t/0` structs.

  ## Examples

      # Simple query (no SDK MCP)
      ClaudeAgentSDK.Query.run("Write a hello world function", %ClaudeAgentSDK.Options{})

      # With SDK MCP servers (auto-uses Client)
      server = ClaudeAgentSDK.create_sdk_mcp_server(name: "math", tools: [Add])
      options = %Options{mcp_servers: %{"math" => server}}
      ClaudeAgentSDK.Query.run("What is 2+2?", options)

  """
  @spec run(String.t(), Options.t()) :: Enumerable.t(ClaudeAgentSDK.Message.t())
  def run(prompt, %Options{} = options) do
    if control_client_required?(options) do
      # Use Client GenServer when control protocol features are present
      client_stream_module().stream(prompt, options)
    else
      # Use simple Process.stream for non-SDK-MCP queries
      {args, stdin_prompt} = build_args(prompt, options)
      process_module().stream(args, options, stdin_prompt)
    end
  end

  @doc """
  Continues the most recent conversation.

  ## Parameters

  - `prompt` - Optional additional prompt to send (string or nil)
  - `options` - Configuration options (see `t:ClaudeAgentSDK.Options.t/0`)

  ## Returns

  A stream of `t:ClaudeAgentSDK.Message.t/0` structs.

  ## Examples

      ClaudeAgentSDK.Query.continue("Add error handling", %ClaudeAgentSDK.Options{})

  """
  @spec continue(String.t() | nil, Options.t()) :: Enumerable.t(ClaudeAgentSDK.Message.t())
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
  - `options` - Configuration options (see `t:ClaudeAgentSDK.Options.t/0`)

  ## Returns

  A stream of `t:ClaudeAgentSDK.Message.t/0` structs.

  ## Examples

      ClaudeAgentSDK.Query.resume("session-123", "Add tests", %ClaudeAgentSDK.Options{})

  """
  @spec resume(String.t(), String.t() | nil, Options.t()) ::
          Enumerable.t(ClaudeAgentSDK.Message.t())
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

  # Check if options contain SDK MCP servers
  @doc false
  @spec has_sdk_mcp_servers?(Options.t()) :: boolean()
  defp has_sdk_mcp_servers?(%Options{mcp_servers: nil}), do: false

  defp has_sdk_mcp_servers?(%Options{mcp_servers: servers}) when is_map(servers) do
    Enum.any?(servers, fn {_name, config} ->
      is_map(config) and Map.get(config, :type) == :sdk
    end)
  end

  defp control_client_required?(%Options{} = options) do
    has_sdk_mcp_servers?(options) or StreamingRouter.requires_control_protocol?(options)
  end

  defp client_stream_module do
    Application.get_env(:claude_agent_sdk, :client_stream_module, ClientStream)
  end

  defp process_module do
    Application.get_env(:claude_agent_sdk, :process_module, Process)
  end
end
