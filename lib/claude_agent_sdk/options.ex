defmodule ClaudeAgentSDK.Options do
  @moduledoc """
  Configuration options for Claude Code SDK requests.

  This struct defines all available options that can be passed to Claude Code CLI.
  All fields are optional and will be omitted from the CLI command if not provided.

  ## Fields

  - `max_turns` - Maximum number of conversation turns (integer)
  - `system_prompt` - Custom system prompt to use (string)
  - `append_system_prompt` - Additional system prompt to append (string)
  - `output_format` - Output format (`:text`, `:json`, or `:stream_json`)
  - `allowed_tools` - List of allowed tool names (list of strings)
  - `disallowed_tools` - List of disallowed tool names (list of strings)
  - `mcp_config` - Path to MCP configuration file (string)
  - `permission_prompt_tool` - Tool for permission prompts (string)
  - `permission_mode` - Permission handling mode (see `t:permission_mode/0`)
  - `cwd` - Working directory for the CLI (string)
  - `verbose` - Enable verbose output (boolean)
  - `executable` - Custom executable to run (string)
  - `executable_args` - Arguments for custom executable (list of strings)
  - `path_to_claude_code_executable` - Path to Claude Code CLI (string)
  - `abort_ref` - Reference for aborting requests (reference)
  - `hooks` - Hook configurations (see `t:ClaudeAgentSDK.Hooks.hook_config/0`)

  ## Examples

      # Basic configuration
      %ClaudeAgentSDK.Options{
        max_turns: 5,
        output_format: :stream_json,
        verbose: true
      }

      # Advanced configuration
      %ClaudeAgentSDK.Options{
        system_prompt: "You are a helpful coding assistant",
        allowed_tools: ["editor", "bash"],
        permission_mode: :accept_edits,
        cwd: "/path/to/project"
      }

  """

  defstruct [
    :max_turns,
    :system_prompt,
    :append_system_prompt,
    :output_format,
    :allowed_tools,
    :disallowed_tools,
    :mcp_config,
    :permission_prompt_tool,
    :permission_mode,
    :cwd,
    :verbose,
    :executable,
    :executable_args,
    :path_to_claude_code_executable,
    :abort_ref,
    # New fields for v0.1.0
    # Model selection ("opus", "sonnet", "haiku", or full name)
    :model,
    # Fallback model when primary is busy
    :fallback_model,
    # Custom agent definitions
    :agents,
    # Explicit session ID (UUID)
    :session_id,
    # Quick wins (v0.2.0)
    # Create new session ID when resuming
    :fork_session,
    # Additional directories for tool access
    :add_dir,
    # Only use MCP servers from --mcp-config
    :strict_mcp_config,
    # Hooks (v0.3.0)
    # Hook callbacks for lifecycle events
    :hooks
  ]

  @type output_format :: :text | :json | :stream_json
  @type permission_mode :: :default | :accept_edits | :bypass_permissions | :plan
  @type model_name :: String.t()
  @type agent_name :: String.t()
  @type agent_definition :: %{
          description: String.t(),
          prompt: String.t()
        }

  @type t :: %__MODULE__{
          max_turns: integer() | nil,
          system_prompt: String.t() | nil,
          append_system_prompt: String.t() | nil,
          output_format: output_format() | nil,
          allowed_tools: [String.t()] | nil,
          disallowed_tools: [String.t()] | nil,
          mcp_config: String.t() | nil,
          permission_prompt_tool: String.t() | nil,
          permission_mode: permission_mode() | nil,
          cwd: String.t() | nil,
          verbose: boolean() | nil,
          executable: String.t() | nil,
          executable_args: [String.t()] | nil,
          path_to_claude_code_executable: String.t() | nil,
          abort_ref: reference() | nil,
          model: model_name() | nil,
          fallback_model: model_name() | nil,
          agents: %{agent_name() => agent_definition()} | nil,
          session_id: String.t() | nil,
          fork_session: boolean() | nil,
          add_dir: [String.t()] | nil,
          strict_mcp_config: boolean() | nil,
          hooks: ClaudeAgentSDK.Hooks.hook_config() | nil
        }

  @doc """
  Creates a new Options struct with the given attributes.

  ## Parameters

  - `attrs` - Keyword list of attributes to set (keyword list)

  ## Returns

  A new `t:ClaudeAgentSDK.Options.t/0` struct with the specified attributes.

  ## Examples

      ClaudeAgentSDK.Options.new(
        max_turns: 5,
        output_format: :json,
        verbose: true
      )

      # Empty options (all defaults)
      ClaudeAgentSDK.Options.new()

  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Converts the options to command line arguments for the Claude CLI.

  ## Parameters

  - `options` - The options struct to convert

  ## Returns

  A list of strings representing CLI arguments.

  ## Examples

      options = %ClaudeAgentSDK.Options{max_turns: 5, verbose: true}
      ClaudeAgentSDK.Options.to_args(options)
      # => ["--max-turns", "5", "--verbose"]

  """
  @spec to_args(t()) :: [String.t()]
  def to_args(%__MODULE__{} = options) do
    []
    |> add_output_format_args(options)
    |> add_max_turns_args(options)
    |> add_system_prompt_args(options)
    |> add_append_system_prompt_args(options)
    |> add_allowed_tools_args(options)
    |> add_disallowed_tools_args(options)
    |> add_mcp_config_args(options)
    |> add_permission_prompt_tool_args(options)
    |> add_permission_mode_args(options)
    |> add_verbose_args(options)
    |> add_model_args(options)
    |> add_fallback_model_args(options)
    |> add_agents_args(options)
    |> add_session_id_args(options)
    |> add_fork_session_args(options)
    |> add_dir_args(options)
    |> add_strict_mcp_args(options)
  end

  defp add_output_format_args(args, %{output_format: nil}), do: args

  defp add_output_format_args(args, %{output_format: format}) do
    # Convert format atom to CLI string format
    format_string =
      case format do
        :stream_json -> "stream-json"
        other -> to_string(other)
      end

    format_args = ["--output-format", format_string]
    # CLI requires --verbose when using stream-json with --print
    if format == :stream_json do
      args ++ format_args ++ ["--verbose"]
    else
      args ++ format_args
    end
  end

  defp add_max_turns_args(args, %{max_turns: nil}), do: args

  defp add_max_turns_args(args, %{max_turns: turns}),
    do: args ++ ["--max-turns", to_string(turns)]

  defp add_system_prompt_args(args, %{system_prompt: nil}), do: args

  defp add_system_prompt_args(args, %{system_prompt: prompt}),
    do: args ++ ["--system-prompt", prompt]

  defp add_append_system_prompt_args(args, %{append_system_prompt: nil}), do: args

  defp add_append_system_prompt_args(args, %{append_system_prompt: prompt}),
    do: args ++ ["--append-system-prompt", prompt]

  defp add_allowed_tools_args(args, %{allowed_tools: nil}), do: args

  defp add_allowed_tools_args(args, %{allowed_tools: tools}),
    do: args ++ ["--allowedTools", Enum.join(tools, " ")]

  defp add_disallowed_tools_args(args, %{disallowed_tools: nil}), do: args

  defp add_disallowed_tools_args(args, %{disallowed_tools: tools}),
    do: args ++ ["--disallowedTools", Enum.join(tools, " ")]

  defp add_mcp_config_args(args, %{mcp_config: nil}), do: args
  defp add_mcp_config_args(args, %{mcp_config: config}), do: args ++ ["--mcp-config", config]

  defp add_permission_prompt_tool_args(args, %{permission_prompt_tool: nil}), do: args

  defp add_permission_prompt_tool_args(args, %{permission_prompt_tool: tool}),
    do: args ++ ["--permission-prompt-tool", tool]

  defp add_permission_mode_args(args, %{permission_mode: nil}), do: args

  defp add_permission_mode_args(args, %{permission_mode: mode}) do
    # Convert permission mode atom to CLI string format
    mode_string =
      case mode do
        :accept_edits -> "acceptEdits"
        :bypass_permissions -> "bypassPermissions"
        other -> to_string(other)
      end

    args ++ ["--permission-mode", mode_string]
  end

  defp add_verbose_args(args, %{verbose: true}), do: args ++ ["--verbose"]
  defp add_verbose_args(args, _), do: args

  defp add_model_args(args, %{model: nil}), do: args
  defp add_model_args(args, %{model: model}), do: args ++ ["--model", model]

  defp add_fallback_model_args(args, %{fallback_model: nil}), do: args

  defp add_fallback_model_args(args, %{fallback_model: model}),
    do: args ++ ["--fallback-model", model]

  defp add_agents_args(args, %{agents: nil}), do: args

  defp add_agents_args(args, %{agents: agents}) do
    # Convert agents map to JSON format expected by CLI
    json = Jason.encode!(agents)
    args ++ ["--agents", json]
  end

  defp add_session_id_args(args, %{session_id: nil}), do: args
  defp add_session_id_args(args, %{session_id: id}), do: args ++ ["--session-id", id]

  defp add_fork_session_args(args, %{fork_session: true}), do: args ++ ["--fork-session"]
  defp add_fork_session_args(args, _), do: args

  defp add_dir_args(args, %{add_dir: nil}), do: args

  defp add_dir_args(args, %{add_dir: directories}) when is_list(directories) do
    args ++ ["--add-dir"] ++ directories
  end

  defp add_strict_mcp_args(args, %{strict_mcp_config: true}), do: args ++ ["--strict-mcp-config"]
  defp add_strict_mcp_args(args, _), do: args
end
