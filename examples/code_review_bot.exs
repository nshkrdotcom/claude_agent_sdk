#!/usr/bin/env elixir

# Code Review Bot - Automated code review for Git commits
# Usage: mix run examples/code_review_bot.exs

defmodule CodeReviewBot do
  @moduledoc """
  Automated code review bot that analyzes Git commits and provides feedback.
  """

  def review_latest_commit do
    IO.puts("🔍 Code Review Bot - Analyzing latest commit...")
    
    # Get the latest commit diff
    {diff, 0} = System.cmd("git", ["diff", "HEAD~1", "HEAD"])
    
    if String.trim(diff) == "" do
      IO.puts("No changes in latest commit")
    else
    
    # Analyze the diff with Claude
    review = ClaudeCodeSDK.query("""
    Please review this Git commit diff and provide feedback:
    
    ```diff
    #{diff}
    ```
    
    Focus on:
    1. Code quality and best practices
    2. Potential bugs or issues
    3. Security concerns
    4. Performance implications
    5. Maintainability
    
    Provide specific, actionable feedback with line references where possible.
    """)
    |> extract_assistant_content()
    
    IO.puts("\n📝 Code Review Results:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(review)
    
    # Save review to file
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    review_file = "code_review_#{timestamp}.md"
    
    File.write!(review_file, """
    # Code Review - #{timestamp}
    
    ## Commit Diff
    ```diff
    #{diff}
    ```
    
    ## Review
    #{review}
    """)
    
    IO.puts("\n💾 Review saved to: #{review_file}")
  end
  
  def review_pull_request(pr_number) do
    IO.puts("🔍 Reviewing Pull Request ##{pr_number}...")
    
    # Get PR diff (requires gh CLI)
    case System.cmd("gh", ["pr", "diff", "#{pr_number}"]) do
      {diff, 0} ->
        review_diff(diff, "PR ##{pr_number}")
      {error, _} ->
        IO.puts("❌ Error getting PR diff: #{error}")
        IO.puts("Make sure 'gh' CLI is installed and authenticated")
    end
  end
  
  def review_file(file_path) do
    IO.puts("🔍 Reviewing file: #{file_path}")
    
    content = File.read!(file_path)
    
    review = ClaudeCodeSDK.query("""
    Please review this #{Path.extname(file_path)} file:
    
    File: #{file_path}
    ```
    #{content}
    ```
    
    Provide feedback on:
    1. Code structure and organization
    2. Naming conventions
    3. Error handling
    4. Documentation quality
    5. Test coverage needs
    6. Refactoring opportunities
    """)
    |> extract_assistant_content()
    
    IO.puts("\n📝 File Review:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(review)
  end
  
  def review_directory(dir_path) do
    IO.puts("🔍 Reviewing directory: #{dir_path}")
    
    # Find all source files
    files = Path.wildcard("#{dir_path}/**/*.{ex,exs,js,ts,py,rb}")
    
    IO.puts("Found #{length(files)} files to review...")
    
    # Review each file and collect issues
    all_reviews = Enum.map(files, fn file ->
      IO.puts("   Reviewing #{file}...")
      content = File.read!(file)
      
      review = ClaudeCodeSDK.query("""
      Quick code review for: #{file}
      
      ```
      #{String.slice(content, 0, 2000)}#{if String.length(content) > 2000, do: "\n... (truncated)", else: ""}
      ```
      
      Identify only critical issues:
      1. Security vulnerabilities
      2. Major bugs
      3. Performance bottlenecks
      
      Be concise and specific.
      """)
      |> extract_assistant_content()
      
      {file, review}
    end)
    
    # Generate summary
    summary = generate_directory_summary(all_reviews)
    
    IO.puts("\n📋 Directory Review Summary:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(summary)
  end
  
  defp generate_directory_summary(reviews) do
    all_issues = Enum.map_join(reviews, "\n\n", fn {file, review} ->
      "### #{Path.basename(file)}\n#{review}"
    end)
    
    ClaudeCodeSDK.query("""
    Summarize these code review findings:
    
    #{all_issues}
    
    Create:
    1. Executive summary of overall code quality
    2. Top 5 critical issues to fix immediately
    3. Recommended improvement priorities
    4. Overall assessment score (1-10)
    """)
    |> extract_assistant_content()
  end
  
  defp review_diff(diff, context) do
    review = ClaudeCodeSDK.query("""
    Review this code diff for #{context}:
    
    ```diff
    #{diff}
    ```
    
    Provide feedback on:
    1. Code quality of changes
    2. Potential impact on existing code
    3. Testing recommendations
    4. Deployment considerations
    """)
    |> extract_assistant_content()
    
    IO.puts("\n📝 Review Results:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(review)
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
  ["commit"] -> 
    CodeReviewBot.review_latest_commit()
    
  ["pr", pr_number] -> 
    CodeReviewBot.review_pull_request(pr_number)
    
  ["file", file_path] -> 
    CodeReviewBot.review_file(file_path)
    
  ["dir", dir_path] -> 
    CodeReviewBot.review_directory(dir_path)
    
  [] ->
    CodeReviewBot.review_latest_commit()
    
  _ ->
    IO.puts("""
    Usage:
      mix run examples/code_review_bot.exs                # Review latest commit
      mix run examples/code_review_bot.exs commit         # Review latest commit  
      mix run examples/code_review_bot.exs pr 123         # Review PR #123
      mix run examples/code_review_bot.exs file path.ex   # Review specific file
      mix run examples/code_review_bot.exs dir lib/       # Review directory
    """)
end