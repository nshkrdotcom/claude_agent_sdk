#!/usr/bin/env elixir

# Agent Switching Example
# Demonstrates defining and switching between multiple agent profiles
#
# Usage:
#   mix run examples/v0_4_0/agent_switching.exs

alias ClaudeAgentSDK.{Agent, Options, Client}

IO.puts("\n=== Agent Switching Example ===\n")

# Define multiple agent profiles
IO.puts("Defining agent profiles...\n")

code_agent =
  Agent.new(
    name: :code_expert,
    description: "Expert Python programmer",
    prompt: """
    You are an expert Python programmer. You excel at:
    - Writing clean, efficient code
    - Following PEP 8 style guidelines
    - Using type hints and documentation
    - Applying best practices and design patterns

    When writing code, always include type hints and docstrings.
    """,
    allowed_tools: ["Read", "Write", "Bash", "Edit"],
    model: "claude-sonnet-4"
  )

research_agent =
  Agent.new(
    name: :researcher,
    description: "Research and analysis specialist",
    prompt: """
    You are a research specialist. You excel at:
    - Finding and analyzing information
    - Synthesizing data from multiple sources
    - Creating comprehensive reports
    - Fact-checking and verification

    Always cite your sources and provide evidence for claims.
    """,
    allowed_tools: ["WebSearch", "WebFetch", "Read"],
    model: "claude-opus-4"
  )

documentation_agent =
  Agent.new(
    name: :technical_writer,
    description: "Technical documentation expert",
    prompt: """
    You are a technical documentation expert. You excel at:
    - Writing clear, concise documentation
    - Creating helpful examples and tutorials
    - Organizing information logically
    - Making complex topics accessible

    Always use clear language and provide concrete examples.
    """,
    allowed_tools: ["Read", "Write"],
    model: "claude-sonnet-4"
  )

IO.puts("✅ Defined 3 agents:")
IO.puts("   - #{code_agent.name}: #{code_agent.description}")
IO.puts("   - #{research_agent.name}: #{research_agent.description}")
IO.puts("   - #{documentation_agent.name}: #{documentation_agent.description}")

# Create options with all agents
options =
  Options.new(
    agents: %{
      code_expert: code_agent,
      researcher: research_agent,
      technical_writer: documentation_agent
    },
    # Start with code expert
    agent: :code_expert,
    max_turns: 2
  )

IO.puts("\n📋 Starting client with code_expert as active agent...\n")

{:ok, client} = Client.start_link(options)

# Get initial agent
{:ok, current_agent} = Client.get_agent(client)
IO.puts("Current agent: #{current_agent}")

# Get available agents
{:ok, available} = Client.get_available_agents(client)
IO.puts("Available agents: #{inspect(available)}")

# Demonstrate agent switching
IO.puts("\n🔄 Switching agents...\n")

IO.puts("1. Switching to researcher agent")
:ok = Client.set_agent(client, :researcher)
{:ok, agent} = Client.get_agent(client)
IO.puts("   Active agent: #{agent}")
state = :sys.get_state(client)
IO.puts("   Model: #{state.options.model}")
IO.puts("   Allowed tools: #{inspect(state.options.allowed_tools)}")

IO.puts("\n2. Switching to technical_writer agent")
:ok = Client.set_agent(client, :technical_writer)
{:ok, agent} = Client.get_agent(client)
IO.puts("   Active agent: #{agent}")
state = :sys.get_state(client)
IO.puts("   Model: #{state.options.model}")
IO.puts("   Allowed tools: #{inspect(state.options.allowed_tools)}")

IO.puts("\n3. Switching back to code_expert")
:ok = Client.set_agent(client, :code_expert)
{:ok, agent} = Client.get_agent(client)
IO.puts("   Active agent: #{agent}")
state = :sys.get_state(client)
IO.puts("   Model: #{state.options.model}")
IO.puts("   Allowed tools: #{inspect(state.options.allowed_tools)}")

# Clean up
Client.stop(client)

IO.puts("\n✅ Agent Switching example complete!")
IO.puts("\nKey takeaways:")
IO.puts("  - Define agents with Agent.new/1")
IO.puts("  - Pass agents map in Options.new(agents: %{...})")
IO.puts("  - Switch agents at runtime with Client.set_agent/2")
IO.puts("  - Each agent has its own prompt, tools, and model")
IO.puts("  - Agent settings are applied automatically when switching")
IO.puts("  - Conversation context is preserved across switches")

IO.puts("\n💡 Use cases:")
IO.puts("  - Code agent for implementation → Research agent for documentation lookup")
IO.puts("  - Analyst agent for data review → Writer agent for report generation")
IO.puts("  - Different models for different tasks (Opus for complex, Sonnet for fast)")
