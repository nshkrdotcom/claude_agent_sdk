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

  alias ClaudeAgentSDK.{Options, Query, SDKMCP}
  alias ClaudeAgentSDK.Session.History
  alias ClaudeAgentSDK.SessionStore

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
  @spec query(String.t() | Enumerable.t(), Options.t() | nil, term() | nil) ::
          Enumerable.t(ClaudeAgentSDK.Message.t())
  def query(prompt, options \\ nil, transport \\ nil) do
    opts = options || %Options{}
    Query.run(prompt, opts, transport)
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
  Lists Claude CLI transcript sessions.

  This mirrors the official Agent SDK `list_sessions()` surface and reads the
  CLI's on-disk JSONL history under `~/.claude/projects`.
  """
  @spec list_sessions(keyword()) :: [ClaudeAgentSDK.Session.SessionInfo.t()]
  def list_sessions(opts \\ []) do
    History.list_sessions(opts)
  end

  @doc """
  Reads visible user/assistant messages from a Claude CLI transcript session.
  """
  @spec get_session_messages(String.t(), keyword()) :: [ClaudeAgentSDK.Session.SessionMessage.t()]
  def get_session_messages(session_id, opts \\ []) do
    History.get_session_messages(session_id, opts)
  end

  @doc """
  Looks up metadata for a single CLI transcript session.
  """
  @spec get_session_info(String.t(), keyword()) :: ClaudeAgentSDK.Session.SessionInfo.t() | nil
  def get_session_info(session_id, opts \\ []) do
    History.get_session_info(session_id, opts)
  end

  @doc """
  Appends a custom title entry to a CLI transcript session.
  """
  @spec rename_session(String.t(), String.t(), keyword()) :: :ok
  def rename_session(session_id, title, opts \\ []) do
    History.rename_session(session_id, title, opts)
  end

  @doc """
  Appends or clears a tag entry on a CLI transcript session.
  """
  @spec tag_session(String.t(), String.t() | nil, keyword()) :: :ok
  def tag_session(session_id, tag, opts \\ []) do
    History.tag_session(session_id, tag, opts)
  end

  @doc """
  Deletes a CLI transcript session and its subagent transcript directory.
  """
  @spec delete_session(String.t(), keyword()) :: :ok
  def delete_session(session_id, opts \\ []) do
    History.delete_session(session_id, opts)
  end

  @doc """
  Forks a CLI transcript session into a new local session file.
  """
  @spec fork_session(String.t(), keyword()) :: ClaudeAgentSDK.Session.ForkResult.t()
  def fork_session(session_id, opts \\ []) do
    History.fork_session(session_id, opts)
  end

  @doc """
  Lists subagent IDs for a CLI transcript session.
  """
  @spec list_subagents(String.t(), keyword()) :: [String.t()]
  def list_subagents(session_id, opts \\ []) do
    History.list_subagents(session_id, opts)
  end

  @doc """
  Reads visible messages from a subagent transcript.
  """
  @spec get_subagent_messages(String.t(), String.t(), keyword()) :: [
          ClaudeAgentSDK.Session.SessionMessage.t()
        ]
  def get_subagent_messages(session_id, agent_id, opts \\ []) do
    History.get_subagent_messages(session_id, agent_id, opts)
  end

  @doc """
  Derives the SessionStore project key for a directory.
  """
  @spec project_key_for_directory(String.t() | nil) :: String.t()
  def project_key_for_directory(directory \\ nil),
    do: SessionStore.project_key_for_directory(directory)

  @doc """
  Imports a local Claude JSONL session transcript into a SessionStore adapter.
  """
  @spec import_session_to_store(String.t(), term(), keyword()) :: :ok | {:error, term()}
  def import_session_to_store(session_id, store, opts \\ []),
    do: SessionStore.import_session_to_store(session_id, store, opts)

  @doc """
  Lists SessionStore-backed sessions.
  """
  @spec list_sessions_from_store(term(), keyword()) :: [ClaudeAgentSDK.Session.SessionInfo.t()]
  def list_sessions_from_store(store, opts \\ []),
    do: SessionStore.list_sessions_from_store(store, opts)

  @doc """
  Looks up SessionStore-backed session metadata.
  """
  @spec get_session_info_from_store(String.t(), term(), keyword()) ::
          ClaudeAgentSDK.Session.SessionInfo.t() | nil
  def get_session_info_from_store(session_id, store, opts \\ []),
    do: SessionStore.get_session_info_from_store(session_id, store, opts)

  @doc """
  Reads visible messages from a SessionStore-backed session.
  """
  @spec get_session_messages_from_store(String.t(), term(), keyword()) :: [
          ClaudeAgentSDK.Session.SessionMessage.t()
        ]
  def get_session_messages_from_store(session_id, store, opts \\ []),
    do: SessionStore.get_session_messages_from_store(session_id, store, opts)

  @doc """
  Lists subagents in a SessionStore-backed session.
  """
  @spec list_subagents_from_store(String.t(), term(), keyword()) :: [String.t()]
  def list_subagents_from_store(session_id, store, opts \\ []),
    do: SessionStore.list_subagents_from_store(session_id, store, opts)

  @doc """
  Reads visible messages from a SessionStore-backed subagent transcript.
  """
  @spec get_subagent_messages_from_store(String.t(), String.t(), term(), keyword()) :: [
          ClaudeAgentSDK.Session.SessionMessage.t()
        ]
  def get_subagent_messages_from_store(session_id, agent_id, store, opts \\ []),
    do: SessionStore.get_subagent_messages_from_store(session_id, agent_id, store, opts)

  @doc """
  Appends a custom title entry to a SessionStore-backed session.
  """
  @spec rename_session_via_store(String.t(), String.t(), term(), keyword()) ::
          :ok | {:error, term()}
  def rename_session_via_store(session_id, title, store, opts \\ []),
    do: SessionStore.rename_session_via_store(session_id, title, store, opts)

  @doc """
  Appends or clears a tag on a SessionStore-backed session.
  """
  @spec tag_session_via_store(String.t(), String.t() | nil, term(), keyword()) ::
          :ok | {:error, term()}
  def tag_session_via_store(session_id, tag, store, opts \\ []),
    do: SessionStore.tag_session_via_store(session_id, tag, store, opts)

  @doc """
  Deletes a SessionStore-backed session when supported by the adapter.
  """
  @spec delete_session_via_store(String.t(), term(), keyword()) :: :ok | {:error, term()}
  def delete_session_via_store(session_id, store, opts \\ []),
    do: SessionStore.delete_session_via_store(session_id, store, opts)

  @doc """
  Forks a SessionStore-backed session into a new session.
  """
  @spec fork_session_via_store(String.t(), term(), keyword()) ::
          ClaudeAgentSDK.Session.ForkResult.t() | {:error, term()}
  def fork_session_via_store(session_id, store, opts \\ []),
    do: SessionStore.fork_session_via_store(session_id, store, opts)

  @doc """
  Lists SDK-managed sessions from `ClaudeAgentSDK.SessionStore`.

  Starts the SessionStore automatically when needed.
  """
  @spec list_saved_sessions(keyword()) ::
          {:ok, [ClaudeAgentSDK.SessionStore.session_metadata()]} | {:error, term()}
  def list_saved_sessions(opts \\ []) do
    with :ok <- ensure_session_store_started(opts) do
      {:ok, ClaudeAgentSDK.SessionStore.list_sessions()}
    end
  end

  defp ensure_session_store_started(opts) do
    case ClaudeAgentSDK.SessionStore.start_link(opts) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
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
  - `:version` - Server version (defaults to "1.0.0")
  - `:registry_pid` - PID of the tool registry GenServer

  When `:supervisor` is omitted, the registry runs under the SDK's internal
  SDK MCP supervisor, so it stays alive independently of the creating process.

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
    version = Keyword.get(opts, :version, "1.0.0")
    tools = Keyword.get(opts, :tools, [])
    supervisor = Keyword.get(opts, :supervisor)

    # Start a registry for this server
    registry_pid = start_sdk_registry(supervisor)

    # Register all tools
    for tool_module <- tools do
      # Ensure module is loaded before checking exports
      Code.ensure_loaded!(tool_module)

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

  defp start_sdk_registry(nil) do
    SDKMCP.Supervisor.start_registry()
  end

  defp start_sdk_registry(supervisor) do
    SDKMCP.Supervisor.start_registry(supervisor)
  end
end
