# Implementation Plan: Model and Agent Support
## Priority: MUST-HAVE (High)
## Estimated Effort: 1 day
## Target Version: 0.1.0

---

## 🎯 Objective

Expose Claude Code CLI's `--model`, `--fallback-model`, and `--agents` flags in the SDK to enable:
- Selection of specific Claude models (Opus, Sonnet, Haiku)
- Automatic fallback when primary model is overloaded
- Custom agent workflows with specialized prompts

---

## 📋 Problem Statement

### Current State
```elixir
# SDK doesn't expose model selection
ClaudeAgentSDK.query("Complex task")  # Uses default model (Sonnet)

# Can't define custom agents
# Can't fallback automatically when model is busy
```

### Desired State
```elixir
# Model selection
options = %Options{
  model: "opus",              # Most capable
  fallback_model: "sonnet"    # If opus is overloaded
}

# Custom agents
options = %Options{
  agents: %{
    "security_reviewer" => %{
      description: "Security-focused code reviewer",
      prompt: "You are a security expert. Look for vulnerabilities."
    },
    "refactorer" => %{
      description: "Code refactoring specialist",
      prompt: "You refactor code for clean architecture."
    }
  }
}

ClaudeAgentSDK.query("Review this auth function", options)
```

---

## 🏗️ Architecture Design

### Changes to Options Module

```elixir
# lib/claude_agent_sdk/options.ex

defmodule ClaudeAgentSDK.Options do
  defstruct [
    # ... existing fields
    :model,           # NEW: String - model name or alias
    :fallback_model,  # NEW: String - fallback model
    :agents,          # NEW: Map - custom agent definitions
    :session_id,      # NEW: String - explicit session ID (UUID)
    :settings,        # NEW: String - path to settings JSON or JSON string
    :add_dir          # NEW: [String] - additional directories for tool access
  ]

  @type model_name :: String.t()
  @type agent_name :: String.t()
  @type agent_definition :: %{
    description: String.t(),
    prompt: String.t()
  }

  @type t :: %__MODULE__{
    # ... existing fields
    model: model_name() | nil,
    fallback_model: model_name() | nil,
    agents: %{agent_name() => agent_definition()} | nil,
    session_id: String.t() | nil,
    settings: String.t() | nil,
    add_dir: [String.t()] | nil
  }
end
```

### CLI Argument Mapping

```elixir
# lib/claude_agent_sdk/options.ex (to_args/1 updates)

defp add_model_args(args, %{model: nil}), do: args
defp add_model_args(args, %{model: model}) do
  args ++ ["--model", model]
end

defp add_fallback_model_args(args, %{fallback_model: nil}), do: args
defp add_fallback_model_args(args, %{fallback_model: model}) do
  args ++ ["--fallback-model", model]
end

defp add_agents_args(args, %{agents: nil}), do: args
defp add_agents_args(args, %{agents: agents}) do
  # Convert to JSON format expected by CLI
  json = Jason.encode!(agents)
  args ++ ["--agents", json]
end

defp add_session_id_args(args, %{session_id: nil}), do: args
defp add_session_id_args(args, %{session_id: id}) do
  args ++ ["--session-id", id]
end

defp add_settings_args(args, %{settings: nil}), do: args
defp add_settings_args(args, %{settings: settings}) do
  args ++ ["--settings", settings]
end

defp add_dir_args(args, %{add_dir: nil}), do: args
defp add_dir_args(args, %{add_dir: directories}) do
  # Space-separated list of directories
  args ++ ["--add-dir"] ++ directories
end
```

---

## 📁 File Structure

```
lib/claude_agent_sdk/
  options.ex              # Update: Add new fields
  option_builder.ex       # Update: Add model/agent helpers
  agents/                 # New: Agent utilities
    builder.ex            # New: Agent definition builder
    presets.ex            # New: Pre-built agents

test/claude_agent_sdk/
  options_test.exs        # Update: Test new fields
  option_builder_test.exs # Update: Test new helpers
  agents/
    builder_test.exs      # New: Agent builder tests

examples/
  model_selection.exs     # New: Model usage example
  custom_agents.exs       # New: Agent workflow example
```

