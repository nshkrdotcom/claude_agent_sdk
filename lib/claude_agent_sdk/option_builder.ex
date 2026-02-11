defmodule ClaudeAgentSDK.OptionBuilder do
  @moduledoc """
  Smart option builder for Claude Code SDK configurations.

  This module provides pre-configured option sets and builder patterns for
  common use cases. Instead of manually constructing `ClaudeAgentSDK.Options`
  structs, you can use these convenience functions to get sensible defaults
  for different environments and scenarios.

  ## Design Philosophy

  - **Environment-aware**: Automatically adapt to dev, test, and production
  - **Security-first**: Production configs are restrictive by default
  - **Composable**: Mix and match presets with custom overrides
  - **Practical**: Based on real-world usage patterns

  ## Quick Start

      # Get options for current environment
      options = ClaudeAgentSDK.OptionBuilder.for_environment()
      
      # Use a specific preset
      options = ClaudeAgentSDK.OptionBuilder.build_development_options()
      
      # Customize a preset
      options = ClaudeAgentSDK.OptionBuilder.merge(:development, %{max_turns: 15})

  ## Structured Outputs (JSON Schema)

  Request validated JSON by providing a schema to `output_format`. This emits
  `--json-schema` for compatible CLI versions (same flag used by the Python SDK 0.1.10):

      schema = %{
        "type" => "object",
        "properties" => %{"summary" => %{"type" => "string"}},
        "required" => ["summary"]
      }

      options = %Options{output_format: %{type: :json_schema, schema: schema}}

  ## Environment Presets

  | Environment | Security | Tools | Turn Limit | Use Case |
  |-------------|----------|-------|------------|----------|
  | **Development** | Permissive | All tools | 10 | Local development |
  | **Staging** | Moderate | Read-only | 5 | Testing/CI |
  | **Production** | Restrictive | Read-only | 3 | Production analysis |

  ## Use Case Presets

  | Preset | Tools | Purpose | Permissions |
  |--------|-------|---------|-------------|
  | **Analysis** | Read, Grep, Find | Code review | Read-only |
  | **Documentation** | Read, Write | Doc generation | File creation |
  | **Chat** | None | Simple Q&A | No tools |
  | **Sandboxed** | Custom | Safe execution | Isolated |

  """

  alias ClaudeAgentSDK.{BuildEnv, Options}

  # Environment-specific presets

  @doc """
  Builds options suitable for development environment.

  **Use for**: Local development, debugging, experimentation

  **Features**:
  - Higher turn limit (10) for complex tasks
  - Verbose output for debugging
  - All tools allowed for full functionality
  - Edit permissions accepted for rapid iteration
  - Stream JSON output for real-time feedback

  ## Examples

      # Basic development setup
      options = ClaudeAgentSDK.OptionBuilder.build_development_options()
      ClaudeAgentSDK.query("Help me debug this function", options)

      # Development with custom system prompt
      options = 
        ClaudeAgentSDK.OptionBuilder.build_development_options()
        |> ClaudeAgentSDK.OptionBuilder.with_system_prompt("You are a debugging expert")

  """
  @spec build_development_options() :: Options.t()
  def build_development_options do
    %Options{
      max_turns: 10,
      verbose: true,
      output_format: :stream_json,
      allowed_tools: ["Bash", "Read", "Write", "Edit", "Grep", "Find"],
      permission_mode: :accept_edits,
      system_prompt:
        "You are a helpful development assistant. Focus on practical solutions and explain your reasoning."
    }
  end

  @doc """
  Builds options suitable for staging/testing environment.

  **Use for**: CI/CD pipelines, automated testing, code review

  **Features**:
  - Moderate turn limit (5) for focused tasks
  - Read-only tools for safety
  - Plan mode prevents automatic changes
  - Bash disabled to prevent system modifications
  - JSON output for structured results

  ## Examples

      # Use in CI for code analysis
      options = ClaudeAgentSDK.OptionBuilder.build_staging_options()
      ClaudeAgentSDK.query("Analyze this code for security issues", options)

  """
  @spec build_staging_options() :: Options.t()
  def build_staging_options do
    %Options{
      max_turns: 5,
      verbose: false,
      output_format: :json,
      permission_mode: :plan,
      allowed_tools: ["Read"],
      disallowed_tools: ["Bash", "Write", "Edit"],
      system_prompt: "You are a code reviewer. Provide thorough analysis without making changes."
    }
  end

  @doc """
  Builds options suitable for production environment.

  **Use for**: Production monitoring, read-only analysis, customer-facing features

  **Features**:
  - Low turn limit (3) for efficiency
  - Read-only access only
  - Plan mode for safety
  - Minimal tool access
  - Structured JSON output

  ## Examples

      # Production-safe code analysis
      options = ClaudeAgentSDK.OptionBuilder.build_production_options()
      ClaudeAgentSDK.query("Explain what this function does", options)

  """
  @spec build_production_options() :: Options.t()
  def build_production_options do
    %Options{
      max_turns: 3,
      verbose: false,
      output_format: :stream_json,
      permission_mode: :plan,
      allowed_tools: ["Read"],
      disallowed_tools: ["Bash", "Write", "Edit", "Grep", "Find"],
      system_prompt: "You are a helpful assistant. Provide concise, accurate information."
    }
  end

  # Use-case specific presets

  @doc """
  Builds options optimized for code analysis tasks.

  **Use for**: Code reviews, security audits, quality analysis

  **Features**:
  - Read and search tools for thorough analysis
  - Higher turn limit (7) for comprehensive review
  - No modification permissions for safety
  - Specialized system prompt for analysis focus

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.build_analysis_options()
      ClaudeAgentSDK.query("Review this module for potential issues", options)

  """
  @spec build_analysis_options() :: Options.t()
  def build_analysis_options do
    %Options{
      max_turns: 7,
      output_format: :stream_json,
      allowed_tools: ["Read", "Grep", "Find"],
      disallowed_tools: ["Write", "Edit", "Bash"],
      permission_mode: :plan,
      verbose: false,
      system_prompt:
        "You are a senior code reviewer. Analyze code for security, performance, maintainability, and best practices. Provide specific recommendations."
    }
  end

  @doc """
  Builds options for simple chat and Q&A interactions.

  **Use for**: Help desk, documentation queries, general assistance

  **Features**:
  - Single turn for quick responses
  - Text output for simple display
  - No tool access to prevent unintended actions
  - Minimal permissions

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.build_chat_options()
      ClaudeAgentSDK.query("What is the difference between async and sync?", options)

  """
  @spec build_chat_options() :: Options.t()
  def build_chat_options do
    %Options{
      max_turns: 1,
      output_format: :text,
      allowed_tools: [],
      disallowed_tools: ["Bash", "Read", "Write", "Edit", "Grep", "Find"],
      permission_mode: :plan,
      verbose: false,
      system_prompt: "You are a helpful programming assistant. Provide clear, concise answers."
    }
  end

  @doc """
  Builds options for documentation generation tasks.

  **Use for**: API docs, README generation, code documentation

  **Features**:
  - Read access to understand existing code
  - Write access for creating documentation files
  - Higher turn limit (8) for comprehensive docs
  - Accept edits mode for file creation
  - Specialized prompt for documentation focus

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.build_documentation_options()
      ClaudeAgentSDK.query("Generate API documentation for this module", options)

  """
  @spec build_documentation_options() :: Options.t()
  def build_documentation_options do
    %Options{
      max_turns: 8,
      output_format: :stream_json,
      allowed_tools: ["Read", "Write", "Grep"],
      disallowed_tools: ["Bash", "Edit"],
      permission_mode: :accept_edits,
      verbose: false,
      system_prompt:
        "You are a technical writer. Create clear, comprehensive documentation that helps users understand and use the code effectively."
    }
  end

  @doc """
  Builds options for test generation and testing tasks.

  **Use for**: Unit test creation, test analysis, quality assurance

  **Features**:
  - Read access to understand code under test
  - Write access for creating test files
  - Moderate turn limit for thorough test coverage
  - Testing-focused system prompt

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.build_testing_options()
      ClaudeAgentSDK.query("Generate comprehensive unit tests for this module", options)

  """
  @spec build_testing_options() :: Options.t()
  def build_testing_options do
    %Options{
      max_turns: 6,
      output_format: :stream_json,
      allowed_tools: ["Read", "Write", "Grep"],
      disallowed_tools: ["Bash", "Edit"],
      permission_mode: :accept_edits,
      verbose: false,
      system_prompt:
        "You are a QA engineer. Create thorough, maintainable tests that cover edge cases and follow testing best practices."
    }
  end

  # Builder utilities and combinators

  @doc """
  Builds options for the configured build environment.

  Automatically selects appropriate options based on the configured
  environment (defaults to `MIX_ENV` or `:prod` when unset):
  - `:dev` -> development options (permissive, verbose)
  - `:test` -> staging options (moderate restrictions)
  - `:prod` -> production options (restrictive, safe)

  This is the recommended way to get environment-appropriate defaults.

  ## Examples

      # Get options for current environment
      options = ClaudeAgentSDK.OptionBuilder.for_environment()
      
      # In development, this gives you full access
      # In production, this gives you read-only access

  """
  @spec for_environment() :: Options.t()
  def for_environment do
    case BuildEnv.current() do
      :dev -> build_development_options()
      :test -> build_staging_options()
      :prod -> build_production_options()
    end
  end

  @doc """
  Merges custom options with a base configuration.

  Allows you to start with a preset and customize specific fields.
  This is the recommended pattern for customizing presets.

  ## Parameters

  - `base` - Base preset (atom) or Options struct
  - `custom` - Map of custom options to override

  ## Examples

      # Start with development preset, customize turn limit
      options = ClaudeAgentSDK.OptionBuilder.merge(:development, %{max_turns: 15})
      
      # Start with analysis preset, add custom prompt
      options = ClaudeAgentSDK.OptionBuilder.merge(:analysis, %{
        system_prompt: "Focus on security vulnerabilities",
        max_turns: 10
      })
      
      # Merge with existing options
      base_options = ClaudeAgentSDK.OptionBuilder.build_chat_options()
      options = ClaudeAgentSDK.OptionBuilder.merge(base_options, %{max_turns: 3})

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
        :testing -> build_testing_options()
        _ -> %Options{}
      end

    merge(base_options, custom)
  end

  def merge(%Options{} = base, custom) when is_map(custom) do
    struct(base, custom)
  end

  @doc """
  Adds a custom working directory to any options.

  ## Parameters

  - `cwd` - Working directory path
  - `options` - Options struct to modify (optional, creates new if not provided)

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.with_working_directory("/project")
      
      options = 
        ClaudeAgentSDK.OptionBuilder.build_development_options()
        |> ClaudeAgentSDK.OptionBuilder.with_working_directory("/project")

  """
  @spec with_working_directory(String.t()) :: Options.t()
  def with_working_directory(cwd) do
    %Options{cwd: cwd}
  end

  @spec with_working_directory(Options.t(), String.t()) :: Options.t()
  def with_working_directory(%Options{} = options, cwd) do
    %{options | cwd: cwd}
  end

  @doc """
  Adds a custom system prompt to any options.

  ## Parameters

  - `prompt` - System prompt to use
  - `options` - Options struct to modify (optional, creates new if not provided)

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.with_system_prompt("You are a security expert")
      
      options = 
        ClaudeAgentSDK.OptionBuilder.build_analysis_options()
        |> ClaudeAgentSDK.OptionBuilder.with_system_prompt("You are a security expert")

  """
  @spec with_system_prompt(String.t()) :: Options.t()
  def with_system_prompt(prompt) do
    %Options{system_prompt: prompt}
  end

  @spec with_system_prompt(Options.t(), String.t()) :: Options.t()
  def with_system_prompt(%Options{} = options, prompt) do
    %{options | system_prompt: prompt}
  end

  @doc """
  Adds additional allowed tools to any options.

  ## Parameters

  - `options` - Options struct to modify
  - `tools` - List of additional tools to allow

  ## Examples

      options = 
        ClaudeAgentSDK.OptionBuilder.build_production_options()
        |> ClaudeAgentSDK.OptionBuilder.with_additional_tools(["Grep"])

  """
  @spec with_additional_tools(Options.t(), [String.t()]) :: Options.t()
  def with_additional_tools(%Options{} = options, additional_tools) do
    current_tools = options.allowed_tools || []
    %{options | allowed_tools: current_tools ++ additional_tools}
  end

  @doc """
  Sets a custom turn limit for any options.

  ## Parameters

  - `options` - Options struct to modify  
  - `turns` - Maximum number of turns

  ## Examples

      options = 
        ClaudeAgentSDK.OptionBuilder.build_chat_options()
        |> ClaudeAgentSDK.OptionBuilder.with_turn_limit(5)

  """
  @spec with_turn_limit(Options.t(), pos_integer()) :: Options.t()
  def with_turn_limit(%Options{} = options, turns) do
    %{options | max_turns: turns}
  end

  @doc """
  Creates a sandboxed configuration for safe execution.

  **Use for**: Untrusted code execution, isolated environments, testing

  **Features**:
  - Isolated to specific directory
  - Bypass permissions (safe within sandbox)
  - Customizable tool access
  - No bash access by default

  ## Parameters

  - `sandbox_path` - Path to sandbox directory
  - `allowed_tools` - List of tools to allow (default: ["Read", "Write"])

  ## Examples

      # Basic sandbox
      options = ClaudeAgentSDK.OptionBuilder.sandboxed("/tmp/sandbox")
      
      # Sandbox with custom tools
      options = ClaudeAgentSDK.OptionBuilder.sandboxed("/tmp/safe", ["Read", "Write", "Grep"])

  """
  @spec sandboxed(String.t(), [String.t()]) :: Options.t()
  def sandboxed(sandbox_path, allowed_tools \\ ["Read", "Write"]) do
    %Options{
      cwd: sandbox_path,
      permission_mode: :bypass_permissions,
      allowed_tools: allowed_tools,
      disallowed_tools: ["Bash"],
      max_turns: 5,
      output_format: :stream_json,
      system_prompt:
        "You are working in a sandboxed environment. Only work within the current directory."
    }
  end

  @doc """
  Creates options for quick, one-off queries.

  **Use for**: Simple questions, quick checks, lightweight operations

  **Features**:
  - Single turn limit
  - Text output for simplicity
  - No tools for safety
  - Fast response

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.quick()
      ClaudeAgentSDK.query("What does this error mean?", options)

  """
  @spec quick() :: Options.t()
  def quick do
    %Options{
      max_turns: 1,
      output_format: :text,
      allowed_tools: [],
      permission_mode: :plan,
      verbose: false,
      system_prompt: "Provide a quick, helpful answer."
    }
  end

  @doc """
  Lists all available preset names.

  Useful for dynamic configuration or validation.

  ## Examples

      presets = ClaudeAgentSDK.OptionBuilder.available_presets()
      # => [:development, :staging, :production, :analysis, :chat, :documentation, :testing]

  """
  @spec available_presets() :: [atom()]
  def available_presets do
    [:development, :staging, :production, :analysis, :chat, :documentation, :testing]
  end

  @doc """
  Validates that an options struct has sensible configuration.

  Checks for common misconfigurations and provides warnings.

  ## Parameters

  - `options` - Options struct to validate

  ## Returns

  - `{:ok, options}` if valid
  - `{:warning, options, warnings}` if valid but has warnings
  - `{:error, reason}` if invalid

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.build_development_options()
      {:ok, _} = ClaudeAgentSDK.OptionBuilder.validate(options)

  """
  @spec validate(Options.t()) ::
          {:ok, Options.t()} | {:warning, Options.t(), [String.t()]} | {:error, String.t()}
  def validate(%Options{} = options) do
    warnings =
      []
      |> check_turn_limit(options)
      |> check_bypass_permissions(options)
      |> check_bash_bypass_combination(options)

    case warnings do
      [] -> {:ok, options}
      warnings -> {:warning, options, Enum.reverse(warnings)}
    end
  end

  defp check_turn_limit(warnings, options) do
    if options.max_turns && options.max_turns > 20 do
      ["Turn limit very high (#{options.max_turns}), may be expensive" | warnings]
    else
      warnings
    end
  end

  defp check_bypass_permissions(warnings, options) do
    if options.permission_mode == :bypass_permissions && !options.cwd do
      ["bypass_permissions without cwd could be unsafe" | warnings]
    else
      warnings
    end
  end

  defp check_bash_bypass_combination(warnings, options) do
    if options.allowed_tools && "Bash" in options.allowed_tools &&
         options.permission_mode == :bypass_permissions do
      ["Bash + bypass_permissions can be dangerous" | warnings]
    else
      warnings
    end
  end

  # Model selection helpers (v0.1.0)

  @doc """
  Builds options for maximum capability using Opus model.

  Best for:
  - Complex reasoning tasks
  - Code generation requiring deep understanding
  - Multi-step problem solving

  Higher cost but better results.

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.with_opus()
      ClaudeAgentSDK.query("Architect a complex system", options)
  """
  @spec with_opus() :: Options.t()
  def with_opus do
    %Options{
      model: "opus",
      # Fallback if opus busy
      fallback_model: "sonnet",
      max_turns: 10,
      output_format: :stream_json
    }
  end

  @doc """
  Builds options for balanced performance using Sonnet model.

  Best for:
  - General-purpose tasks
  - Good balance of speed and capability
  - Complex reasoning tasks

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.with_sonnet()
      ClaudeAgentSDK.query("Review this code", options)
  """
  @spec with_sonnet() :: Options.t()
  def with_sonnet do
    %Options{
      model: "sonnet",
      max_turns: 5,
      output_format: :stream_json
    }
  end

  @doc """
  Builds options for fast responses using Haiku model (default).

  Best for:
  - Simple queries
  - Quick responses needed
  - High-volume use cases
  - Lowest cost option
  - Default for most SDK operations

  ## Examples

      options = ClaudeAgentSDK.OptionBuilder.with_haiku()
      ClaudeAgentSDK.query("What is 2+2?", options)
  """
  @spec with_haiku() :: Options.t()
  def with_haiku do
    %Options{
      model: "haiku",
      max_turns: 3,
      output_format: :stream_json
    }
  end

  @doc """
  Adds specific model to any options.

  ## Parameters

  - `options` - Existing options
  - `model_name` - Model name (short form like `"opus"`, `"sonnet"`, `"haiku"`, or a full model ID)
  - `fallback` - Optional fallback model

  ## Examples

      options = build_development_options()
      |> with_model("opus", "sonnet")
  """
  @spec with_model(Options.t(), String.t(), String.t() | nil) :: Options.t()
  def with_model(options, model_name, fallback \\ nil) do
    %{options | model: model_name, fallback_model: fallback}
  end

  @doc """
  Adds custom agent to options.

  ## Examples

      options = OptionBuilder.build_development_options()
      |> OptionBuilder.with_agent("security_reviewer", %{
        description: "Security-focused code reviewer",
        prompt: "You are a security expert. Review for vulnerabilities."
      })
  """
  @spec with_agent(Options.t(), String.t(), map()) :: Options.t()
  def with_agent(%Options{agents: nil} = options, name, definition) do
    %{options | agents: %{name => definition}}
  end

  def with_agent(%Options{agents: agents} = options, name, definition) do
    %{options | agents: Map.put(agents, name, definition)}
  end

  @doc """
  Sets multiple agents at once.

  ## Examples

      agents = %{
        "reviewer" => %{description: "Code reviewer", prompt: "Review code"},
        "tester" => %{description: "Test generator", prompt: "Generate tests"}
      }

      options = OptionBuilder.with_agents(agents)
  """
  @spec with_agents(map()) :: Options.t()
  def with_agents(agents) when is_map(agents) do
    %Options{agents: agents}
  end

  @spec with_agents(Options.t(), map()) :: Options.t()
  def with_agents(%Options{} = options, agents) when is_map(agents) do
    existing = options.agents || %{}
    %{options | agents: Map.merge(existing, agents)}
  end
end
