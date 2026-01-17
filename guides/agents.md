# Agents Guide

This guide covers how to define and use custom agents (personas) in the Claude Agent SDK for Elixir.

## Table of Contents

1. [What are Agents](#what-are-agents)
2. [Agent.new/1 and the Agent Struct](#agentnew1-and-the-agent-struct)
3. [Agent Configuration](#agent-configuration)
4. [Using Agents in Options](#using-agents-in-options)
5. [Switching Agents at Runtime](#switching-agents-at-runtime)
6. [Multi-Agent Workflows](#multi-agent-workflows)
7. [Filesystem Agents](#filesystem-agents)
8. [Agent Validation](#agent-validation)
9. [Best Practices](#best-practices)

---

## What are Agents

Agents are custom personas or roles that you can define for Claude. Each agent has its own:

- **Description**: A human-readable description of what the agent does
- **Prompt**: A system prompt that defines the agent's behavior and expertise
- **Allowed Tools**: An optional list of tools the agent can use
- **Model**: An optional model specification (e.g., "haiku", "sonnet", "opus")

Agents enable you to:

- Create specialized AI assistants for different tasks
- Switch between different Claude behaviors at runtime
- Maintain conversation context across agent switches
- Build multi-agent workflows where different agents handle different parts of a task

### Use Cases

- **Code Review Agent**: Analyzes code for bugs, security issues, and best practices
- **Documentation Agent**: Writes clear, comprehensive documentation
- **Testing Agent**: Creates test cases and validates implementations
- **Research Agent**: Gathers information and provides analysis
- **Refactoring Agent**: Improves code structure and performance

---

## Agent.new/1 and the Agent Struct

The `ClaudeAgentSDK.Agent` module provides the `Agent` struct and functions for creating and managing agents.

### The Agent Struct

```elixir
%ClaudeAgentSDK.Agent{
  name: atom() | nil,           # Optional identifier
  description: String.t(),       # Required: What the agent does
  prompt: String.t(),            # Required: System prompt
  allowed_tools: [String.t()],   # Optional: List of tool names
  model: String.t() | nil        # Optional: Model to use
}
```

### Creating Agents with Agent.new/1

The `ClaudeAgentSDK.Agent.new/1` function creates a new agent struct from a keyword list:

```elixir
alias ClaudeAgentSDK.Agent

# Minimal agent (only required fields)
simple_agent = Agent.new(
  description: "A helpful assistant",
  prompt: "You are a helpful assistant that provides clear, concise answers."
)

# Complete agent with all fields
code_reviewer = Agent.new(
  name: :code_reviewer,
  description: "Expert code reviewer",
  prompt: """
  You are an expert code reviewer. When reviewing code:
  - Check for bugs and logic errors
  - Identify security vulnerabilities
  - Suggest performance improvements
  - Enforce coding standards and best practices
  Provide concise, actionable feedback.
  """,
  allowed_tools: ["Read", "Grep", "Glob"],
  model: "claude-sonnet-4"
)
```

### Required Fields

- `:description` - A non-empty string describing the agent's purpose
- `:prompt` - A non-empty string defining the agent's behavior

### Optional Fields

- `:name` - An atom identifier for the agent (useful for referencing in multi-agent setups)
- `:allowed_tools` - A list of tool name strings the agent can use
- `:model` - A string specifying which model to use (e.g., "haiku", "sonnet", "opus", "claude-sonnet-4")

Tip: MCP tool names are always strings (`mcp__<server>__<tool>`). Avoid atom tool names in agent configs to prevent atom leaks.

---

## Agent Configuration

### Description

The description should clearly explain what the agent does. It helps users understand the agent's purpose and is used by the CLI for agent discovery.

```elixir
# Good descriptions
description: "Python coding expert that writes clean, type-hinted code"
description: "Security analyst that identifies vulnerabilities in code"
description: "Technical writer that creates clear API documentation"

# Avoid vague descriptions
description: "A helper"  # Too vague
description: "Agent"     # Not descriptive
```

### Prompt

The prompt is the system instruction that shapes the agent's behavior. Write detailed prompts that:

- Define the agent's expertise and role
- Specify the format and style of responses
- Set boundaries and guidelines
- Include any domain-specific knowledge

```elixir
# Detailed prompt example
prompt: """
You are a Python expert specializing in data science and machine learning.

## Your Expertise
- NumPy, Pandas, and scikit-learn
- Deep learning with PyTorch and TensorFlow
- Data visualization with Matplotlib and Seaborn

## Response Guidelines
- Write code with type hints
- Include docstrings for functions
- Add comments explaining complex logic
- Keep examples concise but complete

## Constraints
- Prefer standard library solutions when possible
- Avoid deprecated APIs
- Use Python 3.10+ features
"""
```

### Model Selection

Choose the appropriate model based on task complexity:

```elixir
# Fast responses for simple tasks
model: "haiku"

# Balanced performance for most tasks
model: "sonnet"
model: "claude-sonnet-4"

# Maximum capability for complex tasks
model: "opus"
model: "claude-opus-4"
```

### Tool Configuration

Restrict tools to what the agent needs:

```elixir
# Read-only agent for code analysis
allowed_tools: ["Read", "Grep", "Glob"]

# Documentation writer
allowed_tools: ["Read", "Write", "Edit"]

# Full access agent
allowed_tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]

# No tools (chat only)
allowed_tools: []
```

---

## Using Agents in Options

To use agents, add them to the `Options` struct and specify which agent is active.

### Single Agent

```elixir
alias ClaudeAgentSDK.{Agent, Options}

reviewer = Agent.new(
  name: :reviewer,
  description: "Code reviewer",
  prompt: "You are an expert code reviewer. Analyze code for quality and correctness.",
  allowed_tools: ["Read", "Grep"],
  model: "sonnet"
)

options = Options.new(
  agents: %{reviewer: reviewer},
  agent: :reviewer,
  max_turns: 5
)

# Run query with the agent
ClaudeAgentSDK.query("Review the authentication module", options)
|> Enum.to_list()
```

### Multiple Agents

```elixir
alias ClaudeAgentSDK.{Agent, Options}

# Define multiple specialized agents
coder = Agent.new(
  name: :coder,
  description: "Python coding expert",
  prompt: "You are a Python expert. Write clean, well-documented code with type hints.",
  allowed_tools: ["Read", "Write", "Edit"],
  model: "sonnet"
)

tester = Agent.new(
  name: :tester,
  description: "Test specialist",
  prompt: "You are a testing expert. Write comprehensive pytest tests with good coverage.",
  allowed_tools: ["Read", "Write"],
  model: "sonnet"
)

reviewer = Agent.new(
  name: :reviewer,
  description: "Code reviewer",
  prompt: "You analyze code for bugs, security issues, and best practices.",
  allowed_tools: ["Read", "Grep"],
  model: "haiku"
)

# Configure options with all agents
options = Options.new(
  agents: %{
    coder: coder,
    tester: tester,
    reviewer: reviewer
  },
  agent: :coder,  # Start with coder
  max_turns: 5
)
```

---

## Switching Agents at Runtime

You can switch agents while maintaining conversation context by using `ClaudeAgentSDK.resume/3` with updated options.

### Basic Agent Switching

```elixir
alias ClaudeAgentSDK.{Agent, Options, Session}

# Define agents
coder = Agent.new(
  name: :coder,
  description: "Python coder",
  prompt: "You write Python code.",
  model: "haiku"
)

analyst = Agent.new(
  name: :analyst,
  description: "Code analyst",
  prompt: "You analyze code quality.",
  model: "haiku"
)

# Initial options with coder agent
options = Options.new(
  agents: %{coder: coder, analyst: analyst},
  agent: :coder,
  max_turns: 3
)

# First query with coder
messages1 = ClaudeAgentSDK.query(
  "Write a function to calculate fibonacci numbers",
  options
) |> Enum.to_list()

# Extract session ID for continuation
session_id = Session.extract_session_id(messages1)

# Switch to analyst agent
options_analyst = %{options | agent: :analyst}

# Resume conversation with analyst
messages2 = ClaudeAgentSDK.resume(
  session_id,
  "Analyze the function I just wrote for performance issues",
  options_analyst
) |> Enum.to_list()
```

### Extracting Session ID

The session ID can be found in either the result message or the system init message:

```elixir
# Method 1: Using Session helper
session_id = ClaudeAgentSDK.Session.extract_session_id(messages)

# Method 2: Manual extraction
session_id = Enum.find_value(messages, fn
  %{type: :result, data: %{session_id: sid}} when is_binary(sid) -> sid
  %{type: :system, subtype: :init, data: %{session_id: sid}} when is_binary(sid) -> sid
  _ -> nil
end)
```

---

## Multi-Agent Workflows

Multi-agent workflows let you orchestrate multiple specialized agents to complete complex tasks.

### Sequential Workflow

Each agent handles a specific phase of the task:

```elixir
alias ClaudeAgentSDK.{Agent, Options, Session, ContentExtractor}

# Phase 1: Design agent creates architecture
designer = Agent.new(
  name: :designer,
  description: "Software architect",
  prompt: "Design software architecture. Create clear, modular designs.",
  model: "sonnet"
)

# Phase 2: Coder implements the design
coder = Agent.new(
  name: :coder,
  description: "Implementation specialist",
  prompt: "Implement code based on designs. Write clean, tested code.",
  allowed_tools: ["Write", "Edit"],
  model: "sonnet"
)

# Phase 3: Reviewer validates the implementation
reviewer = Agent.new(
  name: :reviewer,
  description: "Code reviewer",
  prompt: "Review code for bugs, security, and best practices.",
  allowed_tools: ["Read", "Grep"],
  model: "haiku"
)

options = Options.new(
  agents: %{designer: designer, coder: coder, reviewer: reviewer},
  agent: :designer,
  max_turns: 3
)

# Phase 1: Design
IO.puts("Phase 1: Design")
msgs1 = ClaudeAgentSDK.query(
  "Design a user authentication system with JWT tokens",
  options
) |> Enum.to_list()
session_id = Session.extract_session_id(msgs1)

# Phase 2: Implement
IO.puts("Phase 2: Implementation")
msgs2 = ClaudeAgentSDK.resume(
  session_id,
  "Implement the authentication system based on the design",
  %{options | agent: :coder}
) |> Enum.to_list()

# Phase 3: Review
IO.puts("Phase 3: Review")
msgs3 = ClaudeAgentSDK.resume(
  session_id,
  "Review the implementation for security issues",
  %{options | agent: :reviewer}
) |> Enum.to_list()

# Extract final review
review = msgs3
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.join("\n")

IO.puts("Review Results:\n#{review}")
```

### Iterative Workflow

Agents work back and forth until a task is complete:

```elixir
defmodule MultiAgentWorkflow do
  alias ClaudeAgentSDK.{Agent, Options, Session, ContentExtractor}

  def run_iterative_workflow(task_description, max_iterations \\ 3) do
    # Define agents
    coder = Agent.new(
      name: :coder,
      description: "Code writer",
      prompt: "Write code to complete tasks. Accept feedback and improve.",
      model: "haiku"
    )

    reviewer = Agent.new(
      name: :reviewer,
      description: "Code reviewer",
      prompt: """
      Review code and provide specific feedback.
      If the code is acceptable, respond with "APPROVED".
      Otherwise, list specific improvements needed.
      """,
      model: "haiku"
    )

    options = Options.new(
      agents: %{coder: coder, reviewer: reviewer},
      agent: :coder,
      max_turns: 2
    )

    # Initial implementation
    msgs = ClaudeAgentSDK.query(task_description, options) |> Enum.to_list()
    session_id = Session.extract_session_id(msgs)

    iterate(session_id, options, max_iterations, 1)
  end

  defp iterate(_session_id, _options, max_iter, current) when current > max_iter do
    IO.puts("Max iterations reached")
    :max_iterations
  end

  defp iterate(session_id, options, max_iter, current) do
    IO.puts("Iteration #{current}: Review phase")

    # Review phase
    review_msgs = ClaudeAgentSDK.resume(
      session_id,
      "Review the current implementation",
      %{options | agent: :reviewer}
    ) |> Enum.to_list()

    review_text = extract_assistant_text(review_msgs)

    if String.contains?(review_text, "APPROVED") do
      IO.puts("Code approved!")
      :approved
    else
      IO.puts("Iteration #{current}: Revision phase")

      # Revision phase
      ClaudeAgentSDK.resume(
        session_id,
        "Address the reviewer's feedback",
        %{options | agent: :coder}
      ) |> Enum.to_list()

      iterate(session_id, options, max_iter, current + 1)
    end
  end

  defp extract_assistant_text(messages) do
    messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.join("\n")
  end
end

# Run the workflow
MultiAgentWorkflow.run_iterative_workflow("Write a function to validate email addresses")
```

---

## Filesystem Agents

The Claude CLI supports loading agent definitions from markdown files in the `.claude/agents/` directory of your project.

### Agent File Format

Create markdown files with YAML frontmatter in `.claude/agents/`:

```markdown
---
name: my-agent
description: Description of what this agent does
tools: Read, Grep, Glob
---

# Agent Name

System prompt content goes here. This becomes the agent's prompt.

You can include:
- Detailed instructions
- Examples
- Constraints and guidelines
```

### Directory Structure

```
your-project/
  .claude/
    agents/
      code-reviewer.md
      documentation-writer.md
      test-generator.md
  src/
  ...
```

### Example Agent File

Create `.claude/agents/security-auditor.md`:

```markdown
---
name: security-auditor
description: Security specialist that audits code for vulnerabilities
tools: Read, Grep, Glob
---

# Security Auditor

You are a security expert specializing in code audits. Your role is to identify:

## Vulnerabilities to Check
- SQL injection
- Cross-site scripting (XSS)
- Authentication bypass
- Insecure data handling
- Hardcoded credentials

## Response Format
For each issue found:
1. File and line number
2. Vulnerability type
3. Severity (Critical/High/Medium/Low)
4. Recommended fix

Be thorough but avoid false positives.
```

### Loading Filesystem Agents

Use `setting_sources: ["project"]` to load agents from the filesystem:

```elixir
alias ClaudeAgentSDK.{Client, Options}

# Set cwd to your project directory
options = %Options{
  cwd: "/path/to/your/project",
  setting_sources: ["project"],  # Load from .claude/agents/
  max_turns: 5,
  model: "haiku"
}

{:ok, client} = Client.start_link(options)

# Query - filesystem agents are now available
:ok = Client.query(client, "Run a security audit on the auth module")
{:ok, messages} = Client.receive_response(client)
# Or stream until result:
# Client.receive_response_stream(client) |> Enum.to_list()

# Check which agents were loaded (in init message)
init = Enum.find(messages, &(&1.type == :system and &1.subtype == :init))
IO.inspect(init.raw["agents"], label: "Loaded agents")

Client.stop(client)
```

### Combining Filesystem and Programmatic Agents

You can use both filesystem agents and programmatic agents together:

```elixir
alias ClaudeAgentSDK.{Agent, Options}

# Define a programmatic agent
custom_agent = Agent.new(
  name: :custom,
  description: "Custom programmatic agent",
  prompt: "You are a custom agent defined in code.",
  model: "haiku"
)

options = Options.new(
  cwd: "/path/to/project",
  setting_sources: ["project"],  # Also load filesystem agents
  agents: %{custom: custom_agent},
  agent: :custom,
  max_turns: 3
)
```

---

## Agent Validation

The SDK provides validation functions to ensure agent configurations are correct.

### Validating Individual Agents

Use the `validate/1` function from `ClaudeAgentSDK.Agent` to validate a single agent:

```elixir
alias ClaudeAgentSDK.Agent

# Valid agent
agent = Agent.new(
  description: "Valid agent",
  prompt: "You are helpful"
)
Agent.validate(agent)
#=> :ok

# Invalid: empty description
invalid1 = Agent.new(
  description: "",
  prompt: "Prompt"
)
Agent.validate(invalid1)
#=> {:error, :description_required}

# Invalid: empty prompt
invalid2 = Agent.new(
  description: "Description",
  prompt: ""
)
Agent.validate(invalid2)
#=> {:error, :prompt_required}

# Invalid: wrong type for allowed_tools
invalid3 = %Agent{
  description: "Description",
  prompt: "Prompt",
  allowed_tools: "Read"  # Should be a list
}
Agent.validate(invalid3)
#=> {:error, :allowed_tools_must_be_list}
```

### Validation Error Types

| Error | Cause |
|-------|-------|
| `:description_required` | Description is nil or empty |
| `:description_must_be_string` | Description is not a string |
| `:prompt_required` | Prompt is nil or empty |
| `:prompt_must_be_string` | Prompt is not a string |
| `:allowed_tools_must_be_list` | Tools is not a list |
| `:allowed_tools_must_be_strings` | Tools list contains non-strings |
| `:model_must_be_string` | Model is not a string |

### Validating Options with Agents

Use `Options.validate_agents/1` to validate the agents configuration in options:

```elixir
alias ClaudeAgentSDK.{Agent, Options}

# Valid configuration
options = Options.new(
  agents: %{
    coder: Agent.new(description: "Coder", prompt: "You code"),
    reviewer: Agent.new(description: "Reviewer", prompt: "You review")
  },
  agent: :coder
)
Options.validate_agents(options)
#=> :ok

# Invalid: active agent not in agents map
invalid = Options.new(
  agents: %{coder: Agent.new(description: "Coder", prompt: "You code")},
  agent: :reviewer  # Does not exist
)
Options.validate_agents(invalid)
#=> {:error, {:agent_not_found, :reviewer}}

# Invalid: agent specified but no agents defined
invalid2 = Options.new(
  agents: nil,
  agent: :coder
)
Options.validate_agents(invalid2)
#=> {:error, :no_agents_configured}

# Invalid: invalid agent in map
invalid3 = Options.new(
  agents: %{bad: Agent.new(description: "", prompt: "Prompt")},
  agent: :bad
)
Options.validate_agents(invalid3)
#=> {:error, {:invalid_agent, :bad, :description_required}}
```

### Validation Options Errors

| Error | Cause |
|-------|-------|
| `:no_agents_configured` | Active agent set but agents map is nil |
| `:agents_must_be_map` | Agents is not a map |
| `{:agent_not_found, name}` | Active agent not in agents map |
| `{:invalid_agent, name, reason}` | Agent failed validation |
| `:agent_must_be_atom` | Active agent is not an atom |

---

## Best Practices

### 1. Write Focused Agent Prompts

Create agents with clear, specific purposes:

```elixir
# Good: Focused agent
Agent.new(
  description: "Python type annotation specialist",
  prompt: """
  You specialize in adding type annotations to Python code.
  - Use Python 3.10+ syntax (union with |, etc.)
  - Add annotations to function signatures
  - Use TypedDict for complex dictionaries
  - Add docstrings with type information
  """
)

# Avoid: Overly broad agent
Agent.new(
  description: "General helper",
  prompt: "You help with everything"
)
```

### 2. Match Model to Task Complexity

```elixir
# Simple tasks: Use haiku for speed
simple_agent = Agent.new(
  description: "Quick responder",
  prompt: "Provide brief, direct answers",
  model: "haiku"
)

# Complex tasks: Use more capable models
complex_agent = Agent.new(
  description: "Architecture designer",
  prompt: "Design complex software systems",
  model: "opus"
)
```

### 3. Restrict Tools Appropriately

```elixir
# Read-only analysis agent
analyzer = Agent.new(
  description: "Code analyzer",
  prompt: "Analyze code without modifications",
  allowed_tools: ["Read", "Grep", "Glob"]  # No write access
)

# Trusted implementation agent
implementer = Agent.new(
  description: "Trusted implementer",
  prompt: "Implement requested features",
  allowed_tools: ["Read", "Write", "Edit", "Bash"]
)
```

### 4. Validate Before Use

Always validate agents before using them in production:

```elixir
def create_agent(attrs) do
  agent = Agent.new(attrs)

  case Agent.validate(agent) do
    :ok -> {:ok, agent}
    {:error, reason} -> {:error, "Invalid agent: #{inspect(reason)}"}
  end
end
```

### 5. Use Meaningful Names

```elixir
# Good: Descriptive names
agents: %{
  code_reviewer: reviewer_agent,
  security_auditor: security_agent,
  documentation_writer: docs_agent
}

# Avoid: Generic names
agents: %{
  agent1: agent1,
  agent2: agent2
}
```

### 6. Document Agent Capabilities

```elixir
# Include capability documentation in the description
Agent.new(
  name: :database_expert,
  description: "PostgreSQL expert - query optimization, schema design, migrations",
  prompt: "..."
)
```

### 7. Handle Agent Switches Gracefully

```elixir
def switch_agent(session_id, new_agent, options, prompt \\ nil) do
  updated_options = %{options | agent: new_agent}

  case Options.validate_agents(updated_options) do
    :ok ->
      if prompt do
        ClaudeAgentSDK.resume(session_id, prompt, updated_options)
      else
        ClaudeAgentSDK.resume(session_id, nil, updated_options)
      end

    {:error, reason} ->
      {:error, "Cannot switch to agent #{new_agent}: #{inspect(reason)}"}
  end
end
```

### 8. Use Filesystem Agents for Team Sharing

Store commonly used agents in `.claude/agents/` so the entire team can use them:

```
.claude/
  agents/
    code-reviewer.md      # Shared code review standards
    security-auditor.md   # Company security guidelines
    style-enforcer.md     # Team coding style
```

### 9. Combine Agents for Complex Workflows

Design agent teams that complement each other:

```elixir
# Complementary agent team
agents = %{
  # Creative phase
  designer: Agent.new(
    description: "Creates designs and architectures",
    prompt: "Focus on creative solutions and designs",
    model: "opus"
  ),

  # Implementation phase
  implementer: Agent.new(
    description: "Implements designs",
    prompt: "Write clean, efficient implementations",
    allowed_tools: ["Write", "Edit"],
    model: "sonnet"
  ),

  # Validation phase
  validator: Agent.new(
    description: "Validates implementations",
    prompt: "Verify correctness and quality",
    allowed_tools: ["Read", "Bash"],
    model: "haiku"
  )
}
```

### 10. Test Agent Configurations

```elixir
defmodule AgentTest do
  use ExUnit.Case
  alias ClaudeAgentSDK.{Agent, Options}

  describe "agent validation" do
    test "code_reviewer agent is valid" do
      agent = create_code_reviewer()
      assert Agent.validate(agent) == :ok
    end

    test "options with agents are valid" do
      options = create_multi_agent_options()
      assert Options.validate_agents(options) == :ok
    end
  end
end
```

---

## Summary

Agents in the Claude Agent SDK enable you to:

- Create specialized AI personas with custom prompts and tool access
- Switch between agents while maintaining conversation context
- Build multi-agent workflows for complex tasks
- Load agents from filesystem for team sharing
- Validate configurations before use

Key modules:
- `ClaudeAgentSDK.Agent` - Agent struct and validation
- `ClaudeAgentSDK.Options` - Configuration with agents
- `ClaudeAgentSDK.Session` - Session ID extraction for agent switching

For more examples, see:
- `examples/advanced_features/agents_live.exs` - Multi-agent workflow demo
- `examples/advanced_features/subagent_spawning_live.exs` - Task tool for parallel subagent spawning
- `examples/filesystem_agents_live.exs` - Filesystem agents demo

---

## Subagent Spawning with Task Tool

The Task tool enables a lead agent to spawn subagents that work in parallel on different aspects of a problem. This pattern is similar to the research-agent demo in the official SDK demos.

### How It Works

When Claude has access to the Task tool, it can spawn specialized subagents:

1. **Lead Agent**: Orchestrates the overall task and spawns subagents
2. **Subagents**: Work on specific subtasks independently
3. **Results**: Flow back to the lead agent for synthesis

### Basic Usage

```elixir
alias ClaudeAgentSDK.Options

options = Options.new(
  model: "sonnet",
  max_turns: 10,
  allowed_tools: ["Task", "Read", "Write"],  # Task enables subagent spawning
  permission_mode: :bypass_permissions
)

prompt = """
Research the current state of Elixir web frameworks. Spawn two subagents:
1. One to research Phoenix features
2. One to research LiveView capabilities
Then synthesize their findings.
"""

ClaudeAgentSDK.query(prompt, options)
|> Enum.to_list()
```

### Tracking Subagent Activity

Use hooks to monitor subagent spawning:

```elixir
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

# Track Task tool usage
track_subagents = fn input, _tool_use_id, _context ->
  case input do
    %{"tool_name" => "Task", "tool_input" => tool_input} ->
      description = tool_input["description"] || "unknown"
      subagent_type = tool_input["subagent_type"] || "general-purpose"
      IO.puts("Spawning subagent: #{description} (#{subagent_type})")
    _ -> :ok
  end
  Output.allow()
end

options = Options.new(
  allowed_tools: ["Task", "Read", "Glob", "Grep"],
  hooks: %{
    pre_tool_use: [Matcher.new("Task", [track_subagents])]
  }
)
```

### Streaming Subagent Output

When using the Streaming API, events include a `parent_tool_use_id` field to identify which subagent produced each event:

```elixir
Streaming.send_message(session, "Use Task to research Elixir frameworks")
|> Enum.each(fn event ->
  case event.parent_tool_use_id do
    nil ->
      # Main agent output
      IO.write("[MAIN] #{event[:text]}")

    tool_id ->
      # Subagent output - route to appropriate UI panel
      IO.write("[SUB:#{String.slice(tool_id, 0, 8)}] #{event[:text]}")
  end
end)
```

See the [Streaming Guide](streaming.md#subagent-events-parent_tool_use_id) and `examples/streaming_tools/subagent_streaming.exs` for details.

### Subagent Types

The Task tool supports different subagent types:

| Type | Description |
|------|-------------|
| `general-purpose` | Default agent for multi-step tasks |
| `Explore` | Fast codebase exploration |
| `Plan` | Software architecture planning |

### Use Cases

- **Research Workflows**: Spawn multiple researchers for parallel information gathering
- **Code Analysis**: Parallel scanning of different parts of a codebase
- **Complex Tasks**: Decompose large tasks into parallelizable subtasks

See `examples/advanced_features/subagent_spawning_live.exs` for a complete demonstration.