---

## 🔧 Implementation Details

### Phase 1: Update Options Module

**File**: `lib/claude_agent_sdk/options.ex`

Add to `defstruct`:
```elixir
defstruct [
  # Existing fields...
  :max_turns,
  :system_prompt,
  # ... etc

  # New fields
  :model,           # "opus" | "sonnet" | "haiku" | "claude-sonnet-4-5-20250929"
  :fallback_model,  # Same format as model
  :agents,          # %{agent_name => %{description, prompt}}
  :session_id,      # UUID string
  :settings,        # JSON file path or JSON string
  :add_dir          # ["path/to/dir1", "path/to/dir2"]
]
```

Update `to_args/1`:
```elixir
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
  |> add_model_args(options)           # NEW
  |> add_fallback_model_args(options)  # NEW
  |> add_agents_args(options)          # NEW
  |> add_session_id_args(options)      # NEW
  |> add_settings_args(options)        # NEW
  |> add_dir_args(options)             # NEW
end
```

### Phase 2: Enhance OptionBuilder

**File**: `lib/claude_agent_sdk/option_builder.ex`

Add model selection helpers:
```elixir
@doc """
Builds options for maximum capability (Opus model).

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
    fallback_model: "sonnet",  # Fallback if opus busy
    max_turns: 10
  }
end

@doc """
Builds options for balanced performance (Sonnet model).

Best for:
- General-purpose tasks
- Good balance of speed and capability
- Most cost-effective for production

## Examples

    options = ClaudeAgentSDK.OptionBuilder.with_sonnet()
"""
@spec with_sonnet() :: Options.t()
def with_sonnet do
  %Options{
    model: "sonnet",
    max_turns: 5
  }
end

@doc """
Builds options for fast responses (Haiku model).

Best for:
- Simple queries
- Quick responses needed
- High-volume use cases
- Lowest cost option

## Examples

    options = ClaudeAgentSDK.OptionBuilder.with_haiku()
"""
@spec with_haiku() :: Options.t()
def with_haiku do
  %Options{
    model: "haiku",
    max_turns: 3
  }
end

@doc """
Adds specific model to any options.

## Parameters

- `options` - Existing options
- `model_name` - Model name ("opus", "sonnet", "haiku", or full name)
- `fallback` - Optional fallback model

## Examples

    options
    |> with_model("opus", "sonnet")
    |> with_turn_limit(10)
"""
@spec with_model(Options.t(), String.t(), String.t() | nil) :: Options.t()
def with_model(options, model_name, fallback \\ nil) do
  %{options | model: model_name, fallback_model: fallback}
end
```

Add agent helpers:
```elixir
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
Merges multiple agents into options.

## Examples

    agents = %{
      "reviewer" => %{
        description: "Code reviewer",
        prompt: "Review code quality"
      },
      "tester" => %{
        description: "Test generator",
        prompt: "Generate comprehensive tests"
      }
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
```

### Phase 3: Agent Builder Utility

**File**: `lib/claude_agent_sdk/agents/builder.ex`

