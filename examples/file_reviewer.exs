#!/usr/bin/env elixir

# File Reviewer - Simple code review for individual files
# Usage: mix run examples/file_reviewer.exs <file_path>

defmodule FileReviewer do
  def review_file(file_path) do
    IO.puts("🔍 File Reviewer")
    IO.puts("Reviewing: #{file_path}")
    
    unless File.exists?(file_path) do
      IO.puts("❌ File not found: #{file_path}")
      System.halt(1)
    end
    
    content = File.read!(file_path)
    
    IO.puts("📝 File size: #{String.length(content)} characters")
    IO.puts("📡 Analyzing with Claude...")
    
    review = ClaudeCodeSDK.query("""
    Please review this code file and provide feedback:
    
    File: #{file_path}
    ```
    #{String.slice(content, 0, 2000)}#{if String.length(content) > 2000, do: "\n... (truncated)", else: ""}
    ```
    
    Focus on:
    1. Code quality and best practices
    2. Potential bugs or issues
    3. Security concerns
    4. Performance implications
    5. One specific improvement suggestion
    
    Keep feedback actionable and specific.
    """)
    |> extract_assistant_content()
    
    IO.puts("\n📝 Code Review Results:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(review)
    
    # Save review to file
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    review_file = "review_#{Path.basename(file_path, Path.extname(file_path))}_#{timestamp}.md"
    
    File.write!(review_file, """
    # Code Review - #{Path.basename(file_path)}
    
    **Generated:** #{DateTime.utc_now() |> DateTime.to_iso8601()}
    
    **File:** #{file_path}
    
    ## Review
    
    #{review}
    """)
    
    IO.puts("\n💾 Review saved to: #{review_file}")
    IO.puts("✅ Review complete!")
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
    FileReviewer.review_file(file_path)
    
  [] ->
    # Default to reviewing the main SDK file
    FileReviewer.review_file("lib/claude_code_sdk.ex")
    
  _ ->
    IO.puts("Usage: mix run examples/file_reviewer.exs [file_path]")
end