#!/usr/bin/env elixir

# Test Claude CLI directly to isolate the issue
IO.puts("🔧 Testing Claude CLI directly")

# Test 1: Check Claude version
IO.puts("\n1️⃣ Checking Claude version...")
case System.cmd("claude", ["--version"], stderr_to_stdout: true) do
  {output, 0} -> IO.puts("✅ Claude version: #{String.trim(output)}")
  {output, code} -> IO.puts("❌ Claude version failed (#{code}): #{output}")
end

# Test 2: Test simple query (should fail fast)
IO.puts("\n2️⃣ Testing simple query...")
case System.cmd("claude", ["--output-format", "stream-json", "--verbose", "Say exactly: Test"],
                stderr_to_stdout: true) do
  {output, 0} ->
    IO.puts("✅ Claude query succeeded")
    IO.puts("Output length: #{String.length(output)} chars")
    preview = String.slice(output, 0, 500)
    IO.puts("Preview: #{preview}")

  {output, code} ->
    IO.puts("❌ Claude query failed (code: #{code})")
    # Try to parse and format JSON from output
    if String.contains?(output, "{") do
      IO.puts("Formatted output:")
      output
      |> String.split("\n")
      |> Enum.filter(& &1 != "" and String.contains?(&1, "{"))
      |> Enum.each(fn line ->
        try do
          case Jason.decode(line) do
            {:ok, parsed} -> IO.puts(Jason.encode!(parsed, pretty: true))
            {:error, _} -> IO.puts(line)
          end
        rescue
          _ -> IO.puts(line)
        end
      end)
    else
      IO.puts("Raw output: #{output}")
    end
end

# Test 3: Check auth status
IO.puts("\n3️⃣ Checking auth status...")
case System.cmd("claude", ["auth", "status"], stderr_to_stdout: true) do
  {output, 0} -> IO.puts("✅ Auth status: #{String.trim(output)}")
  {output, code} -> IO.puts("❌ Auth check failed (#{code}): #{output}")
end

IO.puts("\n🏁 CLI test completed!")
