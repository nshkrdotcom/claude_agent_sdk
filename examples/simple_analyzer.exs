#!/usr/bin/env elixir

# Simple Code Analyzer - Test Claude SDK with file analysis
# Usage: mix run examples/simple_analyzer.exs <file_path>
# Uses current application environment (mock by default, live in production)

alias ClaudeCodeSDK.{ContentExtractor, OptionBuilder}

# Start mock if needed
if Application.get_env(:claude_code_sdk, :use_mock, false) do
  {:ok, _} = ClaudeCodeSDK.Mock.start_link()
  IO.puts("🎭 Mock mode enabled")
else
  IO.puts("🔴 Live mode enabled")
end

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

    # Use analysis-specific options
    options = OptionBuilder.build_analysis_options()

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
    """, options)
    |> extract_assistant_content()

    IO.puts("\n📋 Analysis:")
    IO.puts("=" |> String.duplicate(40))
    IO.puts(analysis)
    IO.puts("✅ Analysis complete!")
  end

  defp extract_assistant_content(stream) do
    messages = Enum.to_list(stream)

    # Check for errors first
    error_msg = Enum.find(messages, & &1.type == :result and &1.subtype != :success)
    if error_msg do
      IO.puts("\n❌ Error (#{error_msg.subtype}):")
      if Map.has_key?(error_msg.data, :error) do
        IO.puts(error_msg.data.error)
      else
        IO.puts(inspect(error_msg.data))
      end
      System.halt(1)
    end

    # Use ContentExtractor for proper content extraction
    messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.filter(&(&1 != nil))
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
