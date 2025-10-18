#!/usr/bin/env elixir

# MCP Tools Live Example
# Demonstrates MCP tools with REAL Claude CLI usage
#
# Usage:
#   mix run.live examples/v0_4_0/mcp_tools_live.exs

defmodule MathTools do
  use ClaudeAgentSDK.Tool

  deftool :add,
          "Add two numbers",
          %{
            type: "object",
            properties: %{
              a: %{type: "number"},
              b: %{type: "number"}
            },
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      result = a + b
      IO.puts("🔧 Tool executed: add(#{a}, #{b}) = #{result}")

      {:ok,
       %{"content" => [%{"type" => "text", "text" => "The sum of #{a} and #{b} is #{result}"}]}}
    end
  end

  deftool :multiply,
          "Multiply two numbers",
          %{
            type: "object",
            properties: %{
              a: %{type: "number"},
              b: %{type: "number"}
            },
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      result = a * b
      IO.puts("🔧 Tool executed: multiply(#{a}, #{b}) = #{result}")

      {:ok,
       %{
         "content" => [%{"type" => "text", "text" => "The product of #{a} and #{b} is #{result}"}]
       }}
    end
  end
end

IO.puts("\n=== MCP Tools Live Example ===\n")
IO.puts("⚠️  This will make REAL API calls to Claude\n")

# Create SDK MCP server
server =
  ClaudeAgentSDK.create_sdk_mcp_server(
    name: "math-tools",
    version: "1.0.0",
    tools: [MathTools.Add, MathTools.Multiply]
  )

IO.puts("✅ Created MCP server with 2 math tools\n")

# Configure options with MCP tools
options =
  ClaudeAgentSDK.Options.new(
    mcp_config: %{"math-tools" => server},
    max_turns: 5
  )

# Query Claude with tool access
prompt = """
Please solve these math problems using the math tools I've provided:

1. What is 156 + 284?
2. What is 23 × 17?
3. Calculate 999 + 1

Use the add and multiply tools for each calculation.
"""

IO.puts("📤 Sending query to Claude...\n")
IO.puts("Prompt: #{String.slice(prompt, 0..100)}...\n")

# Stream messages and display
ClaudeAgentSDK.query(prompt, options)
|> Stream.each(fn msg ->
  case msg do
    %{"type" => "assistant", "content" => content} when is_list(content) ->
      for block <- content do
        case block do
          %{"type" => "text", "text" => text} ->
            IO.puts("💬 Claude: #{text}")

          %{"type" => "tool_use", "name" => name, "input" => input} ->
            IO.puts("🛠️  Claude wants to use: #{name}(#{inspect(input)})")

          _ ->
            :ok
        end
      end

    %{"type" => "result"} ->
      IO.puts("\n✅ Query complete!")

    _ ->
      :ok
  end
end)
|> Stream.run()

IO.puts("\n✅ MCP Tools Live Example complete!")
IO.puts("\nWhat happened:")
IO.puts("  1. We created an SDK MCP server with math tools")
IO.puts("  2. Claude was given access to these tools")
IO.puts("  3. Claude used the tools to perform calculations")
IO.puts("  4. Tools executed in-process (no subprocess)")
IO.puts("  5. Results were returned to Claude")
