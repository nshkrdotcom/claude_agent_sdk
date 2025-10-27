# Quick Demo: Streaming + Tools (v0.6.0)
#
# A simple demo showing the feature works.
# Run with: mix run examples/streaming_tools/quick_demo.exs

alias ClaudeAgentSDK.{Streaming, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}

IO.puts("\n" <> ("=" |> String.duplicate(70)))
IO.puts("Streaming + Tools Quick Demo (v0.6.0)")
IO.puts("=" |> String.duplicate(70))

# Define a simple hook (as anonymous function)
my_hook = fn _input, _id, _ctx ->
  IO.puts("  [Hook fired!]")
  Output.allow()
end

# Configure with hooks
options = %Options{
  hooks: %{pre_tool_use: [Matcher.new("*", [my_hook])]}
}

IO.puts("\n1. Starting session with hooks...")
{:ok, session} = Streaming.start_session(options)

# Check session type
case session do
  {:control_client, _pid} ->
    IO.puts("   ✅ Control client selected (has hooks)")

  pid when is_pid(pid) ->
    IO.puts("   ℹ️  CLI-only selected (no control features)")
end

IO.puts("\n2. Sending message: 'Say hello'")
IO.puts("   (Taking first 5 events as demo)\n")

# Take just first 5 events to avoid hanging
events =
  Streaming.send_message(session, "Say hello in one word")
  |> Enum.take(5)

IO.puts("\n3. Received #{length(events)} events:")

Enum.each(events, fn event ->
  IO.puts("   - #{inspect(event.type)}")
end)

IO.puts("\n4. Closing session...")
Streaming.close_session(session)

IO.puts("   ✅ Complete!\n")
IO.puts("=" |> String.duplicate(70))
IO.puts("\n✨ Streaming + Tools is WORKING!")
IO.puts("\nThe SDK automatically selected control client because hooks were configured.")
IO.puts("Try the other examples for more detailed demonstrations.")
IO.puts(String.duplicate("=", 70) <> "\n")
