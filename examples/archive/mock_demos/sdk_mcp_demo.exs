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

if is_integer(idx) do
  raise "Did not expect --mcp-config for SDK MCP servers (they are carried via the control protocol)"
end

IO.inspect(args, label: "CLI args (SDK MCP omitted)")
IO.puts("\n✓ SDK MCP servers are not emitted as --mcp-config (control protocol handles them)")
