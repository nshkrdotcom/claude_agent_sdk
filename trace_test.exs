#!/usr/bin/env elixir

# Test with full tracing
IO.puts("[1] Starting trace test...")

# Load Jason first (built into Elixir)
IO.puts("[2] Loading modules...")
Code.require_file("lib/claude_code_sdk/options.ex")
Code.require_file("lib/claude_code_sdk/message.ex") 
Code.require_file("lib/claude_code_sdk/process.ex")
Code.require_file("lib/claude_code_sdk/query.ex")
Code.require_file("lib/claude_code_sdk.ex")

IO.puts("[3] Modules loaded")

# Add tracing
defmodule Tracer do
  def trace do
    IO.puts("[4] Setting up trace...")
    
    # Trace all function calls in our modules
    :dbg.start()
    :dbg.tracer()
    :dbg.p(:all, :c)
    :dbg.tpl(ClaudeCodeSDK, :_)
    :dbg.tpl(ClaudeCodeSDK.Query, :_)
    :dbg.tpl(ClaudeCodeSDK.Process, :_)
    
    IO.puts("[5] Starting query...")
    
    try do
      result = ClaudeCodeSDK.query("Hi")
      IO.puts("[6] Query returned: #{inspect(result)}")
      
      IO.puts("[7] Taking first message...")
      first = result |> Enum.take(1)
      IO.puts("[8] Got: #{inspect(first)}")
    rescue
      e ->
        IO.puts("[ERROR] #{inspect(e)}")
        IO.puts(Exception.format_stacktrace())
    end
  end
end

Tracer.trace()