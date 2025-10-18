#!/usr/bin/env elixir
# SDK MCP Live Demo - REAL Claude API Usage
# Demonstrates SDK MCP tools with actual Claude CLI integration
#
# Usage:
#   MIX_ENV=test mix run.live examples/v0_5_0/sdk_mcp_live_demo.exs
#
# Prerequisites:
#   - Claude CLI installed and authenticated (claude login)
#   - ANTHROPIC_API_KEY environment variable set
#
# Note: Uses MIX_ENV=test to ensure compiled modules are available

defmodule MathTools do
  @moduledoc """
  Example SDK MCP tools for mathematical operations.
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
      IO.puts("  [MathTools] add(#{a}, #{b}) = #{result}")

      {:ok,
       %{
         "content" => [
           %{
             "type" => "text",
             "text" => "The sum of #{a} and #{b} is #{result}"
           }
         ]
       }}
    end
  end

  deftool :multiply,
          "Multiply two numbers together",
          %{
            type: "object",
            properties: %{
              a: %{type: "number", description: "First number"},
              b: %{type: "number", description: "Second number"}
            },
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      result = a * b
      IO.puts("  [MathTools] multiply(#{a}, #{b}) = #{result}")

      {:ok,
       %{
         "content" => [
           %{
             "type" => "text",
             "text" => "The product of #{a} and #{b} is #{result}"
           }
         ]
       }}
    end
  end
end

IO.puts("\n=== SDK MCP Live Demo ===\n")
IO.puts("This example demonstrates SDK MCP tools with REAL Claude API calls")
IO.puts("⚠️  Warning: This will make actual API calls and may incur costs!\n")

# Create SDK MCP server with math tools
IO.puts("📦 Creating SDK MCP server...")

server =
  ClaudeAgentSDK.create_sdk_mcp_server(
    name: "math-tools",
    version: "1.0.0",
    tools: [MathTools.Add, MathTools.Multiply]
  )

IO.puts("✅ Server created: #{server.name} v#{server.version}")
IO.puts("   Registry PID: #{inspect(server.registry_pid)}\n")

# Create options with SDK MCP server
options =
  ClaudeAgentSDK.Options.new(
    mcp_servers: %{"math-tools" => server},
    max_turns: 5,
    verbose: true
  )

IO.puts("🤖 Configured Claude with SDK MCP server")
IO.puts("   MCP servers: #{inspect(Map.keys(options.mcp_servers))}\n")

# Query Claude to use the tools
prompt = """
Please use the math tools I've provided to solve these problems:

1. What is 156 + 284?
2. What is 23 × 17?
3. Calculate (15 + 27) × 2

For each calculation, use the appropriate tool and show me the result.
"""

IO.puts("📤 Sending query to Claude...\n")
IO.puts("Prompt: #{String.slice(prompt, 0..100)}...\n")

# Stream and display messages
IO.puts("💬 Claude's response:\n")

try do
  ClaudeAgentSDK.query(prompt, options)
  |> Stream.each(fn msg ->
    case msg do
      %{"type" => "assistant", "content" => content} when is_list(content) ->
        for block <- content do
          case block do
            %{"type" => "text", "text" => text} ->
              IO.puts("Claude: #{text}\n")

            %{"type" => "tool_use", "name" => name, "input" => input} ->
              IO.puts("🛠️  Claude is using tool: #{name}")
              IO.puts("   Input: #{inspect(input)}\n")

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

  IO.puts("\n🎉 SDK MCP Live Demo completed successfully!")
  IO.puts("\nWhat happened:")
  IO.puts("  1. We created an SDK MCP server with 2 math tools")
  IO.puts("  2. The server was passed to Claude via the control protocol")
  IO.puts("  3. Claude discovered the tools via MCP 'tools/list' request")
  IO.puts("  4. Claude used the tools via MCP 'tools/call' requests")
  IO.puts("  5. Tool execution happened in-process (no subprocess overhead)")
  IO.puts("\n💡 Key Benefits:")
  IO.puts("  - Tools run in the same Elixir process")
  IO.puts("  - No subprocess spawning or IPC overhead")
  IO.puts("  - Direct access to Elixir ecosystem")
  IO.puts("  - Easier debugging and testing")
rescue
  e ->
    IO.puts("\n❌ Error: #{Exception.message(e)}")
    IO.puts("\n#{Exception.format_stacktrace(__STACKTRACE__)}")

    IO.puts("\n💡 Troubleshooting:")
    IO.puts("  - Ensure Claude CLI is installed: claude --version")
    IO.puts("  - Ensure you're authenticated: claude login")
    IO.puts("  - Check API key: echo $ANTHROPIC_API_KEY")
    IO.puts("  - Try with mock mode first: Options.new(mock: true)")
end
