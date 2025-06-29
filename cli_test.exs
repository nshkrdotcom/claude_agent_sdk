#!/usr/bin/env elixir

# Test Claude CLI directly to isolate the issue
IO.puts("🔧 Testing Claude CLI directly")

# Test 1: Check Claude version
IO.puts("\n1️⃣ Checking Claude version...")
case System.cmd("claude", ["--version"], stderr_to_stdout: true) do
  {output, 0} -> IO.puts("✅ Claude version: #{String.trim(output)}")
  {output, code} -> IO.puts("❌ Claude version failed (#{code}): #{output}")
end

# Test 2: Test simple query with timeout
IO.puts("\n2️⃣ Testing simple query with timeout...")
task = Task.async(fn ->
  System.cmd("claude", ["--output-format", "stream-json", "--verbose", "Say exactly: Test"], 
             stderr_to_stdout: true)
end)

case Task.yield(task, 12_000) do
  {:ok, {output, code}} ->
    IO.puts("✅ Claude query completed (code: #{code})")
    IO.puts("Output length: #{String.length(output)} chars")
    
    # Show first 500 chars
    preview = String.slice(output, 0, 500)
    IO.puts("Preview: #{preview}")
    
  nil ->
    IO.puts("❌ Claude query timed out")
    Task.shutdown(task, :brutal_kill)
end

# Test 3: Check auth status
IO.puts("\n3️⃣ Checking auth status...")
case System.cmd("claude", ["auth", "status"], stderr_to_stdout: true) do
  {output, 0} -> IO.puts("✅ Auth status: #{String.trim(output)}")
  {output, code} -> IO.puts("❌ Auth check failed (#{code}): #{output}")
end

IO.puts("\n🏁 CLI test completed!")