```elixir
defmodule ClaudeAgentSDK.Agents.Builder do
  @moduledoc """
  Builder for custom Claude agents.

  Provides a fluent API for defining specialized agents with
  custom prompts, tools, and behaviors.

  ## Examples

      agent = AgentBuilder.new("code_reviewer")
      |> AgentBuilder.with_description("Security-focused reviewer")
      |> AgentBuilder.with_system_prompt(\"\"\"
        You are a security expert specializing in:
        - OWASP Top 10 vulnerabilities
        - Secure coding practices
        - Input validation
      \"\"\")
      |> AgentBuilder.with_tools(["Read", "Grep"])
      |> AgentBuilder.build()
  """

  defstruct [
    :name,
    :description,
    :prompt,
    :tools,
    :examples
  ]

  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t() | nil,
    prompt: String.t() | nil,
    tools: [String.t()] | nil,
    examples: [String.t()] | nil
  }

  @doc """
  Creates a new agent builder.
  """
  @spec new(String.t()) :: t()
  def new(name) do
    %__MODULE__{name: name}
  end

  @doc """
  Sets the agent description.
  """
  @spec with_description(t(), String.t()) :: t()
  def with_description(builder, description) do
    %{builder | description: description}
  end

  @doc """
  Sets the agent's system prompt.
  """
  @spec with_system_prompt(t(), String.t()) :: t()
  def with_system_prompt(builder, prompt) do
    %{builder | prompt: prompt}
  end

  @doc """
  Sets allowed tools for the agent.
  """
  @spec with_tools(t(), [String.t()]) :: t()
  def with_tools(builder, tools) do
    %{builder | tools: tools}
  end

  @doc """
  Adds example interactions for the agent.
  """
  @spec with_examples(t(), [String.t()]) :: t()
  def with_examples(builder, examples) do
    %{builder | examples: examples}
  end

  @doc """
  Builds the agent definition suitable for Options.agents.
  """
  @spec build(t()) :: {String.t(), map()}
  def build(builder) do
    definition = %{
      description: builder.description || "Custom agent: #{builder.name}",
      prompt: builder.prompt || "You are a helpful assistant."
    }

    # Add optional fields if present
    definition = if builder.tools do
      Map.put(definition, :allowed_tools, builder.tools)
    else
      definition
    end

    definition = if builder.examples do
      Map.put(definition, :examples, builder.examples)
    else
      definition
    end

    {builder.name, definition}
  end

  @doc """
  Builds and returns just the definition map.
  """
  @spec build_definition(t()) :: map()
  def build_definition(builder) do
    {_name, definition} = build(builder)
    definition
  end
end
```

### Phase 4: Pre-built Agent Library

**File**: `lib/claude_agent_sdk/agents/presets.ex`

```elixir
defmodule ClaudeAgentSDK.Agents.Presets do
  @moduledoc """
  Pre-built agent definitions for common use cases.

  ## Usage

      alias ClaudeAgentSDK.Agents.Presets

      options = %Options{
        agents: Presets.security_agents()
      }

      # Or combine with custom agents
      options = %Options{
        agents: Map.merge(
          Presets.code_quality_agents(),
          my_custom_agents()
        )
      }
  """

  @doc """
  Returns security-focused agent definitions.
  """
  @spec security_agents() :: map()
  def security_agents do
    %{
      "security_reviewer" => %{
        description: "Security vulnerability scanner",
        prompt: """
        You are a security expert specializing in secure code review.

        Focus on:
        - OWASP Top 10 vulnerabilities
        - SQL injection, XSS, CSRF
        - Authentication and authorization flaws
        - Sensitive data exposure
        - Input validation issues

        Provide specific, actionable recommendations.
        """
      },
      "crypto_auditor" => %{
        description: "Cryptography implementation reviewer",
        prompt: """
        You are a cryptography expert reviewing crypto implementations.

        Check for:
        - Weak encryption algorithms
        - Poor key management
        - Insufficient randomness
        - Timing attacks
        - Protocol implementation flaws

        Reference industry standards (NIST, FIPS).
        """
      }
    }
  end

  @doc """
  Returns code quality agent definitions.
  """
  @spec code_quality_agents() :: map()
  def code_quality_agents do
    %{
      "style_checker" => %{
        description: "Code style and convention checker",
        prompt: """
        You are a code style expert.

        Review for:
        - Naming conventions
        - Code organization
        - Comment quality
        - Readability
        - Best practices for the language

        Suggest improvements aligned with community standards.
        """
      },
      "performance_optimizer" => %{
        description: "Performance optimization specialist",
        prompt: """
        You are a performance optimization expert.

        Identify:
        - Algorithmic inefficiencies
        - Memory leaks
        - Unnecessary computations
        - Database query optimization opportunities
        - Caching opportunities

        Provide concrete optimization suggestions with expected impact.
        """
      },
      "refactorer" => %{
        description: "Code refactoring specialist",
        prompt: """
        You are a refactoring expert focused on clean architecture.

        Suggest refactorings for:
        - DRY violations
        - Large functions/classes
        - Complex conditionals
        - Design pattern opportunities
        - Code smells

        Provide before/after examples.
        """
      }
    }
  end

  @doc """
  Returns testing-focused agent definitions.
  """
  @spec testing_agents() :: map()
  def testing_agents do
    %{
      "test_generator" => %{
        description: "Comprehensive test generator",
        prompt: """
        You are a testing expert.

        Generate tests that:
        - Cover edge cases
        - Test error conditions
        - Follow AAA pattern (Arrange, Act, Assert)
        - Use appropriate test doubles
        - Are maintainable and readable

        Include both unit and integration test scenarios.
        """
      },
      "test_reviewer" => %{
        description: "Test quality reviewer",
        prompt: """
        You review test code quality.

        Check for:
        - Adequate coverage
        - Test independence
        - Proper assertions
        - Test data quality
        - Flaky test patterns

        Suggest improvements for reliability and maintainability.
        """
      }
    }
  end

  @doc """
  Returns documentation-focused agent definitions.
  """
  @spec documentation_agents() :: map()
  def documentation_agents do
    %{
      "doc_generator" => %{
        description: "Technical documentation generator",
        prompt: """
        You are a technical writer.

        Create documentation that:
        - Explains purpose and usage clearly
        - Includes code examples
        - Documents edge cases and limitations
        - Uses proper formatting (markdown)
        - Is accessible to target audience

        Follow documentation best practices.
        """
      },
      "api_documenter" => %{
        description: "API documentation specialist",
        prompt: """
        You specialize in API documentation.

        Document:
        - Function signatures with types
        - Parameter descriptions
        - Return values
        - Usage examples
        - Common errors
        - Related functions

        Use consistent format across all endpoints.
        """
      }
    }
  end

  @doc """
  Returns all preset agents combined.
  """
  @spec all() :: map()
  def all do
    Map.merge(security_agents(), code_quality_agents())
    |> Map.merge(testing_agents())
    |> Map.merge(documentation_agents())
  end
end
```

