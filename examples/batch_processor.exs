#!/usr/bin/env elixir

# Batch Processor - Process multiple files or tasks with Claude
# Usage: mix run examples/batch_processor.exs

defmodule BatchProcessor do
  @moduledoc """
  Batch processing utilities for applying Claude operations to multiple files or tasks.
  """

  def process_directory(directory, operation, options \\ []) do
    IO.puts("📁 Processing directory: #{directory}")
    IO.puts("🔧 Operation: #{operation}")
    
    files = find_source_files(directory)
    IO.puts("Found #{length(files)} files to process")
    
    # Configure processing options
    concurrency = Keyword.get(options, :concurrency, 3)
    rate_limit = Keyword.get(options, :rate_limit_ms, 1000)
    output_dir = Keyword.get(options, :output_dir, "output")
    
    File.mkdir_p!(output_dir)
    
    # Process files with controlled concurrency
    results = if concurrency > 1 do
      process_files_concurrent(files, operation, concurrency, output_dir)
    else
      process_files_sequential(files, operation, rate_limit, output_dir)
    end
    
    # Generate summary report
    generate_summary_report(results, output_dir)
    
    IO.puts("✅ Batch processing completed!")
  end
  
  defp find_source_files(directory) do
    extensions = [".ex", ".exs", ".js", ".ts", ".py", ".rb", ".java", ".cpp", ".c", ".h"]
    
    extensions
    |> Enum.flat_map(fn ext ->
      Path.wildcard("#{directory}/**/*#{ext}")
    end)
    |> Enum.reject(&String.contains?(&1, "node_modules"))
    |> Enum.reject(&String.contains?(&1, ".git"))
    |> Enum.reject(&String.contains?(&1, "_build"))
    |> Enum.reject(&String.contains?(&1, "deps"))
  end
  
  defp process_files_concurrent(files, operation, concurrency, output_dir) do
    IO.puts("🚀 Processing #{length(files)} files with concurrency: #{concurrency}")
    
    files
    |> Task.async_stream(
      fn file ->
        process_single_file(file, operation, output_dir)
      end,
      max_concurrency: concurrency,
      timeout: 120_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
    end)
  end
  
  defp process_files_sequential(files, operation, rate_limit, output_dir) do
    IO.puts("🐌 Processing #{length(files)} files sequentially with #{rate_limit}ms delay")
    
    files
    |> Enum.with_index()
    |> Enum.map(fn {file, index} ->
      IO.puts("Processing #{index + 1}/#{length(files)}: #{Path.basename(file)}")
      
      result = process_single_file(file, operation, output_dir)
      
      # Rate limiting
      if index < length(files) - 1 do
        Process.sleep(rate_limit)
      end
      
      result
    end)
  end
  
  defp process_single_file(file_path, operation, output_dir) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      content = File.read!(file_path)
      
      # Apply the operation using Claude
      result = apply_operation(content, file_path, operation)
      
      # Save result
      output_file = create_output_path(file_path, output_dir, operation)
      File.write!(output_file, result)
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      %{
        file: file_path,
        operation: operation,
        output_file: output_file,
        duration_ms: duration,
        status: :success,
        size_input: String.length(content),
        size_output: String.length(result)
      }
      
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        %{
          file: file_path,
          operation: operation,
          duration_ms: duration,
          status: :error,
          error: inspect(error)
        }
    end
  end
  
  defp apply_operation(content, file_path, operation) do
    prompt = case operation do
      "code_review" ->
        """
        Perform a code review for this file:
        
        File: #{file_path}
        ```
        #{content}
        ```
        
        Provide:
        1. Overall code quality assessment
        2. Specific issues and improvements
        3. Security concerns
        4. Performance recommendations
        5. Best practice violations
        """
        
      "add_comments" ->
        """
        Add comprehensive comments to this code:
        
        File: #{file_path}
        ```
        #{content}
        ```
        
        Add:
        1. Module/class level documentation
        2. Function/method documentation
        3. Inline comments for complex logic
        4. Type annotations where applicable
        5. Usage examples
        
        Return the fully commented code.
        """
        
      "generate_tests" ->
        """
        Generate comprehensive test cases for this code:
        
        File: #{file_path}
        ```
        #{content}
        ```
        
        Generate:
        1. Unit tests for all functions
        2. Edge case tests
        3. Error condition tests
        4. Integration tests where applicable
        5. Property-based tests if relevant
        
        Use appropriate testing framework for the language.
        """
        
      "refactor" ->
        """
        Refactor this code for better quality:
        
        File: #{file_path}
        ```
        #{content}
        ```
        
        Improve:
        1. Code structure and organization
        2. Function decomposition
        3. Naming conventions
        4. Error handling
        5. Performance optimizations
        6. Remove code duplication
        
        Return the refactored code with explanations.
        """
        
      "security_audit" ->
        """
        Perform a security audit of this code:
        
        File: #{file_path}
        ```
        #{content}
        ```
        
        Identify:
        1. Security vulnerabilities
        2. Input validation issues
        3. Authentication/authorization problems
        4. Data exposure risks
        5. Injection attack vectors
        6. Cryptographic issues
        
        Provide specific remediation steps.
        """
        
      "optimize" ->
        """
        Optimize this code for performance:
        
        File: #{file_path}
        ```
        #{content}
        ```
        
        Focus on:
        1. Algorithm efficiency
        2. Memory usage optimization
        3. Concurrency improvements
        4. Database query optimization
        5. Caching opportunities
        6. Hot path optimizations
        
        Return optimized code with performance analysis.
        """
        
      "document" ->
        """
        Generate comprehensive documentation for this code:
        
        File: #{file_path}
        ```
        #{content}
        ```
        
        Create:
        1. API documentation
        2. Usage examples
        3. Configuration options
        4. Architecture overview
        5. Troubleshooting guide
        6. Development setup instructions
        
        Format as Markdown documentation.
        """
        
      _ ->
        "Analyze this code file: #{file_path}\n\n```\n#{content}\n```"
    end
    
    ClaudeCodeSDK.query(prompt)
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
  
  defp create_output_path(input_path, output_dir, operation) do
    basename = Path.basename(input_path, Path.extname(input_path))
    extension = case operation do
      "document" -> ".md"
      "generate_tests" -> "_test#{Path.extname(input_path)}"
      _ -> "_#{operation}#{Path.extname(input_path)}"
    end
    
    Path.join(output_dir, "#{basename}#{extension}")
  end
  
  defp generate_summary_report(results, output_dir) do
    IO.puts("📊 Generating summary report...")
    
    # Calculate statistics
    total_files = length(results)
    successful = Enum.count(results, &(&1.status == :success))
    failed = total_files - successful
    total_duration = Enum.sum(Enum.map(results, & &1[:duration_ms] || 0))
    avg_duration = if total_files > 0, do: total_duration / total_files, else: 0
    
    # Group by operation
    by_operation = Enum.group_by(results, & &1.operation)
    
    # Generate detailed report
    report = """
    # Batch Processing Report
    
    Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    
    ## Summary
    - Total files processed: #{total_files}
    - Successful: #{successful}
    - Failed: #{failed}
    - Total duration: #{total_duration}ms
    - Average duration per file: #{Float.round(avg_duration, 2)}ms
    
    ## Results by Operation
    #{Enum.map_join(by_operation, "\n\n", fn {operation, op_results} ->
      successful_op = Enum.count(op_results, &(&1.status == :success))
      failed_op = length(op_results) - successful_op
      
      "### #{String.capitalize(operation)}\n" <>
      "- Files: #{length(op_results)}\n" <>
      "- Successful: #{successful_op}\n" <>
      "- Failed: #{failed_op}"
    end)}
    
    ## Detailed Results
    #{Enum.map_join(results, "\n", fn result ->
      status_icon = if result.status == :success, do: "✅", else: "❌"
      "#{status_icon} #{Path.basename(result.file)} (#{result.duration_ms}ms)"
    end)}
    
    ## Failed Files
    #{results
      |> Enum.filter(&(&1.status == :error))
      |> Enum.map_join("\n", fn result ->
        "❌ #{result.file}: #{result[:error] || "Unknown error"}"
      end)}
    """
    
    report_file = Path.join(output_dir, "batch_report.md")
    File.write!(report_file, report)
    
    IO.puts("📊 Report saved to: #{report_file}")
    
    # Print summary to console
    IO.puts("\n📊 Processing Summary:")
    IO.puts("   Total: #{total_files} files")
    IO.puts("   ✅ Success: #{successful}")
    IO.puts("   ❌ Failed: #{failed}")
    IO.puts("   ⏱️  Total time: #{Float.round(total_duration / 1000, 2)}s")
  end
  
  def process_task_list(task_file, options \\ []) do
    IO.puts("📋 Processing task list: #{task_file}")
    
    tasks = File.read!(task_file)
            |> String.split("\n")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    
    IO.puts("Found #{length(tasks)} tasks to process")
    
    output_dir = Keyword.get(options, :output_dir, "task_results")
    File.mkdir_p!(output_dir)
    
    results = tasks
              |> Enum.with_index()
              |> Enum.map(fn {task, index} ->
                IO.puts("Processing task #{index + 1}/#{length(tasks)}: #{String.slice(task, 0, 50)}...")
                process_single_task(task, index, output_dir)
              end)
    
    generate_task_summary(results, output_dir)
  end
  
  defp process_single_task(task, index, output_dir) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = ClaudeCodeSDK.query(task)
                |> Stream.filter(&(&1.type == :assistant))
                |> Stream.map(fn msg ->
                  case msg.data.message do
                    %{"content" => text} when is_binary(text) -> text
                    %{"content" => [%{"text" => text}]} -> text
                    other -> inspect(other)
                  end
                end)
                |> Enum.join("\n")
      
      output_file = Path.join(output_dir, "task_#{String.pad_leading("#{index + 1}", 3, "0")}.md")
      task_content = """
      # Task #{index + 1}
      
      ## Prompt
      #{task}
      
      ## Response
      #{result}
      
      Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}
      """
      
      File.write!(output_file, task_content)
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      %{
        task: task,
        index: index,
        output_file: output_file,
        duration_ms: duration,
        status: :success,
        result_length: String.length(result)
      }
      
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        %{
          task: task,
          index: index,
          duration_ms: duration,
          status: :error,
          error: inspect(error)
        }
    end
  end
  
  defp generate_task_summary(results, output_dir) do
    successful = Enum.count(results, &(&1.status == :success))
    failed = length(results) - successful
    total_duration = Enum.sum(Enum.map(results, & &1.duration_ms))
    
    summary = """
    # Task Processing Summary
    
    Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    
    ## Statistics
    - Total tasks: #{length(results)}
    - Successful: #{successful}
    - Failed: #{failed}
    - Total duration: #{Float.round(total_duration / 1000, 2)}s
    
    ## Task Results
    #{Enum.map_join(results, "\n", fn result ->
      status = if result.status == :success, do: "✅", else: "❌"
      task_preview = String.slice(result.task, 0, 50)
      "#{status} Task #{result.index + 1}: #{task_preview}... (#{result.duration_ms}ms)"
    end)}
    """
    
    File.write!(Path.join(output_dir, "task_summary.md"), summary)
  end
end

# CLI interface
case System.argv() do
  ["dir", directory, operation] ->
    BatchProcessor.process_directory(directory, operation)
    
  ["dir", directory, operation, "--concurrent", concurrency] ->
    {conc, _} = Integer.parse(concurrency)
    BatchProcessor.process_directory(directory, operation, concurrency: conc)
    
  ["tasks", task_file] ->
    BatchProcessor.process_task_list(task_file)
    
  [] ->
    IO.puts("""
    Usage:
      mix run examples/batch_processor.exs dir <directory> <operation>              # Process directory
      mix run examples/batch_processor.exs dir lib/ code_review                     # Review all files
      mix run examples/batch_processor.exs dir src/ add_comments --concurrent 3     # Add comments with concurrency
      mix run examples/batch_processor.exs tasks tasks.txt                          # Process task list
    
    Available operations:
      code_review     - Perform code reviews
      add_comments    - Add documentation and comments
      generate_tests  - Generate test suites
      refactor        - Refactor code for quality
      security_audit  - Security vulnerability analysis
      optimize        - Performance optimization
      document        - Generate documentation
    """)
    
  _ ->
    IO.puts("❌ Invalid arguments. Use no arguments to see usage.")
end