#!/usr/bin/env elixir

# Simple Code Analyzer - Test Claude SDK with file analysis
# Usage: mix run examples/simple_analyzer.exs <file_path>

defmodule SimpleAnalyzer do
  def analyze_file(file_path) do
    IO.puts("🔍 Simple Code Analyzer")
    IO.puts("Analyzing: #{file_path}")
    
    unless File.exists?(file_path) do
      IO.puts("❌ File not found: #{file_path}")
      System.halt(1)
    end
    
    content = File.read!(file_path)
    
    IO.puts("📝 File size: #{String.length(content)} characters")
    IO.puts("📡 Sending to Claude...")
    
    analysis = ClaudeCodeSDK.query("""
    Analyze this code file and provide a brief summary:
    
    File: #{file_path}
    ```
    #{String.slice(content, 0, 1500)}#{if String.length(content) > 1500, do: "\n... (truncated)", else: ""}
    ```
    
    Provide:
    1. What this code does (1-2 sentences)
    2. Main functions or components
    3. One key improvement suggestion
    
    Keep it concise.
    """)
    |> extract_assistant_content()
    
    IO.puts("\n📋 Analysis:")
    IO.puts("=" |> String.duplicate(40))
    IO.puts(analysis)
    IO.puts("✅ Analysis complete!")
  end
  
  defp extract_assistant_content(stream) do
    stream
    |> Stream.filter(&(&1.type == :assistant))
    |> Stream.map(fn msg ->
      case msg.data.message do
        %{"content" => text} when is_binary(text) -> text
        %{"content" => [%{"text" => text}]} -> text
        other -> inspect(other)
      end
    end)
    |> Enum.join("\n")
  end
end

# CLI interface
case System.argv() do
  [file_path] ->
    SimpleAnalyzer.analyze_file(file_path)
    
  [] ->
    # Default to analyzing the main SDK file
    SimpleAnalyzer.analyze_file("lib/claude_code_sdk.ex")
    
  _ ->
    IO.puts("Usage: mix run examples/simple_analyzer.exs [file_path]")
end