#!/usr/bin/env elixir
# Agents Live Example
# Demonstrates agent switching with REAL Claude CLI usage
#
# Usage:
#   MIX_ENV=test mix run.live examples/advanced_features/agents_live.exs
#
# Prerequisites:
#   - Claude CLI installed and authenticated (claude login)

alias ClaudeAgentSDK.{Agent, Options, ContentExtractor}

# Check if we're in mock mode - these are LIVE examples only
if Application.get_env(:claude_agent_sdk, :use_mock, false) do
  IO.puts("\n🎭 This is a LIVE example - it requires real API calls")
  IO.puts("   For agent configuration demo (mock mode), see:")
  IO.puts("   mix run examples/advanced_features/agent_switching.exs\n")
  IO.puts("💡 To run this live example:")
  IO.puts("   MIX_ENV=test mix run.live examples/advanced_features/agents_live.exs\n")
  System.halt(0)
end

IO.puts("🔴 Running in LIVE mode (real API calls)")
IO.puts("⚠️  Warning: This will make actual API calls and may incur costs!\n")

IO.puts("\n=== Agents Live Example ===\n")

# Define two specialized agents
coder =
  Agent.new(
    name: :coder,
    description: "Python coding expert",
    prompt:
      "You are a Python coding expert. Write concise, well-documented code with type hints. Keep responses under 15 lines.",
    allowed_tools: ["Read", "Write"],
    model: "haiku"
  )

analyst =
  Agent.new(
    name: :analyst,
    description: "Code analysis expert",
    prompt:
      "You are a code analysis expert. Provide concise analysis highlighting 2-3 key points. Keep responses under 10 lines.",
    allowed_tools: ["Read"],
    model: "haiku"
  )

IO.puts("✅ Defined 2 agents:")
IO.puts("   - coder: Writes Python code")
IO.puts("   - analyst: Analyzes code quality\n")

# Task 1: Generate code with coder agent
IO.puts("📝 Task 1: Coder agent generates Python code\n")

options =
  Options.new(
    agents: %{
      coder: coder,
      analyst: analyst
    },
    agent: :coder,
    max_turns: 5
  )

prompt1 =
  "Write a simple Python function to check if a number is prime. Keep it under 10 lines total."

IO.puts("Prompt: #{prompt1}\n")
IO.puts("🤖 Agent: coder\n")

# First query with coder
messages1 =
  ClaudeAgentSDK.query(prompt1, options)
  |> Enum.to_list()

# Extract and display response
text1 = ContentExtractor.extract_content_text(messages1)

if text1 != "" do
  IO.puts("💬 Coder's Response:")
  IO.puts("─" |> String.duplicate(60))
  IO.puts(String.slice(text1, 0..500))
  if String.length(text1) > 500, do: IO.puts("... (truncated)")
  IO.puts("─" |> String.duplicate(60))
end

# Get session ID from result message
session_id =
  case Enum.find(messages1, &(&1.type == :system and &1.subtype == :init)) do
    %{data: %{session_id: sid}} -> sid
    _ -> nil
  end

if session_id do
  IO.puts("\n✅ Code generation complete (Session: #{String.slice(session_id, 0..8)}...)\n")

  # Task 2: Switch to analyst and analyze the code
  IO.puts("🔄 Switching to analyst agent...\n")

  # Update options to use analyst agent
  options_analyst = %{options | agent: :analyst}

  prompt2 =
    "Analyze the prime number function I just wrote. Give me 2-3 key strengths and weaknesses, be concise."

  IO.puts("Prompt: #{prompt2}\n")
  IO.puts("🤖 Agent: analyst\n")

  # Resume conversation with analyst agent
  messages2 =
    ClaudeAgentSDK.resume(session_id, prompt2, options_analyst)
    |> Enum.to_list()

  # Extract and display response
  text2 = ContentExtractor.extract_content_text(messages2)

  if text2 != "" do
    IO.puts("💬 Analyst's Response:")
    IO.puts("─" |> String.duplicate(60))
    IO.puts(String.slice(text2, 0..500))
    if String.length(text2) > 500, do: IO.puts("... (truncated)")
    IO.puts("─" |> String.duplicate(60))
  end

  IO.puts("\n✅ Analysis complete\n")

  IO.puts("\n✅ Agents Live Example complete!")
  IO.puts("\nWhat happened:")
  IO.puts("  1. Started conversation with coder agent")
  IO.puts("  2. Coder generated Python prime number function")
  IO.puts("  3. Switched to analyst agent (via resume with new agent)")
  IO.puts("  4. Analyst analyzed the code from the same session")
  IO.puts("  5. Context was preserved across agent switch")
  IO.puts("\n💡 This demonstrates multi-agent workflows for complex tasks!")
else
  IO.puts("\n⚠️  Could not extract session ID for continuation")
  IO.puts("   Agent switching requires session resumption")
end
