#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.Options
alias Examples.Support

Support.ensure_mock!()
Support.header!("SDK MCP Demo (mock, deterministic)")

defmodule Examples.SDKMCPDemo.MathTools do
  @moduledoc false
  use ClaudeAgentSDK.Tool

  deftool :add,
          "Adds two numbers",
          %{
            type: "object",
            properties: %{a: %{type: "number"}, b: %{type: "number"}},
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a} + #{b} = #{a + b}"}]}}
    end
  end
end

server =
  ClaudeAgentSDK.create_sdk_mcp_server(
    name: "math-tools",
    version: "1.0.0",
    tools: [Examples.SDKMCPDemo.MathTools.Add]
  )

{:ok, tools} = ClaudeAgentSDK.Tool.Registry.list_tools(server.registry_pid)
IO.puts("Registered tools: #{Enum.map(tools, & &1.name) |> Enum.join(", ")}")

{:ok, direct} = Examples.SDKMCPDemo.MathTools.Add.execute(%{"a" => 2, "b" => 3})
direct_text = direct["content"] |> hd() |> Map.fetch!("text")
IO.puts("Direct execution: #{direct_text}")

options = %Options{mcp_servers: %{"math-tools" => server}}
args = Options.to_args(options)

idx = Enum.find_index(args, &(&1 == "--mcp-config"))

# SDK MCP servers ARE passed via --mcp-config so Claude knows the tools exist
# The control protocol handles tool EXECUTION, but CLI needs server metadata
# This matches Python SDK behavior (see subprocess_cli.py lines 246-268)
if !is_integer(idx) do
  raise "Expected --mcp-config for SDK MCP servers (CLI needs to know about them)"
end

mcp_config_json = Enum.at(args, idx + 1)
mcp_config = Jason.decode!(mcp_config_json)

# Verify the config has the mcpServers wrapper and correct structure
if !Map.has_key?(mcp_config, "mcpServers") do
  raise "Expected mcpServers wrapper in --mcp-config"
end

servers = mcp_config["mcpServers"]

if !Map.has_key?(servers, "math-tools") do
  raise "Expected math-tools server in mcpServers"
end

server_config = servers["math-tools"]

if server_config["type"] != "sdk" do
  raise "Expected type=sdk for SDK MCP server"
end

# Verify registry_pid is stripped (internal only)
if Map.has_key?(server_config, "registry_pid") do
  raise "Expected registry_pid to be stripped from CLI args"
end

IO.puts("CLI args includes --mcp-config with SDK servers")
IO.puts("Server config: #{inspect(server_config)}")
IO.puts("\n✓ SDK MCP servers are emitted via --mcp-config (matching Python SDK behavior)")
