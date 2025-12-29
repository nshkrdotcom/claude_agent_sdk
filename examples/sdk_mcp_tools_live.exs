#!/usr/bin/env elixir

# SDK MCP Tools Example - In-process MCP tools (LIVE)
# Usage: mix run examples/sdk_mcp_tools_live.exs
#
# This example demonstrates:
# 1. Creating SDK MCP servers with custom tools
# 2. Registering tools using the `deftool` macro
# 3. Passing SDK MCP servers to Claude via options
# 4. Claude calling and receiving results from SDK MCP tools
#
# Prereqs:
#   - Claude CLI installed (`claude --version`)
#   - Authenticated (`claude login` or `ANTHROPIC_API_KEY`)
#
# This example mirrors the Python SDK's mcp_calculator.py example

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, Options}
alias Examples.Support

Support.ensure_live!()

# Define calculator tools using the deftool macro
defmodule Examples.CalculatorTools do
  @moduledoc false
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
              a: %{type: "number", description: "First number"},
              b: %{type: "number", description: "Second number"}
            },
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      result = a * b
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a} * #{b} = #{result}"}]}}
    end
  end
end

defmodule SDKMCPExample do
  def run do
    Support.header!("SDK MCP Tools Example")

    IO.puts("""
    This example demonstrates in-process MCP tools that run directly
    in the Elixir SDK, without requiring external subprocess servers.
    """)

    # Verify we're using real CLI
    IO.puts("\n0. Environment check:")
    IO.puts("   Mix env: #{Mix.env()}")
    IO.puts("   use_mock config: #{Application.get_env(:claude_agent_sdk, :use_mock, false)}")
    {:ok, cli_path} = ClaudeAgentSDK.CLI.find_executable()
    IO.puts("   Claude CLI: #{cli_path}")
    {:ok, cli_version} = ClaudeAgentSDK.CLI.version()
    IO.puts("   CLI version: #{cli_version}")
    IO.puts("   NOTE: Client uses Transport.Port -> real CLI (ignores use_mock)")

    # Step 1: Create SDK MCP server with calculator tools
    IO.puts("\n1. Creating SDK MCP server with calculator tools...")

    calculator_server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "calculator",
        version: "1.0.0",
        tools: [
          Examples.CalculatorTools.Add,
          Examples.CalculatorTools.Multiply
        ]
      )

    IO.puts("   Created server: #{calculator_server.name} v#{calculator_server.version}")

    # Step 2: Configure options with SDK MCP server
    # Pre-approve the calculator tools so Claude can use them without prompts
    IO.puts("\n2. Configuring Claude with SDK MCP server and allowed tools...")

    options = %Options{
      model: "haiku",
      max_turns: 5,
      mcp_servers: %{"calc" => calculator_server},
      allowed_tools: [
        "mcp__calc__add",
        "mcp__calc__multiply"
      ],
      permission_mode: :bypass_permissions
    }

    IO.puts("   Allowed tools: #{inspect(options.allowed_tools)}")

    # Step 3: Start client and make a query
    IO.puts("\n3. Starting Claude client and sending calculation request...")

    {:ok, client} = Client.start_link(options)
    Process.sleep(2000)

    prompt =
      "Calculate 15 + 27 using the add tool, then multiply the result by 2 using the multiply tool."

    IO.puts("   Prompt: #{prompt}")

    :ok = Client.send_message(client, prompt)

    # Step 4: Stream and display responses
    IO.puts("\n4. Claude's Response:")
    IO.puts(String.duplicate("-", 60))

    tool_calls = []

    tool_calls =
      Client.stream_messages(client)
      |> Enum.reduce_while(tool_calls, fn msg, acc ->
        case msg.type do
          :system ->
            mcp_servers = msg.data[:mcp_servers] || []
            tools = msg.data[:tools] || []
            mcp_tools = Enum.filter(tools, &String.starts_with?(&1, "mcp__"))
            IO.puts("[system] MCP servers: #{inspect(mcp_servers)}")
            IO.puts("[system] MCP tools available: #{inspect(mcp_tools)}")
            {:cont, acc}

          :assistant ->
            content = get_in(msg.data, [:message, "content"]) || []

            # Content can be a list of blocks
            content = if is_list(content), do: content, else: []

            Enum.each(content, fn block ->
              case block do
                %{"type" => "text", "text" => text} ->
                  IO.puts("[claude] #{text}")

                %{"type" => "tool_use", "name" => name, "input" => input} ->
                  IO.puts("[tool_use] #{name} with #{inspect(input)}")

                _ ->
                  :ok
              end
            end)

            # Track tool uses
            tool_uses = Enum.filter(content, &(is_map(&1) and &1["type"] == "tool_use"))
            {:cont, acc ++ tool_uses}

          :user ->
            content = get_in(msg.data, [:message, "content"]) || []
            content = if is_list(content), do: content, else: []

            Enum.each(content, fn block ->
              case block do
                %{"type" => "tool_result", "content" => result_content}
                when is_list(result_content) ->
                  text = Enum.find_value(result_content, fn c -> c["text"] end)
                  IO.puts("[tool_result] #{text}")

                _ ->
                  :ok
              end
            end)

            {:cont, acc}

          :result ->
            IO.puts("[result] #{msg.subtype}")
            # Stop consuming the stream after we get the result
            {:halt, acc}

          _ ->
            {:cont, acc}
        end
      end)

    IO.puts(String.duplicate("-", 60))

    # Step 5: Verify tools were called
    IO.puts("\n5. Verification:")

    if length(tool_calls) > 0 do
      IO.puts("   SDK MCP tools called: #{length(tool_calls)}")

      Enum.each(tool_calls, fn call ->
        IO.puts("   - #{call["name"]}: #{inspect(call["input"])}")
      end)

      IO.puts("\n   Example completed successfully!")
    else
      IO.puts("   Warning: No SDK MCP tools were called by Claude")
      IO.puts("   This could mean Claude found another way to answer,")
      IO.puts("   or there was an issue with tool registration.")
    end

    Client.stop(client)

    # Return the server so we can clean it up
    calculator_server
  end
end

# Run the example
server = SDKMCPExample.run()

# Clean up the registry process and force exit
# The registry and other OTP processes may keep the VM alive otherwise
GenServer.stop(server.registry_pid)
Support.halt_if_runner!()

# If not in runner mode, still need to exit cleanly
System.halt(0)
