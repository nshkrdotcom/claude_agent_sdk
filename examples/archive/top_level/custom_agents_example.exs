#!/usr/bin/env elixir

# Example: Custom agent workflows
# Shows how to define specialized agents for different tasks

alias ClaudeAgentSDK.OptionBuilder

# Enable mocking
Application.put_env(:claude_agent_sdk, :use_mock, true)
{:ok, _} = ClaudeAgentSDK.Mock.start_link()

IO.puts("🤖 Custom Agents Example")
IO.puts("=" |> String.duplicate(50))
IO.puts("")

# Define custom security reviewer agent
security_agent = %{
  "security_reviewer" => %{
    description: "Security-focused code reviewer",
    prompt: """
    You are a security expert specializing in:
    - OWASP Top 10 vulnerabilities  
    - Input validation
    - Authentication/authorization
    - Secure coding practices

    Review code and provide specific security recommendations.
    """
  }
}

IO.puts("📋 Defined Security Reviewer Agent")
IO.puts("   Description: #{security_agent["security_reviewer"].description}")
IO.puts("")

# Use the agent
options =
  OptionBuilder.build_analysis_options()
  |> OptionBuilder.with_agents(security_agent)

IO.puts("✅ Agent configured with analysis options")
IO.puts("   Allowed tools: #{inspect(options.allowed_tools)}")
IO.puts("   Permission mode: #{options.permission_mode}")
IO.puts("")

# Example 2: Multiple agents
multi_agents = %{
  "reviewer" => %{
    description: "Code quality reviewer",
    prompt: "Review code for style and best practices"
  },
  "tester" => %{
    description: "Test generator",
    prompt: "Generate comprehensive ExUnit tests"
  },
  "refactorer" => %{
    description: "Code refactoring specialist",
    prompt: "Suggest refactorings for clean architecture"
  }
}

_options_multi = %ClaudeAgentSDK.Options{agents: multi_agents}

IO.puts("📋 Defined #{map_size(multi_agents)} agents:")

Enum.each(multi_agents, fn {name, agent} ->
  IO.puts("   • #{name}: #{agent.description}")
end)

IO.puts("")

IO.puts("✅ Custom agents example complete!")
