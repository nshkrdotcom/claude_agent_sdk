defmodule ClaudeCodeSDK.Options do
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

  ## Examples

      # Basic configuration
      %ClaudeCodeSDK.Options{
        max_turns: 5,
        output_format: :stream_json,
        verbose: true
      }

      # Advanced configuration
      %ClaudeCodeSDK.Options{
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
    :abort_ref
  ]

  @type output_format :: :text | :json | :stream_json
  @type permission_mode :: :default | :accept_edits | :bypass_permissions | :plan

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
          abort_ref: reference() | nil
        }

  @doc """
  Creates a new Options struct with the given attributes.

  ## Parameters

  - `attrs` - Keyword list of attributes to set (keyword list)

  ## Returns

  A new `ClaudeCodeSDK.Options.t/0` struct with the specified attributes.

  ## Examples

      ClaudeCodeSDK.Options.new(
        max_turns: 5,
        output_format: :json,
        verbose: true
      )

      # Empty options (all defaults)
      ClaudeCodeSDK.Options.new()

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

      options = %ClaudeCodeSDK.Options{max_turns: 5, verbose: true}
      ClaudeCodeSDK.Options.to_args(options)
      # => ["--max-turns", "5", "--verbose"]

  """
  @spec to_args(t()) :: [String.t()]
  def to_args(%__MODULE__{} = options) do
    args = []

    args =
      if options.output_format do
        format_args = ["--output-format", to_string(options.output_format)]
        # CLI requires --verbose when using stream-json with --print
        if options.output_format == :stream_json do
          args ++ format_args ++ ["--verbose"]
        else
          args ++ format_args
        end
      else
        args
      end

    args =
      if options.max_turns do
        args ++ ["--max-turns", to_string(options.max_turns)]
      else
        args
      end

    args =
      if options.system_prompt do
        args ++ ["--system-prompt", options.system_prompt]
      else
        args
      end

    args =
      if options.append_system_prompt do
        args ++ ["--append-system-prompt", options.append_system_prompt]
      else
        args
      end

    args =
      if options.allowed_tools do
        args ++ ["--allowedTools", Enum.join(options.allowed_tools, " ")]
      else
        args
      end

    args =
      if options.disallowed_tools do
        args ++ ["--disallowedTools", Enum.join(options.disallowed_tools, " ")]
      else
        args
      end

    args =
      if options.mcp_config do
        args ++ ["--mcp-config", options.mcp_config]
      else
        args
      end

    args =
      if options.permission_prompt_tool do
        args ++ ["--permission-prompt-tool", options.permission_prompt_tool]
      else
        args
      end

    args =
      if options.permission_mode do
        args ++ ["--permission-mode", to_string(options.permission_mode)]
      else
        args
      end

    args =
      if options.verbose do
        args ++ ["--verbose"]
      else
        args
      end

    args
  end
end