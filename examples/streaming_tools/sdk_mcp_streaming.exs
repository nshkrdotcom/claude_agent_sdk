# Example: Streaming with SDK MCP Servers (v0.6.0)
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
# To run this example:
#   iex -S mix
#   > SDKMCPStreamingExample.run()

alias ClaudeAgentSDK.{Streaming, Options}

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
    IO.puts("=" |> String.duplicate(70))
    IO.puts("Streaming + SDK MCP Example (v0.6.0)")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("\nThis example demonstrates streaming with SDK MCP servers.")
    IO.puts("The SDK automatically selects the control client transport.")
    IO.puts("")

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
      mcp_servers: %{"math-tools" => server}
    }

    IO.puts("Starting streaming session with SDK MCP...\n")

    # Start session - automatically uses control client
    {:ok, session} = Streaming.start_session(options)

    IO.puts("✓ Session started (transport: control client with SDK MCP)\n")

    # Run a series of math problems
    problems = [
      "What is 123 + 456?",
      "Calculate 15 × 23",
      "What is the factorial of 6?"
    ]

    for {problem, idx} <- Enum.with_index(problems, 1) do
      IO.puts("\n" <> ("=" |> String.duplicate(70)))
      IO.puts("Problem #{idx}/#{length(problems)}: #{problem}")
      IO.puts("-" |> String.duplicate(70))

      # Track state
      current_text = ""
      tool_count = 0

      # Send message and stream response
      Streaming.send_message(session, problem)
      |> Stream.each(fn event ->
        case event do
          # Text streaming
          %{type: :text_delta, text: text} ->
            IO.write(text)
            current_text = current_text <> text

          # Tool events
          %{type: :tool_use_start, name: name} ->
            IO.puts("\n\n🛠️  Executing SDK MCP tool: #{name}")
            tool_count = tool_count + 1

          %{type: :tool_input_delta, json: json} ->
            # Show tool input as it streams
            if String.trim(json) != "" do
              IO.write("   Input: #{json}")
            end

          %{type: :tool_complete, tool_name: name} ->
            IO.puts("\n✅ Tool #{name} completed\n")

          # Message complete
          %{type: :message_stop} ->
            IO.puts("\n" <> ("-" |> String.duplicate(70)))
            IO.puts("✓ Problem solved (#{tool_count} tool(s) used)")

          # Errors
          %{type: :error, error: error} ->
            IO.puts("\n❌ Error: #{inspect(error)}")

          # Ignore other events
          _ ->
            :ok
        end
      end)
      |> Stream.run()

      # Brief pause between problems
      if idx < length(problems) do
        Process.sleep(500)
      end
    end

    # Close session
    Streaming.close_session(session)

    IO.puts("\n" <> ("=" |> String.duplicate(70)))
    IO.puts("✓ Session closed\n")
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
end

# Note: Run this example from IEx:
#   iex -S mix
#   iex> SDKMCPStreamingExample.run()
