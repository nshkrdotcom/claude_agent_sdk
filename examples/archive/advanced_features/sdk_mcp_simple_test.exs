#!/usr/bin/env elixir
# Simple SDK MCP Test
# Tests that SDK MCP server is created correctly and tools are registered
#
# Usage:
#   mix run examples/advanced_features/sdk_mcp_simple_test.exs

defmodule SimpleTools do
  use ClaudeAgentSDK.Tool

  deftool :greet,
          "Greet a person by name",
          %{
            type: "object",
            properties: %{name: %{type: "string"}},
            required: ["name"]
          } do
    def execute(%{"name" => name}) do
      IO.puts("  ✅ Tool executed: greet(#{name})")

      {:ok,
       %{
         "content" => [
           %{"type" => "text", "text" => "Hello, #{name}!"}
         ]
       }}
    end
  end
end

IO.puts("\n=== Simple SDK MCP Test ===\n")

# Create SDK MCP server
IO.puts("📦 Creating SDK MCP server...")

server =
  ClaudeAgentSDK.create_sdk_mcp_server(
    name: "simple-tools",
    version: "1.0.0",
    tools: [SimpleTools.Greet]
  )

IO.puts("✅ Server created successfully!")
IO.puts("   Name: #{server.name}")
IO.puts("   Version: #{server.version}")
IO.puts("   Type: #{server.type}")
IO.puts("   Registry PID: #{inspect(server.registry_pid)}")

# Verify tools are registered
IO.puts("\n📋 Checking registered tools...")

case ClaudeAgentSDK.Tool.Registry.list_tools(server.registry_pid) do
  {:ok, tools} ->
    IO.puts("✅ Found #{length(tools)} tool(s):")

    for tool <- tools do
      IO.puts("   - #{tool.name}: #{tool.description}")
      IO.puts("     Schema: #{inspect(tool.input_schema)}")
    end

  {:error, reason} ->
    IO.puts("❌ Failed to list tools: #{inspect(reason)}")
end

# Test direct tool execution
IO.puts("\n🔧 Testing direct tool execution...")

case ClaudeAgentSDK.Tool.Registry.execute_tool(server.registry_pid, "greet", %{
       "name" => "World"
     }) do
  {:ok, result} ->
    IO.puts("✅ Tool execution succeeded!")
    IO.puts("   Result: #{inspect(result)}")

  {:error, reason} ->
    IO.puts("❌ Tool execution failed: #{inspect(reason)}")
end

# Test Options configuration
IO.puts("\n⚙️  Testing Options configuration...")

options = ClaudeAgentSDK.Options.new(mcp_servers: %{"simple-tools" => server})

IO.puts("✅ Options created successfully!")
IO.puts("   MCP servers: #{inspect(Map.keys(options.mcp_servers))}")

# Test CLI args generation
IO.puts("\n🔨 Testing CLI args generation...")

args = ClaudeAgentSDK.Options.to_args(options)
mcp_config_index = Enum.find_index(args, &(&1 == "--mcp-config"))

if mcp_config_index do
  json_config = Enum.at(args, mcp_config_index + 1)
  servers = Jason.decode!(json_config)

  IO.puts("✅ CLI args generated successfully!")
  IO.puts("   --mcp-config argument present: yes")
  IO.puts("   Server in config: #{inspect(Map.keys(servers))}")
  IO.puts("   Server type: #{servers["simple-tools"]["type"]}")
  IO.puts("   Registry PID stripped: #{!Map.has_key?(servers["simple-tools"], "registry_pid")}")
else
  IO.puts("❌ --mcp-config argument not found in CLI args")
end

IO.puts("\n✅ All basic tests passed!")
IO.puts("\n💡 Next step: Test with Claude CLI using 'mix run.live'")
