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
      allowed_tools: [
        "mcp__math-tools__add",
        "mcp__math-tools__multiply",
        "mcp__math-tools__factorial"
      ],
      permission_mode: :bypass_permissions
    }

    IO.puts("Starting streaming session with SDK MCP...\n")

    # Start session - automatically uses control client
    {:ok, session} = Streaming.start_session(options)

    try do
      if not match?({:control_client, _pid}, session) do
        raise "Expected control client session, got: #{inspect(session)}"
      end

      IO.puts("✓ Session started (transport: control client with SDK MCP)\n")
      IO.puts("-" |> String.duplicate(70))

      prompt = """
      Use the provided `math-tools` MCP tools (add, multiply, factorial) to answer:

      1) What is 123 + 456?
      2) What is 15 × 23?
      3) What is the factorial of 6?

      Use tools for each calculation and show the results.
      """

      # Track tool usage - SDK MCP tools emit tool_use_start but results come via
      # control protocol, not as streaming tool_complete events
      summary =
        Streaming.send_message(session, prompt)
        |> Enum.reduce_while(
          %{
            tool_use_starts: 0,
            sdk_mcp_tools_used: false,
            current_tool: nil,
            tool_input: "",
            current_block: nil,
            message_complete: false
          },
          fn event, state ->
            state = maybe_flush_tool_input(state, event)

            case event do
              %{type: :text_delta, text: text} ->
                IO.write(text)
                {:cont, state}

              %{type: :tool_use_start, name: name} ->
                # Check if this is an SDK MCP tool (prefixed with mcp__)
                is_sdk_mcp = String.starts_with?(name, "mcp__")
                IO.puts("\n\n🛠️  Executing SDK MCP tool: #{name}")

                {:cont,
                 %{
                   state
                   | tool_use_starts: state.tool_use_starts + 1,
                     sdk_mcp_tools_used: state.sdk_mcp_tools_used or is_sdk_mcp,
                     current_tool: name,
                     tool_input: "",
                     current_block: :tool
                 }}

              %{type: :tool_input_delta, json: json} ->
                {:cont, %{state | tool_input: state.tool_input <> json}}

              %{type: :text_block_start} ->
                {:cont, %{state | current_block: :text}}

              %{type: :thinking_start} ->
                {:cont, %{state | current_block: :thinking}}

              %{type: :content_block_stop} ->
                next_state =
                  if state.current_block == :tool do
                    %{flush_tool_input(state) | current_block: nil, current_tool: nil}
                  else
                    %{state | current_block: nil}
                  end

                {:cont, next_state}

              %{type: :tool_complete, tool_name: name} ->
                IO.puts("\n✅ Tool #{name} completed\n")
                {:cont, state}

              %{type: :message_stop} ->
                final_state = %{
                  flush_tool_input(state)
                  | message_complete: true,
                    current_tool: nil
                }

                IO.puts("\n" <> ("-" |> String.duplicate(70)))

                IO.puts(
                  "✓ Message complete (tool_use_start=#{final_state.tool_use_starts}, sdk_mcp_used=#{final_state.sdk_mcp_tools_used})"
                )

                {:halt, final_state}

              %{type: :error, error: error} ->
                raise "Streaming error: #{inspect(error)}"

              _ ->
                {:cont, state}
            end
          end
        )

      if not summary.message_complete do
        raise "Stream ended without message_stop."
      end

      if summary.tool_use_starts < 1 do
        raise "Expected at least one tool_use_start event, but observed none."
      end

      if not summary.sdk_mcp_tools_used do
        raise "Expected SDK MCP tools to be used, but observed none."
      end

      if String.trim(summary.tool_input) != "" do
        raise "Incomplete tool input JSON observed: #{inspect(summary.tool_input)}"
      end

      # SDK MCP tools are considered used if we saw mcp__* prefixed tool names
      IO.puts("\n" <> ("=" |> String.duplicate(70)))
      IO.puts("✓ Session closed\n")

      if summary.sdk_mcp_tools_used do
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

  defp maybe_flush_tool_input(state, %{type: :tool_use_start}) do
    state = flush_tool_input(state)

    if String.trim(state.tool_input) != "" do
      raise "Incomplete tool input JSON before next tool: #{inspect(state.tool_input)}"
    end

    state
  end

  defp maybe_flush_tool_input(state, _event), do: state

  defp flush_tool_input(%{tool_input: input} = state) do
    trimmed = String.trim(input)

    if trimmed == "" do
      state
    else
      case Jason.decode(trimmed) do
        {:ok, value} ->
          formatted = Jason.encode!(value)

          label =
            case state.current_tool do
              nil -> "   Input: "
              tool_name -> "   Input (#{tool_name}): "
            end

          IO.puts("\n#{label}#{formatted}")
          %{state | tool_input: ""}

        {:error, _} ->
          state
      end
    end
  end
end

# Auto-run when executed with mix run
SDKMCPStreamingExample.run()
Support.halt_if_runner!()
