defmodule ClaudeAgentSDK.Query do
  @moduledoc """
  Handles querying Claude Code and processing responses.

  This module is responsible for building the appropriate command-line arguments
  for different types of Claude Code queries (new queries, continuations, and
  resumptions) and delegating to the CLI streaming transport for execution.

  All functions in this module return a Stream of `ClaudeAgentSDK.Message` structs.

  ## SDK MCP Server Support

  When SDK MCP servers are detected in options, the query automatically uses
  the Client GenServer (which supports bidirectional control protocol) instead
  of the simpler Process.stream approach. This is transparent to the caller -
  you still get the same Stream interface.
  """

  alias ClaudeAgentSDK.Config
  alias ClaudeAgentSDK.Config.CLI, as: CLIConfig
  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Query.ClientStream
  alias ClaudeAgentSDK.Transport.StreamingRouter

  @doc """
  Runs a new query with the given prompt and options.

  Automatically detects if SDK MCP servers are present in options and routes
  to the appropriate backend:
  - SDK MCP servers present → Uses Client GenServer (bidirectional control protocol)
  - No SDK MCP servers → Uses CLI-only streaming transport (unidirectional)

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
  @spec run(String.t() | Enumerable.t(), Options.t(), term() | nil) ::
          Enumerable.t(ClaudeAgentSDK.Message.t())
  def run(prompt, %Options{} = options, transport \\ nil) do
    options = validate_permission_settings!(prompt, options)

    if control_client_required?(options) do
      # Use Client GenServer when control protocol features are present
      client_stream_module().stream(prompt, options, transport)
    else
      # Use CLI-only streaming for non-control queries
      cli_stream_module().stream(prompt, options, transport)
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
    if control_client_required?(options) do
      opts = %{options | continue_conversation: true}
      client_stream_module().stream(prompt, opts)
    else
      base_args = stream_json_args(options)

      args =
        if prompt do
          ["--continue"] ++ base_args ++ ["--", prompt]
        else
          ["--continue"] ++ base_args
        end

      cli_stream_module().stream_args(args, options)
    end
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
    if control_client_required?(options) do
      opts = %{options | resume: session_id}
      client_stream_module().stream(prompt, opts)
    else
      base_args = stream_json_args(options)

      args =
        if prompt do
          ["--resume", session_id, "--input-format", "stream-json"] ++ base_args
        else
          ["--resume", session_id] ++ base_args
        end

      input = resume_input(prompt, session_id)
      cli_stream_module().stream_args(args, options, nil, input)
    end
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

  defp cli_stream_module do
    Config.cli_stream_module()
  end

  defp stream_json_args(%Options{} = options) do
    CLIConfig.streaming_output_args() ++ Options.to_stream_json_args(options)
  end

  defp validate_permission_settings!(_prompt, %Options{} = options) do
    if options.can_use_tool do
      if options.permission_prompt_tool do
        raise ArgumentError,
              "can_use_tool cannot be combined with permission_prompt_tool. Use one or the other."
      end

      # can_use_tool triggers control_client which handles both string and streaming prompts
      options
      |> maybe_enable_partial_messages()
    else
      options
    end
  end

  defp maybe_enable_partial_messages(%Options{include_partial_messages: nil} = options) do
    %Options{options | include_partial_messages: true}
  end

  defp maybe_enable_partial_messages(options), do: options

  defp resume_input(nil, _session_id), do: nil

  defp resume_input(prompt, _session_id) when is_binary(prompt) do
    [
      %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => prompt
        }
      }
    ]
  end
end
