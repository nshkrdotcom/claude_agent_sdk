#!/usr/bin/env elixir
# Agents Example (LIVE)
# Demonstrates agent switching via real Claude CLI sessions.
#
# Run: mix run examples/advanced_features/agents_live.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Agent, Options, ContentExtractor}
alias Examples.Support

Support.ensure_live!()

Support.header!("Agents Example (live)")

# Define two specialized agents
coder =
  Agent.new(
    name: :coder,
    description: "Python coding expert",
    prompt:
      "You are a Python coding expert. Write concise, well-documented code with type hints. Keep responses under 15 lines.",
    allowed_tools: [],
    model: "haiku"
  )

analyst =
  Agent.new(
    name: :analyst,
    description: "Code analysis expert",
    prompt:
      "You are a code analysis expert. Provide concise analysis highlighting 2-3 key points. Keep responses under 10 lines.",
    allowed_tools: [],
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
    max_turns: 2
  )

prompt1 =
  "Write a simple Python function to check if a number is prime. Keep it under 10 lines total. Do not use tools."

IO.puts("Prompt: #{prompt1}\n")
IO.puts("🤖 Agent: coder\n")

# First query with coder
messages1 =
  ClaudeAgentSDK.query(prompt1, options)
  |> Enum.to_list()

# Extract and display response
text1 =
  messages1
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.join("\n")

if text1 == "" do
  IO.puts("❌ No assistant text returned for coder agent.")
  System.halt(1)
end

IO.puts("💬 Coder's Response:")
IO.puts("─" |> String.duplicate(60))
IO.puts(String.slice(text1, 0..500))
if String.length(text1) > 500, do: IO.puts("... (truncated)")
IO.puts("─" |> String.duplicate(60))

case Enum.find(messages1, &(&1.type == :result)) do
  %{subtype: :success} ->
    :ok

  %{subtype: subtype} ->
    IO.puts("❌ Query failed (coder) with result subtype: #{inspect(subtype)}")
    System.halt(1)

  nil ->
    IO.puts("❌ No result message returned (coder).")
    System.halt(1)
end

# Get session ID (prefer result; fall back to system init)
session_id =
  Enum.find_value(messages1, fn
    %{type: :result, data: %{session_id: sid}} when is_binary(sid) and sid != "" ->
      sid

    %{type: :system, subtype: :init, data: %{session_id: sid}}
    when is_binary(sid) and sid != "" ->
      sid

    _ ->
      nil
  end)

if is_nil(session_id) do
  IO.puts("\n❌ Could not extract session ID for continuation.")
  IO.puts("This example requires session resumption to demonstrate agent switching.")
  System.halt(1)
end

IO.puts("\n✅ Code generation complete (Session: #{String.slice(session_id, 0..8)}...)\n")

# Task 2: Switch to analyst and analyze the code
IO.puts("🔄 Switching to analyst agent...\n")

# Update options to use analyst agent
options_analyst = %{options | agent: :analyst}

prompt2 =
  "Analyze the prime number function I just wrote. Give me 2-3 key strengths and weaknesses, be concise. Do not use tools."

IO.puts("Prompt: #{prompt2}\n")
IO.puts("🤖 Agent: analyst\n")

# Resume conversation with analyst agent
messages2 =
  ClaudeAgentSDK.resume(session_id, prompt2, options_analyst)
  |> Enum.to_list()

# Extract and display response
text2 =
  messages2
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.join("\n")

if text2 == "" do
  IO.puts("❌ No assistant text returned for analyst agent.")
  System.halt(1)
end

IO.puts("💬 Analyst's Response:")
IO.puts("─" |> String.duplicate(60))
IO.puts(String.slice(text2, 0..500))
if String.length(text2) > 500, do: IO.puts("... (truncated)")
IO.puts("─" |> String.duplicate(60))

case Enum.find(messages2, &(&1.type == :result)) do
  %{subtype: :success} ->
    :ok

  %{subtype: subtype} ->
    IO.puts("❌ Query failed (analyst) with result subtype: #{inspect(subtype)}")
    System.halt(1)

  nil ->
    IO.puts("❌ No result message returned (analyst).")
    System.halt(1)
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

Support.halt_if_runner!()
