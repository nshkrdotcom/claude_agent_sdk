#!/usr/bin/env elixir

# Simple test - just say hi
Code.require_file("lib/claude_code_sdk/options.ex")
Code.require_file("lib/claude_code_sdk/message.ex")
Code.require_file("lib/claude_code_sdk/process.ex")
Code.require_file("lib/claude_code_sdk/query.ex")
Code.require_file("lib/claude_code_sdk.ex")

# Remove debug output
:ok = :io.setopts([{:encoding, :unicode}])

IO.puts("Testing SDK...")

ClaudeCodeSDK.query("Say 'Hi!' and nothing else")
|> Stream.take(10)
|> Enum.each(fn msg ->
  case msg.type do
    :assistant ->
      IO.puts("\nClaude: #{msg.data.message["content"]}")
    :result ->
      if msg.subtype == :success do
        IO.puts("\n✓ Success!")
      else
        IO.puts("\n✗ Error (#{msg.subtype}):")
        if Map.has_key?(msg.data, :error) do
          IO.puts(msg.data.error)
        else
          IO.puts(inspect(msg.data))
        end
      end
    _ ->
      :ok
  end
end)
