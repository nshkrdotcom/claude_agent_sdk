#!/usr/bin/env elixir

# Minimal test with debugging
IO.puts("Starting...")

Code.require_file("lib/claude_code_sdk/options.ex")
Code.require_file("lib/claude_code_sdk/message.ex")
Code.require_file("lib/claude_code_sdk/process.ex")
Code.require_file("lib/claude_code_sdk/query.ex")
Code.require_file("lib/claude_code_sdk.ex")

IO.puts("Modules loaded")

# Add debug logging to Process module
defmodule Debug do
  def test do
    IO.puts("\n=== DEBUG TEST ===")
    IO.puts("Time: #{DateTime.utc_now()}")

    # Test 1: Check CLI directly
    IO.puts("\n1. Testing claude CLI directly...")
    case System.cmd("claude", ["--version"], stderr_to_stdout: true) do
      {output, 0} -> IO.puts("✓ CLI works: #{String.trim(output)}")
      {error, _} -> IO.puts("✗ CLI error: #{error}")
    end

    # Test 2: Simple query with full debugging
    IO.puts("\n2. Testing SDK query...")
    prompt = "Say hi"
    opts = %ClaudeCodeSDK.Options{output_format: :stream_json}
    args = ["--print", "--output-format", "stream-json", prompt]

    IO.puts("Command: claude #{Enum.join(args, " ")}")
    IO.puts("Starting at: #{:os.system_time(:millisecond)}")

    # Hook into the process
    start_time = :os.system_time(:millisecond)
    count = 0

    try do
      ClaudeCodeSDK.query(prompt, opts)
      |> Stream.take(5)  # Limit messages
      |> Enum.each(fn msg ->
        elapsed = :os.system_time(:millisecond) - start_time
        case msg.type do
          :result when msg.subtype != :success ->
            IO.puts("\n[#{elapsed}ms] ❌ Error (#{msg.subtype}):")
            if Map.has_key?(msg.data, :error) do
              IO.puts(msg.data.error)
            else
              IO.puts(inspect(msg.data))
            end
          _ ->
            IO.puts("\n[#{elapsed}ms] Got #{msg.type}: #{inspect(msg, limit: 50)}")
        end
      end)
    catch
      kind, error ->
        IO.puts("\nError: #{kind} - #{inspect(error)}")
    end

    IO.puts("\nDone")
  end
end

Debug.test()