---

## 🧪 Testing Strategy

### Unit Tests

**File**: `test/claude_agent_sdk/options_test.exs`

```elixir
defmodule ClaudeAgentSDK.OptionsTest do
  use ExUnit.Case

  alias ClaudeAgentSDK.Options

  describe "model support" do
    test "converts model to CLI args" do
      options = %Options{model: "opus"}
      args = Options.to_args(options)

      assert "--model" in args
      assert "opus" in args
    end

    test "converts fallback model to CLI args" do
      options = %Options{
        model: "opus",
        fallback_model: "sonnet"
      }
      args = Options.to_args(options)

      assert "--fallback-model" in args
      assert "sonnet" in args
    end

    test "handles full model names" do
      options = %Options{model: "claude-sonnet-4-5-20250929"}
      args = Options.to_args(options)

      assert "claude-sonnet-4-5-20250929" in args
    end
  end

  describe "agent support" do
    test "converts agents to JSON CLI args" do
      agents = %{
        "reviewer" => %{
          description: "Code reviewer",
          prompt: "Review code"
        }
      }

      options = %Options{agents: agents}
      args = Options.to_args(options)

      assert "--agents" in args

      # Find JSON arg
      json_idx = Enum.find_index(args, &(&1 == "--agents")) + 1
      json_arg = Enum.at(args, json_idx)

      # Verify it's valid JSON
      assert {:ok, decoded} = Jason.decode(json_arg)
      assert decoded["reviewer"]["description"] == "Code reviewer"
    end

    test "handles multiple agents" do
      agents = %{
        "agent1" => %{description: "A1", prompt: "P1"},
        "agent2" => %{description: "A2", prompt: "P2"}
      }

      options = %Options{agents: agents}
      args = Options.to_args(options)

      json_idx = Enum.find_index(args, &(&1 == "--agents")) + 1
      json_arg = Enum.at(args, json_idx)

      {:ok, decoded} = Jason.decode(json_arg)
      assert map_size(decoded) == 2
    end
  end
end
```

