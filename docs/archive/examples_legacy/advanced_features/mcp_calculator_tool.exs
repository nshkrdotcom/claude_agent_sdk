#!/usr/bin/env elixir

# MCP Calculator Tool Example
# Demonstrates creating in-process MCP tools using the deftool macro
#
# Usage:
#   mix run examples/advanced_features/mcp_calculator_tool.exs

defmodule CalculatorTools do
  @moduledoc """
  Example MCP tools for mathematical operations.

  This module demonstrates how to define in-process MCP tools using the
  `deftool` macro. These tools run in the same process as the SDK (no subprocess),
  providing better performance and easier debugging.
  """
  use ClaudeAgentSDK.Tool

  deftool :add,
          "Add two numbers together",
          %{
            type: "object",
            properties: %{
              a: %{type: "number", description: "First number"},
              b: %{type: "number", description: "Second number"}
            },
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      result = a + b
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a} + #{b} = #{result}"}]}}
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
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a} × #{b} = #{result}"}]}}
    end
  end

  deftool :factorial,
          "Calculate factorial of a number",
          %{
            type: "object",
            properties: %{
              n: %{type: "integer", minimum: 0, maximum: 20}
            },
            required: ["n"]
          } do
    def execute(%{"n" => n}) when n >= 0 and n <= 20 do
      result = factorial(n)

      {:ok, %{"content" => [%{"type" => "text", "text" => "#{n}! = #{result}"}]}}
    end

    def execute(%{"n" => n}) do
      {:error, "n must be between 0 and 20, got: #{n}"}
    end

    defp factorial(0), do: 1
    defp factorial(n), do: n * factorial(n - 1)
  end
end

# Main execution
IO.puts("\n=== MCP Calculator Tool Example ===\n")

# Create SDK MCP server with our calculator tools
IO.puts("Creating SDK MCP server with calculator tools...")

server =
  ClaudeAgentSDK.create_sdk_mcp_server(
    name: "calculator",
    version: "1.0.0",
    tools: [
      CalculatorTools.Add,
      CalculatorTools.Multiply,
      CalculatorTools.Factorial
    ]
  )

IO.puts("✅ Server created: #{server.name} v#{server.version}")
IO.puts("   Type: #{server.type}")
IO.puts("   Registry PID: #{inspect(server.registry_pid)}")

# List registered tools
{:ok, tools} = ClaudeAgentSDK.Tool.Registry.list_tools(server.registry_pid)
IO.puts("\n📦 Registered tools (#{length(tools)}):")

for tool <- tools do
  IO.puts("   - #{tool.name}: #{tool.description}")
end

# Use the server in a query
IO.puts("\n🤖 Querying Claude with calculator tools available...")

_options =
  ClaudeAgentSDK.Options.new(
    mcp_config: %{"calculator" => server},
    max_turns: 3
  )

_prompt = """
Calculate the following using the calculator tools:
1. Add 15 and 27
2. Multiply 8 by 9
3. Calculate factorial of 5

Please use the calculator tools I've provided.
"""

# In real usage, you would stream and process messages
# For this example, we'll just show the setup
IO.puts("\nPrompt prepared. In live mode, Claude would use these tools:")
IO.puts("  - add(a: 15, b: 27)")
IO.puts("  - multiply(a: 8, b: 9)")
IO.puts("  - factorial(n: 5)")

IO.puts("\n✅ MCP Calculator Tool example complete!")
IO.puts("\nKey takeaways:")
IO.puts("  - deftool macro creates tool modules automatically")
IO.puts("  - Tools run in-process (no subprocess overhead)")
IO.puts("  - create_sdk_mcp_server bundles tools into an MCP server")
IO.puts("  - Server can be used in Options.mcp_config")
IO.puts("  - Claude can invoke these tools during conversations")

# Demonstrate direct tool execution
IO.puts("\n--- Direct Tool Execution Demo ---")
IO.puts("\nExecuting tools directly (without Claude):")

{:ok, result1} = CalculatorTools.Add.execute(%{"a" => 15, "b" => 27})
IO.puts("add(15, 27): #{hd(result1["content"])["text"]}")

{:ok, result2} = CalculatorTools.Multiply.execute(%{"a" => 8, "b" => 9})
IO.puts("multiply(8, 9): #{hd(result2["content"])["text"]}")

{:ok, result3} = CalculatorTools.Factorial.execute(%{"n" => 5})
IO.puts("factorial(5): #{hd(result3["content"])["text"]}")
