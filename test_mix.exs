#!/usr/bin/env elixir

# Simple test using Mix to properly load dependencies

IO.puts("🚀 Testing with Mix environment")

# Test 1: Check if erlexec is available in compiled environment
try do
  # Start erlexec
  Application.ensure_all_started(:erlexec)
  IO.puts("✅ Erlexec started successfully")
  
  # Test basic exec functionality
  case :exec.run("echo Hello from erlexec", [:sync, :stdout]) do
    {:ok, result} ->
      IO.puts("✅ Exec test successful: #{inspect(result)}")
    {:error, reason} ->
      IO.puts("❌ Exec test failed: #{inspect(reason)}")
  end
  
rescue
  e ->
    IO.puts("❌ Error: #{inspect(e)}")
end