**File**: `test/claude_agent_sdk/agents/builder_test.exs`

```elixir
defmodule ClaudeAgentSDK.Agents.BuilderTest do
  use ExUnit.Case

  alias ClaudeAgentSDK.Agents.Builder

  test "builds basic agent" do
    {name, definition} = Builder.new("test_agent")
    |> Builder.with_description("Test agent")
    |> Builder.with_system_prompt("You are a test.")
    |> Builder.build()

    assert name == "test_agent"
    assert definition.description == "Test agent"
    assert definition.prompt == "You are a test."
  end

  test "builds agent with tools" do
    {_name, definition} = Builder.new("agent")
    |> Builder.with_tools(["Read", "Grep"])
    |> Builder.build()

    assert definition.allowed_tools == ["Read", "Grep"]
  end

  test "handles optional fields" do
    {_name, definition} = Builder.new("minimal")
    |> Builder.build()

    assert definition.description =~ "minimal"
    assert definition.prompt == "You are a helpful assistant."
  end
end
```

### Integration Tests

```elixir
defmodule ClaudeAgentSDK.ModelIntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "queries with specific model" do
    options = %ClaudeAgentSDK.Options{
      model: "sonnet",
      max_turns: 1
    }

    messages = ClaudeAgentSDK.query("Hello", options)
    |> Enum.to_list()

    # Verify model was used (check system message)
    system_msg = Enum.find(messages, &(&1.type == :system))
    assert system_msg.data.model =~ "sonnet"
  end

  @tag :integration
  test "uses custom agent" do
    agents = %{
      "math_helper" => %{
        description: "Math expert",
        prompt: "You are a math expert. Solve problems step by step."
      }
    }

    options = %ClaudeAgentSDK.Options{agents: agents}

    messages = ClaudeAgentSDK.query("What is 2+2?", options)
    |> Enum.to_list()

    assert Enum.any?(messages, &(&1.type == :assistant))
  end
end
```

---

## 📊 Success Criteria

- [ ] Model selection working (opus, sonnet, haiku, full names)
- [ ] Fallback model triggers correctly when primary busy
- [ ] Custom agents execute with specialized prompts
- [ ] Pre-built agent library available (10+ agents)
- [ ] Agent builder API intuitive and documented
- [ ] OptionBuilder has model/agent helpers
- [ ] All tests passing
- [ ] Documentation complete with examples

---

## 📝 Documentation Updates

### README.md

Add model selection section:

```markdown
## Model Selection

### Using Model Aliases

```elixir
# Opus - Most capable, higher cost
options = ClaudeAgentSDK.OptionBuilder.with_opus()

# Sonnet - Balanced (default)
options = ClaudeAgentSDK.OptionBuilder.with_sonnet()

# Haiku - Fastest, lowest cost
options = ClaudeAgentSDK.OptionBuilder.with_haiku()
```

### Automatic Fallback

```elixir
options = %Options{
  model: "opus",
  fallback_model: "sonnet"  # If opus is overloaded
}
```

### Custom Agents

```elixir
alias ClaudeAgentSDK.Agents.{Builder, Presets}

# Use pre-built agents
options = %Options{
  agents: Presets.security_agents()
}

# Or build custom agents
{name, agent} = Builder.new("my_agent")
|> Builder.with_description("Custom specialist")
|> Builder.with_system_prompt("You are an expert in X")
|> Builder.build()

options = %Options{agents: %{name => agent}}
```
```

---

## ⏱️ Timeline

**Day 1**: Implementation (7 hours)
- Update Options (2 hours)
- Update OptionBuilder (2 hours)
- Agent Builder (2 hours)
- Agent Presets (1 hour)

**Day 2**: Testing & Documentation (3 hours)
- Unit tests (1.5 hours)
- Integration tests (0.5 hour)
- Documentation (1 hour)

**Total**: 10 hours (1.25 days)

---

**Status**: Ready for Implementation
**Dependencies**: None (independent feature)
**Risk**: Low (additive changes only)
