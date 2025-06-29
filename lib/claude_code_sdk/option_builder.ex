defmodule ClaudeCodeSDK.OptionBuilder do
  @moduledoc """
  Builder patterns for common ClaudeCodeSDK.Options configurations.

  Provides pre-configured option sets for different environments and use cases,
  making it easier to work with the SDK in various contexts.
  """

  alias ClaudeCodeSDK.Options

  @doc """
  Builds options suitable for development environment.

  Features:
  - Higher turn limit (10)
  - Verbose output enabled
  - All tools allowed
  - Edit permissions accepted

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.build_development_options()
      iex> options.max_turns
      10
      iex> options.verbose
      true
  """
  @spec build_development_options() :: Options.t()
  def build_development_options do
    %Options{
      max_turns: 10,
      verbose: true,
      allowed_tools: ["Bash", "Read", "Write", "Edit"],
      permission_mode: :accept_edits
    }
  end

  @doc """
  Builds options suitable for staging/testing environment.

  Features:
  - Moderate turn limit (5)
  - Read-only tools
  - Plan mode (no automatic edits)
  - Bash disabled for safety

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.build_staging_options()
      iex> options.permission_mode
      :plan
  """
  @spec build_staging_options() :: Options.t()
  def build_staging_options do
    %Options{
      max_turns: 5,
      verbose: false,
      permission_mode: :plan,
      allowed_tools: ["Read"],
      disallowed_tools: ["Bash", "Write", "Edit"]
    }
  end

  @doc """
  Builds options suitable for production environment.

  Features:
  - Low turn limit (3)
  - Read-only access
  - Plan mode
  - Minimal tool access

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.build_production_options()
      iex> options.max_turns
      3
  """
  @spec build_production_options() :: Options.t()
  def build_production_options do
    %Options{
      max_turns: 3,
      verbose: false,
      permission_mode: :plan,
      allowed_tools: ["Read"],
      disallowed_tools: ["Bash", "Write", "Edit"],
      output_format: :stream_json
    }
  end

  @doc """
  Builds options for code analysis tasks.

  Features:
  - Read-only access
  - Higher turn limit for thorough analysis
  - No modification permissions

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.build_analysis_options()
      iex> "Write" in options.disallowed_tools
      true
  """
  @spec build_analysis_options() :: Options.t()
  def build_analysis_options do
    %Options{
      max_turns: 7,
      allowed_tools: ["Read", "Grep", "Find"],
      disallowed_tools: ["Write", "Edit", "Bash"],
      permission_mode: :plan,
      verbose: false
    }
  end

  @doc """
  Builds options for interactive chat/assistance.

  Features:
  - Lower turn limit
  - Text output format
  - No tool access by default

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.build_chat_options()
      iex> options.output_format
      :text
  """
  @spec build_chat_options() :: Options.t()
  def build_chat_options do
    %Options{
      max_turns: 1,
      output_format: :text,
      allowed_tools: [],
      permission_mode: :plan
    }
  end

  @doc """
  Builds options for documentation generation.

  Features:
  - Read access to understand code
  - Write access for creating docs
  - Higher turn limit for comprehensive docs

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.build_documentation_options()
      iex> "Write" in options.allowed_tools
      true
  """
  @spec build_documentation_options() :: Options.t()
  def build_documentation_options do
    %Options{
      max_turns: 8,
      allowed_tools: ["Read", "Write"],
      disallowed_tools: ["Bash", "Edit"],
      permission_mode: :accept_edits,
      verbose: false
    }
  end

  @doc """
  Builds options with custom working directory.

  ## Parameters

    - `cwd` - Working directory path
    - `base_options` - Base options to extend (optional)

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.with_working_directory("/project")
      iex> options.cwd
      "/project"
  """
  @spec with_working_directory(String.t(), Options.t()) :: Options.t()
  def with_working_directory(cwd, base_options \\ %Options{}) do
    %{base_options | cwd: cwd}
  end

  @doc """
  Builds options with custom system prompt.

  ## Parameters

    - `prompt` - System prompt to use
    - `base_options` - Base options to extend (optional)

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.with_system_prompt("You are a helpful assistant")
      iex> options.system_prompt
      "You are a helpful assistant"
  """
  @spec with_system_prompt(String.t(), Options.t()) :: Options.t()
  def with_system_prompt(prompt, base_options \\ %Options{}) do
    %{base_options | system_prompt: prompt}
  end

  @doc """
  Builds options for a specific environment based on Mix.env().

  Automatically selects appropriate options based on current environment:
  - `:dev` -> development options
  - `:test` -> staging options  
  - `:prod` -> production options

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.for_environment()
      iex> is_struct(options, ClaudeCodeSDK.Options)
      true
  """
  @spec for_environment() :: Options.t()
  def for_environment do
    case Mix.env() do
      :dev -> build_development_options()
      :test -> build_staging_options()
      :prod -> build_production_options()
      # Safe default
      _ -> build_production_options()
    end
  end

  @doc """
  Merges custom options with a base configuration.

  ## Parameters

    - `base` - Base options or builder function atom
    - `custom` - Map of custom options to override

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.merge(:development, %{max_turns: 15})
      iex> options.max_turns
      15
      iex> options.verbose
      true
  """
  @spec merge(atom() | Options.t(), map()) :: Options.t()
  def merge(base, custom) when is_atom(base) do
    base_options =
      case base do
        :development -> build_development_options()
        :staging -> build_staging_options()
        :production -> build_production_options()
        :analysis -> build_analysis_options()
        :chat -> build_chat_options()
        :documentation -> build_documentation_options()
        _ -> %Options{}
      end

    merge(base_options, custom)
  end

  def merge(%Options{} = base, custom) when is_map(custom) do
    struct(base, custom)
  end

  @doc """
  Creates a sandboxed configuration for safe execution.

  ## Parameters

    - `sandbox_path` - Path to sandbox directory
    - `allowed_tools` - List of tools to allow (default: ["Read", "Write"])

  ## Examples

      iex> options = ClaudeCodeSDK.OptionBuilder.sandboxed("/tmp/sandbox")
      iex> options.cwd
      "/tmp/sandbox"
      iex> "Bash" in options.disallowed_tools
      true
  """
  @spec sandboxed(String.t(), list(String.t())) :: Options.t()
  def sandboxed(sandbox_path, allowed_tools \\ ["Read", "Write"]) do
    %Options{
      cwd: sandbox_path,
      permission_mode: :bypass_permissions,
      allowed_tools: allowed_tools,
      disallowed_tools: ["Bash"],
      max_turns: 5
    }
  end
end
