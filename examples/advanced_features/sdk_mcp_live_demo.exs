#!/usr/bin/env elixir
# SDK MCP Example (LIVE)
# Demonstrates SDK MCP tools with real Claude CLI integration.
#
# Run: mix run examples/advanced_features/sdk_mcp_live_demo.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.Options
alias ClaudeAgentSDK.Message
alias Examples.Support

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
      IO.puts("  [MathTools.Add] #{a} + #{b} = #{result}")

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
      IO.puts("  [MathTools.Multiply] #{a} × #{b} = #{result}")

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

Support.ensure_live!()
Support.header!("SDK MCP Example (live)")

# Create SDK MCP server with math tools
IO.puts("📦 Creating SDK MCP server...")

server =
  ClaudeAgentSDK.create_sdk_mcp_server(
    name: "math-tools",
    version: "1.0.0",
    tools: [MathTools.Add, MathTools.Multiply]
  )

IO.puts("✅ Server created: #{server.name} v#{server.version}")
IO.puts("   Type: #{server.type}")
IO.puts("   Registry PID: #{inspect(server.registry_pid)}\n")

# Create options with SDK MCP server
allowed_tools = [
  "mcp__math-tools__add",
  "mcp__math-tools__multiply"
]

options =
  Options.new(
    mcp_servers: %{"math-tools" => server},
    model: "haiku",
    allowed_tools: allowed_tools
  )

IO.puts("🤖 Configured Claude with SDK MCP server")
IO.puts("   MCP servers: #{inspect(Map.keys(options.mcp_servers))}")
IO.puts("   Allowed tools: #{inspect(allowed_tools)}\n")

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
  summary =
    ClaudeAgentSDK.query(prompt, options)
    |> Enum.reduce(%{tool_uses: 0, tool_results: 0, result_subtype: nil}, fn
      %Message{type: :assistant} = msg, acc ->
        Message.content_blocks(msg)
        |> Enum.reduce(acc, fn
          %{type: :text, text: text}, acc2 ->
            text = String.trim(text || "")
            if text != "", do: IO.puts("Claude: #{text}\n")
            acc2

          %{type: :tool_use, name: name, input: input}, acc2 ->
            IO.puts("🛠️  Claude is using tool: #{name}")
            IO.puts("   Input: #{inspect(input)}\n")
            %{acc2 | tool_uses: acc2.tool_uses + 1}

          _other, acc2 ->
            acc2
        end)

      %Message{type: :user} = msg, acc ->
        Message.content_blocks(msg)
        |> Enum.reduce(acc, fn
          %{type: :tool_result, tool_use_id: tool_use_id, is_error: is_error, content: content},
          acc2 ->
            status = if is_error, do: "❌", else: "✅"
            IO.puts("#{status} Tool result (tool_use_id=#{tool_use_id})")
            IO.puts("   Content: #{inspect(content)}\n")
            %{acc2 | tool_results: acc2.tool_results + 1}

          _other, acc2 ->
            acc2
        end)

      %Message{type: :result, subtype: subtype}, acc ->
        IO.puts("\nResult: #{inspect(subtype)}")
        %{acc | result_subtype: subtype}

      _msg, acc ->
        acc
    end)

  cond do
    summary.result_subtype != :success ->
      raise "Query did not complete successfully (result subtype: #{inspect(summary.result_subtype)})"

    summary.tool_uses == 0 ->
      cli_version =
        case ClaudeAgentSDK.CLI.version() do
          {:ok, v} -> v
          _ -> "unknown"
        end

      IO.puts("\n⚠️  Warning: Claude did not use the SDK MCP tools.")

      IO.puts(
        "   This may indicate the CLI (v#{cli_version}) does not fully support SDK MCP servers."
      )

      IO.puts("   The SDK sent sdkMcpServers in the initialize request, but the CLI")
      IO.puts("   did not query the SDK for tools/list.")
      IO.puts("\n   This is a known limitation - SDK MCP support requires CLI updates.")

    summary.tool_results == 0 and summary.tool_uses > 0 ->
      raise "No MCP tool_result blocks observed; expected at least one SDK MCP tool result."

    true ->
      :ok
  end

  if summary.tool_uses > 0 do
    IO.puts("\n🎉 SDK MCP Live Demo completed successfully!")
    IO.puts("\nWhat happened:")
    IO.puts("  1. We created an SDK MCP server with 2 math tools")
    IO.puts("  2. The server was passed to Claude via mcp_servers option")
    IO.puts("  3. Claude discovered the tools via MCP 'tools/list' request")
    IO.puts("  4. Claude used the tools via MCP 'tools/call' requests")
    IO.puts("  5. Tool execution happened in-process (no subprocess overhead)")
    IO.puts("\n💡 Key Benefits:")
    IO.puts("  - Tools run in the same Elixir process")
    IO.puts("  - No subprocess spawning or IPC overhead")
    IO.puts("  - Direct access to Elixir ecosystem")
    IO.puts("  - Easier debugging and testing")
  end
rescue
  e ->
    IO.puts("\n❌ Error: #{Exception.message(e)}")
    IO.puts("\nStacktrace:")
    IO.puts(Exception.format_stacktrace(__STACKTRACE__))

    IO.puts("\n💡 Troubleshooting:")
    IO.puts("  - Ensure Claude CLI is installed: claude --version")
    IO.puts("  - Ensure you're authenticated: claude login")
    IO.puts("  - Check auth env vars: echo $ANTHROPIC_API_KEY / $CLAUDE_AGENT_OAUTH_TOKEN")

    reraise e, __STACKTRACE__
end

Support.halt_if_runner!()
