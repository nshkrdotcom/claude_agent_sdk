defmodule ClaudeCodeSDK.Options do
  @moduledoc """
  Configuration options for Claude Code SDK requests.
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

  ## Examples

      ClaudeCodeSDK.Options.new(
        max_turns: 5,
        output_format: :json,
        verbose: true
      )
  """
  def new(attrs \\ []) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Converts the options to command line arguments.
  """
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