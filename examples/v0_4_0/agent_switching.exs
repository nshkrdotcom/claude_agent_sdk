#!/usr/bin/env elixir

# Agent Switching Example
# Demonstrates defining and switching between multiple agent profiles
#
# Usage:
#   mix run examples/v0_4_0/agent_switching.exs

alias ClaudeAgentSDK.{Agent, Options}

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

IO.puts("\n📋 Configured with code_expert as active agent\n")
IO.puts("Current agent: #{options.agent}")
IO.puts("Available agents: #{inspect(Map.keys(options.agents))}")

IO.puts("\n💡 Note: This is a configuration demo (no CLI started)")
IO.puts("   For live agent switching with real queries, see: examples/v0_4_0/agents_live.exs\n")

# Demonstrate agent configurations
IO.puts("\n🔄 Agent switching workflow:\n")

IO.puts("1. Researcher agent configuration:")
IO.puts("   Agent: #{research_agent.name}")
IO.puts("   Model: #{research_agent.model}")
IO.puts("   Allowed tools: #{inspect(research_agent.allowed_tools)}")
IO.puts("   Use case: Research and information gathering")

IO.puts("\n2. Technical Writer agent configuration:")
IO.puts("   Agent: #{documentation_agent.name}")
IO.puts("   Model: #{documentation_agent.model}")
IO.puts("   Allowed tools: #{inspect(documentation_agent.allowed_tools)}")
IO.puts("   Use case: Documentation and technical writing")

IO.puts("\n3. Code Expert agent configuration:")
IO.puts("   Agent: #{code_agent.name}")
IO.puts("   Model: #{code_agent.model}")
IO.puts("   Allowed tools: #{inspect(code_agent.allowed_tools)}")
IO.puts("   Use case: Code implementation and debugging")

IO.puts("\n🔧 How to use in practice:")

IO.puts("""
  # Start client with agents
  {:ok, client} = Client.start_link(options)

  # Switch between agents during conversation
  Client.set_agent(client, :researcher)  # Switch to researcher
  Client.send_message(client, "Find info about Elixir GenServers")

  Client.set_agent(client, :code_expert)  # Switch to coder
  Client.send_message(client, "Implement a GenServer")

  Client.stop(client)
""")

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
