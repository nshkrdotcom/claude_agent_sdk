#!/usr/bin/env elixir

IO.puts("=== DEBUG TEST START ===")

# Load modules with logging
IO.puts("Loading options...")
Code.require_file("lib/claude_code_sdk/options.ex")

IO.puts("Loading message...")
Code.require_file("lib/claude_code_sdk/message.ex")

IO.puts("Loading process...")
Code.require_file("lib/claude_code_sdk/process.ex")

IO.puts("Loading query...")
Code.require_file("lib/claude_code_sdk/query.ex")

IO.puts("Loading main SDK...")
Code.require_file("lib/claude_code_sdk.ex")

IO.puts("\nAll modules loaded. Starting test...\n")

# Simple query
try do
  IO.puts("Calling ClaudeCodeSDK.query...")
  stream = ClaudeCodeSDK.query("Hi")
  
  IO.puts("\nStream created. Type: #{inspect(stream)}")
  
  IO.puts("\nTrying to take 1 message...")
  messages = stream |> Enum.take(1)
  
  IO.puts("\nGot messages: #{inspect(messages)}")
rescue
  e ->
    IO.puts("\n!!! ERROR: #{inspect(e)}")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end

IO.puts("\n=== DEBUG TEST END ===")