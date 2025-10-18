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

  @doc """
  Creates an SDK-based MCP server for in-process tool execution.

  Unlike external MCP servers that require separate processes, SDK servers
  run directly within your application, providing:
  - Better performance (no subprocess overhead)
  - Simpler deployment (no external dependencies)
  - Direct function calls to your tool implementations

  ## Parameters

  - `opts` - Keyword list with:
    - `:name` - Server name (string, required)
    - `:version` - Server version (string, required)
    - `:tools` - List of tool modules (list of atoms, required)

  ## Returns

  A map representing the SDK MCP server with:
  - `:type` - Always `:sdk`
  - `:name` - Server name
  - `:version` - Server version
  - `:registry_pid` - PID of the tool registry GenServer

  ## Examples

      defmodule MyTools do
        use ClaudeAgentSDK.Tool

        deftool :add, "Add two numbers", %{
          type: "object",
          properties: %{a: %{type: "number"}, b: %{type: "number"}},
          required: ["a", "b"]
        } do
          def execute(%{"a" => a, "b" => b}) do
            {:ok, %{"content" => [%{"type" => "text", "text" => "\#{a + b}"}]}}
          end
        end
      end

      # Create server
      server = ClaudeAgentSDK.create_sdk_mcp_server(
        name: "calculator",
        version: "1.0.0",
        tools: [MyTools.Add]
      )

      # Use in options
      options = %ClaudeAgentSDK.Options{
        mcp_servers: %{"calc" => server},
        allowed_tools: ["mcp__calc__add"]
      }

      ClaudeAgentSDK.query("Calculate 15 + 27", options)
  """
  @spec create_sdk_mcp_server(keyword()) :: %{
          type: :sdk,
          name: String.t(),
          version: String.t(),
          registry_pid: pid()
        }
  def create_sdk_mcp_server(opts) do
    name = Keyword.fetch!(opts, :name)
    version = Keyword.fetch!(opts, :version)
    tools = Keyword.get(opts, :tools, [])

    # Start a registry for this server
    {:ok, registry_pid} = ClaudeAgentSDK.Tool.Registry.start_link([])

    # Register all tools
    for tool_module <- tools do
      if function_exported?(tool_module, :__tool_metadata__, 0) do
        metadata = tool_module.__tool_metadata__()
        ClaudeAgentSDK.Tool.Registry.register_tool(registry_pid, metadata)
      else
        raise ArgumentError,
              "#{inspect(tool_module)} is not a valid tool module (missing __tool_metadata__/0)"
      end
    end

    %{
      type: :sdk,
      name: name,
      version: version,
      registry_pid: registry_pid
    }
  end
end
