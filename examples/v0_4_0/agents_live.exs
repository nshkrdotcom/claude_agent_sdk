#!/usr/bin/env elixir

# Agents Live Example
# Demonstrates agent switching with REAL Claude CLI usage
#
# Usage:
#   mix run.live examples/v0_4_0/agents_live.exs

alias ClaudeAgentSDK.{Agent, Options, Client, ContentExtractor}

IO.puts("\n=== Agents Live Example ===\n")
IO.puts("⚠️  This will make REAL API calls to Claude\n")

# Define two specialized agents
coder =
  Agent.new(
    name: :coder,
    description: "Python coding expert",
    prompt:
      "You are a Python coding expert. Write concise, well-documented code with type hints.",
    allowed_tools: ["Read", "Write"],
    model: "claude-sonnet-4"
  )

analyst =
  Agent.new(
    name: :analyst,
    description: "Code analysis expert",
    prompt:
      "You are a code analysis expert. Provide detailed analysis and suggestions for improvement.",
    allowed_tools: ["Read"],
    model: "claude-sonnet-4"
  )

IO.puts("✅ Defined 2 agents:")
IO.puts("   - coder: Writes Python code")
IO.puts("   - analyst: Analyzes code quality\n")

# Start with coder agent
options =
  Options.new(
    agents: %{
      coder: coder,
      analyst: analyst
    },
    agent: :coder,
    max_turns: 5
  )

{:ok, client} = Client.start_link(options)
IO.puts("✅ Client started with coder agent\n")

# Task 1: Generate code
IO.puts("📝 Task 1: Coder agent generates Python code\n")

Client.send_message(
  client,
  "Write a simple Python function to check if a number is prime. Keep it under 10 lines."
)

Client.stream_messages(client)
|> Stream.take_while(fn msg -> msg["type"] != "result" end)
|> Stream.each(fn msg ->
  case msg do
    %{"type" => "assistant", "content" => content} when is_list(content) ->
      text = ContentExtractor.extract_content_text([msg])
      if text != "", do: IO.puts("💬 Coder: #{String.slice(text, 0..200)}...")

    _ ->
      :ok
  end
end)
|> Stream.run()

IO.puts("\n✅ Code generation complete\n")

# Switch to analyst agent
IO.puts("🔄 Switching to analyst agent...\n")
Client.set_agent(client, :analyst)

# Task 2: Analyze the code
IO.puts("📊 Task 2: Analyst agent reviews the code\n")

Client.send_message(
  client,
  "Analyze the prime number function I just wrote. What are its strengths and weaknesses?"
)

Client.stream_messages(client)
|> Stream.take_while(fn msg -> msg["type"] != "result" end)
|> Stream.each(fn msg ->
  case msg do
    %{"type" => "assistant", "content" => content} when is_list(content) ->
      text = ContentExtractor.extract_content_text([msg])
      if text != "", do: IO.puts("💬 Analyst: #{String.slice(text, 0..200)}...")

    _ ->
      :ok
  end
end)
|> Stream.run()

IO.puts("\n✅ Analysis complete\n")

Client.stop(client)

IO.puts("\n✅ Agents Live Example complete!")
IO.puts("\nWhat happened:")
IO.puts("  1. Started with coder agent")
IO.puts("  2. Coder generated Python code")
IO.puts("  3. Switched to analyst agent")
IO.puts("  4. Analyst reviewed the code")
IO.puts("  5. Context preserved across agent switch")
IO.puts("\n💡 This demonstrates multi-agent workflows for complex tasks!")
