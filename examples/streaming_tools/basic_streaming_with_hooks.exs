# Example: Streaming with Pre-Tool Hooks (v0.6.0)
#
# Demonstrates how to use streaming with hooks to monitor and control
# tool execution in real-time. The SDK automatically selects the control
# client transport when hooks are configured.
#
# Features:
# - Typewriter effect with streaming text
# - Pre-tool hook that logs tool usage
# - Real-time tool execution monitoring
# - Automatic transport selection
#
# To run this example:
#   iex -S mix
#   > StreamingHooksExample.run()

alias ClaudeAgentSDK.{Streaming, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

defmodule StreamingHooksExample do
  @moduledoc """
  Example showing streaming with hooks for security and monitoring.
  """

  # Hook callback: Log all tool usage
  def log_tool_use(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_input = input["tool_input"]

    IO.puts("\n🔧 [HOOK] Tool execution requested:")
    IO.puts("   Tool: #{tool_name}")
    IO.puts("   ID: #{tool_use_id}")
    IO.puts("   Input: #{inspect(tool_input, pretty: true, width: 60)}")

    # Allow the tool to execute
    Output.allow()
    |> Output.with_system_message("Tool usage logged for audit")
  end

  # Hook callback: Block dangerous bash commands
  def validate_bash_command(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} ->
        if dangerous_command?(cmd) do
          IO.puts("\n🚫 [SECURITY] Blocked dangerous command: #{cmd}")

          Output.deny("This command is not allowed for security reasons")
          |> Output.with_system_message("Security policy violation detected")
        else
          Output.allow()
        end

      _ ->
        Output.allow()
    end
  end

  defp dangerous_command?(cmd) do
    dangerous_patterns = [
      "rm -rf",
      "rm -fr",
      "mkfs",
      "dd if=/dev/zero",
      # Fork bomb
      ":(){:|:&};:",
      "chmod -R 777"
    ]

    Enum.any?(dangerous_patterns, &String.contains?(cmd, &1))
  end

  def run do
    IO.puts("=" |> String.duplicate(70))
    IO.puts("Streaming + Hooks Example (v0.6.0)")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("\nThis example demonstrates streaming with hooks.")
    IO.puts("The SDK automatically selects the control client transport.")
    IO.puts("")

    # Configure options with hooks
    options = %Options{
      allowed_tools: ["Bash", "Read", "Write"],
      hooks: %{
        # Log all tool usage for monitoring
        pre_tool_use: [
          Matcher.new("*", [&log_tool_use/3]),
          Matcher.new("Bash", [&validate_bash_command/3])
        ]
      }
    }

    IO.puts("Starting streaming session with hooks...\n")

    # Start session - automatically uses control client
    {:ok, session} = Streaming.start_session(options)

    IO.puts("✓ Session started (transport: control client with hooks)\n")
    IO.puts("Sending message: 'List files in the current directory'\n")
    IO.puts("-" |> String.duplicate(70))

    # Track state for display
    current_text = ""
    tool_count = 0

    # Send message and stream response
    Streaming.send_message(session, "List files in the current directory")
    |> Stream.each(fn event ->
      case event do
        # Text streaming - typewriter effect
        %{type: :text_delta, text: text} ->
          IO.write(text)
          current_text = current_text <> text

        # Tool events
        %{type: :tool_use_start, name: name} ->
          IO.puts("\n\n🛠️  Starting tool: #{name}")
          tool_count = tool_count + 1

        %{type: :tool_complete, tool_name: name, result: result} ->
          IO.puts("\n✅ Tool #{name} completed")

          if String.length(to_string(result)) < 200 do
            IO.puts("   Result: #{inspect(result)}")
          end

        # Message complete
        %{type: :message_stop} ->
          IO.puts("\n" <> ("-" |> String.duplicate(70)))
          IO.puts("\n✓ Message complete")
          IO.puts("  Total tools used: #{tool_count}")
          IO.puts("  Total text length: #{String.length(current_text)} characters")

        # Errors
        %{type: :error, error: error} ->
          IO.puts("\n❌ Error: #{inspect(error)}")

        # Other events (debug)
        _ ->
          # Uncomment to see all events:
          # IO.inspect(event, label: "Event")
          :ok
      end
    end)
    |> Stream.run()

    # Close session
    Streaming.close_session(session)

    IO.puts("\n✓ Session closed\n")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("\nKey Features Demonstrated:")
    IO.puts("  - Streaming with character-by-character text updates")
    IO.puts("  - Pre-tool hooks for logging and security")
    IO.puts("  - Automatic control client transport selection")
    IO.puts("  - Real-time tool execution monitoring")
    IO.puts("\nTry it yourself in IEx:")
    IO.puts("  iex -S mix")
    IO.puts("  > StreamingHooksExample.run()")
    IO.puts("=" |> String.duplicate(70))
  end
end

# Note: This example is meant to be run from IEx (iex -S mix)
# It cannot be run with 'mix run' or 'elixir' directly as it requires
# the compiled SDK dependencies.
#
# To run:
#   iex -S mix
#   iex> StreamingHooksExample.run()
