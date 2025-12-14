# Example: Streaming with Pre-Tool Hooks (v0.6.0)
#
# Demonstrates how to use streaming with hooks to monitor and control
# tool execution in real-time.
#
# Run with: mix run examples/streaming_tools/basic_streaming_with_hooks.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Streaming, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias Examples.Support

defmodule StreamingHooksExample do
  # Hook callback: Log all tool usage
  def log_tool_use(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_input = input["tool_input"]

    IO.puts("\n🔧 [HOOK] Tool execution requested:")
    IO.puts("   Tool: #{tool_name}")
    IO.puts("   ID: #{tool_use_id}")
    IO.puts("   Input: #{inspect(tool_input, pretty: true, width: 60)}")

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
        else
          Output.allow()
        end

      _ ->
        Output.allow()
    end
  end

  defp dangerous_command?(cmd) do
    dangerous = ["rm -rf", "mkfs", "dd if=/dev/zero", ":(){:|:&};:"]
    Enum.any?(dangerous, &String.contains?(cmd, &1))
  end

  def run do
    Support.ensure_live!()

    IO.puts("=" |> String.duplicate(70))
    IO.puts("Streaming + Hooks Example (v0.6.0)")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("\nThis example demonstrates streaming with hooks.")
    IO.puts("The SDK automatically selects the control client transport.\n")

    # Configure options with hooks
    options = %Options{
      model: "haiku",
      max_turns: 2,
      permission_mode: :default,
      tools: ["Bash"],
      allowed_tools: ["Bash"],
      hooks: %{
        pre_tool_use: [
          Matcher.new("*", [&log_tool_use/3]),
          Matcher.new("Bash", [&validate_bash_command/3])
        ]
      }
    }

    IO.puts("Starting streaming session with hooks...\n")

    # Start session - automatically uses control client
    {:ok, session} = Streaming.start_session(options)

    try do
      IO.puts("✓ Session started (transport: control client)\n")
      IO.puts("Sending: 'List the files in the current directory'\n")
      IO.puts("-" |> String.duplicate(70))

      summary =
        Streaming.send_message(session, "List the files in the current directory")
        |> Enum.reduce_while(%{tool_use_starts: 0, message_stop: false}, fn event, acc ->
          case event do
            %{type: :text_delta, text: text} ->
              IO.write(text)
              {:cont, acc}

            %{type: :tool_use_start, name: name} ->
              IO.puts("\n\n🛠️  Tool: #{name}")
              {:cont, %{acc | tool_use_starts: acc.tool_use_starts + 1}}

            %{type: :message_stop} ->
              IO.puts("\n" <> ("-" |> String.duplicate(70)))
              IO.puts("\n✓ Message complete")
              {:halt, %{acc | message_stop: true}}

            %{type: :error, error: reason} ->
              raise "Streaming error: #{inspect(reason)}"

            _ ->
              {:cont, acc}
          end
        end)

      if summary.tool_use_starts < 1 do
        raise "Expected at least 1 tool_use_start event, but saw #{summary.tool_use_starts}."
      end

      if summary.message_stop != true do
        raise "Expected message_stop event, but did not observe one."
      end
    after
      Streaming.close_session(session)
      IO.puts("\n✓ Session closed")
      IO.puts("=" |> String.duplicate(70))
    end
  end
end

# Auto-run when executed with mix run
StreamingHooksExample.run()
Support.halt_if_runner!()
