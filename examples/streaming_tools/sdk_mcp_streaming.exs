#!/usr/bin/env elixir

# Example: Streaming with SDK MCP Servers (live)
#
# Demonstrates how to use streaming with SDK MCP servers for in-process
# tool execution. The SDK automatically selects the control client transport
# when SDK MCP servers are configured.
#
# Features:
# - Streaming with SDK MCP tools
# - In-process tool execution (no subprocess overhead)
# - Real-time tool usage monitoring
# - Automatic transport selection
#
#
# Run: mix run examples/streaming_tools/sdk_mcp_streaming.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Streaming, Options}
alias Examples.Support

defmodule MathTools do
  @moduledoc """
  SDK MCP server with mathematical operations.
  """
  use ClaudeAgentSDK.Tool

  deftool :add,
          "Adds two numbers together",
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
      IO.puts("  [Calculator] Computing: #{a} + #{b} = #{result}")

      {:ok,
       %{
         "content" => [
           %{"type" => "text", "text" => "The sum of #{a} and #{b} is #{result}"}
         ]
       }}
    end
  end

  deftool :multiply,
          "Multiplies two numbers together",
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
      IO.puts("  [Calculator] Computing: #{a} × #{b} = #{result}")

      {:ok,
       %{
         "content" => [
           %{"type" => "text", "text" => "The product of #{a} and #{b} is #{result}"}
         ]
       }}
    end
  end

  deftool :factorial,
          "Calculates the factorial of a number",
          %{
            type: "object",
            properties: %{
              n: %{type: "integer", description: "Number to calculate factorial of", minimum: 0}
            },
            required: ["n"]
          } do
    def execute(%{"n" => n}) when n >= 0 do
      result = calculate_factorial(n)
      IO.puts("  [Calculator] Computing: #{n}! = #{result}")

      {:ok,
       %{
         "content" => [
           %{"type" => "text", "text" => "The factorial of #{n} is #{result}"}
         ]
       }}
    end

    defp calculate_factorial(0), do: 1
    defp calculate_factorial(n), do: n * calculate_factorial(n - 1)
  end
end

defmodule SDKMCPStreamingExample do
  @moduledoc """
  Example showing streaming with SDK MCP servers.
  """

  def run do
    Support.ensure_live!()
    Support.header!("Streaming + SDK MCP Example (live)")
    IO.puts("\nThis example demonstrates streaming with SDK MCP servers.\n")

    # Create SDK MCP server
    IO.puts("Creating SDK MCP server with math tools...\n")

    server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "math-tools",
        version: "1.0.0",
        tools: [MathTools.Add, MathTools.Multiply, MathTools.Factorial]
      )

    IO.puts("✓ SDK MCP server created with 3 tools:")
    IO.puts("  - add(a, b)")
    IO.puts("  - multiply(a, b)")
    IO.puts("  - factorial(n)")
    IO.puts("")

    # Configure options with SDK MCP server
    options = %Options{
      mcp_servers: %{"math-tools" => server},
      model: "haiku",
      max_turns: 2,
      allowed_tools: []
    }

    IO.puts("Starting streaming session with SDK MCP...\n")

    # Start session - automatically uses control client
    {:ok, session} = Streaming.start_session(options)

    try do
      IO.puts("✓ Session started (transport: control client with SDK MCP)\n")
      IO.puts("-" |> String.duplicate(70))

      prompt = """
      Use the provided `math-tools` MCP tools (add, multiply, factorial) to answer:

      1) What is 123 + 456?
      2) What is 15 × 23?
      3) What is the factorial of 6?

      Use tools for each calculation and show the results.
      """

      {tool_use_starts, tool_completes} =
        Streaming.send_message(session, prompt)
        |> Enum.reduce_while({0, 0}, fn event, {starts, completes} ->
          case event do
            %{type: :text_delta, text: text} ->
              IO.write(text)
              {:cont, {starts, completes}}

            %{type: :tool_use_start, name: name} ->
              IO.puts("\n\n🛠️  Executing SDK MCP tool: #{name}")
              {:cont, {starts + 1, completes}}

            %{type: :tool_input_delta, json: json} ->
              if String.trim(json) != "" do
                IO.write("   Input: #{json}")
              end

              {:cont, {starts, completes}}

            %{type: :tool_complete, tool_name: name} ->
              IO.puts("\n✅ Tool #{name} completed\n")
              {:cont, {starts, completes + 1}}

            %{type: :message_stop} ->
              IO.puts("\n" <> ("-" |> String.duplicate(70)))
              IO.puts("✓ Message complete (tool_use_start=#{starts}, tool_complete=#{completes})")
              {:halt, {starts, completes}}

            %{type: :error, error: error} ->
              raise "Streaming error: #{inspect(error)}"

            _ ->
              {:cont, {starts, completes}}
          end
        end)

      # Check if SDK MCP tools were actually used (not Task/other built-in tools)
      # If Claude uses Task instead of SDK MCP tools, that's a CLI limitation
      sdk_mcp_used = tool_use_starts > 0 and tool_completes > 0

      cond do
        tool_use_starts < 1 ->
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

        tool_completes < 1 and tool_use_starts > 0 ->
          # Claude used tools but they didn't complete - likely used Task which requires
          # longer execution. This indicates SDK MCP tools weren't recognized.
          cli_version =
            case ClaudeAgentSDK.CLI.version() do
              {:ok, v} -> v
              _ -> "unknown"
            end

          IO.puts(
            "\n⚠️  Warning: Claude used built-in tools (like Task) instead of SDK MCP tools."
          )

          IO.puts(
            "   This may indicate the CLI (v#{cli_version}) does not fully support SDK MCP servers."
          )

          IO.puts("   The SDK sent sdkMcpServers in the initialize request, but the CLI")
          IO.puts("   did not recognize them as available tools.")
          IO.puts("\n   This is a known limitation - SDK MCP support requires CLI updates.")

        true ->
          :ok
      end

      IO.puts("\n" <> ("=" |> String.duplicate(70)))
      IO.puts("✓ Session closed\n")

      if sdk_mcp_used do
        IO.puts("=" |> String.duplicate(70))
        IO.puts("\nKey Features Demonstrated:")
        IO.puts("  - Streaming with SDK MCP servers")
        IO.puts("  - In-process tool execution (no subprocess overhead)")
        IO.puts("  - Real-time tool input/output streaming")
        IO.puts("  - Automatic control client transport selection")
        IO.puts("  - Multiple tool executions in sequence")
        IO.puts("\nSDK MCP Benefits:")
        IO.puts("  - Tools run in same Elixir process")
        IO.puts("  - No IPC overhead")
        IO.puts("  - Easy debugging and testing")
        IO.puts("  - Direct access to your application state")
        IO.puts("\nTry it yourself in IEx:")
        IO.puts("  iex -S mix")
        IO.puts("  > SDKMCPStreamingExample.run()")
        IO.puts("=" |> String.duplicate(70))
      end
    after
      Streaming.close_session(session)
    end
  end
end

# Auto-run when executed with mix run
SDKMCPStreamingExample.run()
Support.halt_if_runner!()
