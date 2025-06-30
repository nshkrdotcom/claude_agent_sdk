#!/usr/bin/env elixir

# Standalone Claude Code SDK test script
# This isolates the SDK issue from the pipeline system

Mix.install([
  {:claude_code_sdk, path: "/home/home/p/g/n/claude_code_sdk_elixir"},
  {:jason, "~> 1.4"}
])

defmodule ClaudeSDKTest do
  @moduledoc """
  Standalone test to isolate Claude Code SDK parsing issue
  """

  require Logger

  def run_test do
    IO.puts("🧪 Claude Code SDK Standalone Test")
    IO.puts("=" |> String.duplicate(50))
    
    # Check Claude CLI availability
    case System.find_executable("claude") do
      nil ->
        IO.puts("❌ Claude CLI not found")
        System.halt(1)
      claude_path ->
        IO.puts("✅ Claude CLI found at: #{claude_path}")
    end

    # Check Claude CLI version
    case System.cmd("claude", ["--version"]) do
      {version_output, 0} ->
        IO.puts("✅ Claude CLI version: #{String.trim(version_output)}")
      {error, _} ->
        IO.puts("❌ Could not get Claude version: #{error}")
        System.halt(1)
    end

    IO.puts("")
    IO.puts("🔧 Testing minimal Claude Code SDK call...")
    
    # Test 1: Minimal SDK options
    test_minimal_sdk()
    
    IO.puts("")
    IO.puts("🔧 Testing Claude CLI directly...")
    
    # Test 2: Direct CLI call to see raw output
    test_claude_cli_direct()
    
    IO.puts("")
    IO.puts("🔧 Testing SDK with different options...")
    
    # Test 3: Different SDK options
    test_sdk_variations()
  end

  defp test_minimal_sdk do
    IO.puts("Test 1: Minimal ClaudeCodeSDK.query call")
    
    try do
      # Most basic possible options
      options = ClaudeCodeSDK.Options.new(
        max_turns: 1,
        output_format: :text,
        verbose: false
      )
      
      prompt = "What is 2+2? Answer with just the number."
      
      IO.puts("  Calling ClaudeCodeSDK.query with minimal options...")
      IO.puts("  Prompt: #{prompt}")
      IO.puts("  Options: #{inspect(options)}")
      
      # Try to get just the first message
      stream = ClaudeCodeSDK.query(prompt, options)
      IO.puts("  Stream created successfully")
      
      IO.puts("  Attempting to read first message...")
      first_message = Enum.take(stream, 1)
      
      IO.puts("✅ Success! First message: #{inspect(first_message)}")
      
    rescue
      error ->
        IO.puts("❌ Error in minimal SDK test:")
        IO.puts("   #{Exception.message(error)}")
        IO.puts("   Stacktrace:")
        Exception.format_stacktrace(__STACKTRACE__)
        |> String.split("\n")
        |> Enum.take(5)
        |> Enum.each(&IO.puts("     #{&1}"))
    end
  end

  defp test_claude_cli_direct do
    IO.puts("Test 2: Direct Claude CLI call to inspect raw output")
    
    args = [
      "--print",
      "--output-format", "json", 
      "--max-turns", "1",
      "What is 2+2? Answer with just the number."
    ]
    
    IO.puts("  Command: claude #{Enum.join(args, " ")}")
    
    try do
      case System.cmd("claude", args, stderr_to_stdout: true) do
        {output, 0} ->
          IO.puts("✅ Claude CLI succeeded")
          IO.puts("  Raw output length: #{String.length(output)} characters")
          IO.puts("  First 500 chars:")
          IO.puts("  " <> String.slice(output, 0, 500))
          
          # Try to parse each line as JSON
          parse_claude_output(output)
          
        {error_output, exit_code} ->
          IO.puts("❌ Claude CLI failed with exit code #{exit_code}")
          IO.puts("  Error output: #{error_output}")
      end
    rescue
      error ->
        IO.puts("❌ Error calling Claude CLI directly:")
        IO.puts("   #{Exception.message(error)}")
    end
  end

  defp parse_claude_output(output) do
    IO.puts("\n  🔍 Analyzing Claude CLI JSON output:")
    
    lines = String.split(output, "\n")
    IO.puts("    Total lines: #{length(lines)}")
    
    lines
    |> Enum.with_index()
    |> Enum.each(fn {line, index} ->
      if String.trim(line) != "" do
        IO.puts("    Line #{index}: #{String.slice(line, 0, 100)}#{if String.length(line) > 100, do: "...", else: ""}")
        
        case Jason.decode(line) do
          {:ok, json} ->
            IO.puts("      ✅ Valid JSON")
            IO.puts("      Keys: #{inspect(Map.keys(json))}")
            if Map.has_key?(json, "type") do
              IO.puts("      Type: #{json["type"]}")
            end
            
          {:error, reason} ->
            IO.puts("      ❌ Invalid JSON: #{inspect(reason)}")
        end
      end
    end)
  end

  defp test_sdk_variations do
    IO.puts("Test 3: SDK with different configurations")
    
    # Test different option combinations
    test_configs = [
      %{
        name: "JSON output format",
        options: ClaudeCodeSDK.Options.new(
          max_turns: 1,
          output_format: :json,
          verbose: false
        )
      },
      %{
        name: "Text output format", 
        options: ClaudeCodeSDK.Options.new(
          max_turns: 1,
          output_format: :text,
          verbose: true
        )
      },
      %{
        name: "Stream JSON format",
        options: ClaudeCodeSDK.Options.new(
          max_turns: 1,
          output_format: :stream_json,
          verbose: false
        )
      }
    ]
    
    prompt = "Hello! Just say 'Hi' back."
    
    Enum.each(test_configs, fn %{name: name, options: options} ->
      IO.puts("  Testing: #{name}")
      IO.puts("    Options: #{inspect(options)}")
      
      try do
        stream = ClaudeCodeSDK.query(prompt, options)
        messages = Enum.take(stream, 3)  # Take max 3 messages
        IO.puts("    ✅ Success! Got #{length(messages)} message(s)")
        
        messages
        |> Enum.with_index()
        |> Enum.each(fn {msg, idx} ->
          IO.puts("      Message #{idx}: #{inspect(msg, limit: 2)}")
        end)
        
      rescue
        error ->
          IO.puts("    ❌ Failed: #{Exception.message(error)}")
      end
      
      IO.puts("")
    end)
  end
end

# Run the test
ClaudeSDKTest.run_test()
