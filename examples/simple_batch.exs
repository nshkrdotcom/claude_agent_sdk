#!/usr/bin/env elixir

# Simple Batch Processor - Process multiple files with Claude
# Usage: mix run examples/simple_batch.exs <directory> <operation>

defmodule SimpleBatch do
  def process_directory(directory, operation) do
    IO.puts("📁 Simple Batch Processor")
    IO.puts("Directory: #{directory}")
    IO.puts("Operation: #{operation}")

    unless File.dir?(directory) do
      IO.puts("❌ Directory not found: #{directory}")
      System.halt(1)
    end

    # Find Elixir files
    files = find_elixir_files(directory)
    IO.puts("Found #{length(files)} Elixir files")

    if length(files) == 0 do
      IO.puts("No Elixir files found in #{directory}")
      System.halt(0)
    end

    # Create output directory
    output_dir = "batch_output_#{operation}"
    File.mkdir_p!(output_dir)

    IO.puts("📡 Processing files...")

    # Process each file
    results =
      Enum.with_index(files, 1)
      |> Enum.map(fn {file, index} ->
        IO.puts("\n#{index}/#{length(files)}: #{Path.basename(file)}")
        IO.puts(String.duplicate("─", 60))
        process_file(file, operation, output_dir)
      end)

    # Generate summary
    generate_summary(results, output_dir)

    IO.puts("✅ Batch processing complete!")
    IO.puts("📁 Results saved to: #{output_dir}")
  end

  defp find_elixir_files(directory) do
    Path.wildcard("#{directory}/**/*.{ex,exs}")
    |> Enum.reject(&String.contains?(&1, "test/"))
    |> Enum.reject(&String.contains?(&1, "_build/"))
    |> Enum.reject(&String.contains?(&1, "deps/"))
    # Limit to 5 files for demo
    |> Enum.take(5)
  end

  defp process_file(file_path, operation, output_dir) do
    start_time = System.monotonic_time(:millisecond)

    try do
      content = File.read!(file_path)

      prompt = build_prompt(content, file_path, operation)

      result =
        ClaudeAgentSDK.query(prompt)
        |> extract_assistant_content()

      # Save result
      output_file = create_output_file(file_path, operation, output_dir)
      File.write!(output_file, result)

      duration = System.monotonic_time(:millisecond) - start_time

      %{
        file: file_path,
        operation: operation,
        output_file: output_file,
        duration_ms: duration,
        status: :success,
        result_size: String.length(result)
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

  defp build_prompt(content, file_path, operation) do
    case operation do
      "analyze" ->
        """
        Analyze this Elixir code file:

        File: #{file_path}
        ```elixir
        #{String.slice(content, 0, 1000)}#{if String.length(content) > 1000, do: "\n... (truncated)", else: ""}
        ```

        Provide:
        1. What this module does
        2. Key functions
        3. One improvement suggestion

        Keep it concise.
        """

      "comment" ->
        """
        Add helpful comments to this Elixir code:

        File: #{file_path}
        ```elixir
        #{String.slice(content, 0, 800)}#{if String.length(content) > 800, do: "\n... (truncated)", else: ""}
        ```

        Return the code with added:
        1. Module documentation
        2. Function documentation
        3. Inline comments for complex logic

        Keep original functionality intact.
        """

      "document" ->
        """
        Generate documentation for this Elixir module:

        File: #{file_path}
        ```elixir
        #{String.slice(content, 0, 1000)}#{if String.length(content) > 1000, do: "\n... (truncated)", else: ""}
        ```

        Create:
        1. Module overview
        2. Function descriptions
        3. Usage examples

        Format as Markdown.
        """

      _ ->
        "Analyze this code file: #{file_path}\n\n```elixir\n#{String.slice(content, 0, 1000)}\n```"
    end
  end

  defp create_output_file(input_path, operation, output_dir) do
    basename = Path.basename(input_path, Path.extname(input_path))

    extension =
      case operation do
        "document" -> ".md"
        _ -> "_#{operation}.txt"
      end

    Path.join(output_dir, "#{basename}#{extension}")
  end

  defp extract_assistant_content(stream) do
    text_content =
      stream
      |> Stream.filter(&(&1.type == :assistant))
      |> Stream.flat_map(fn msg ->
        content = msg.data.message["content"]

        cond do
          is_binary(content) ->
            # Direct text content
            [content]

          is_list(content) ->
            # Array of content blocks - extract only text blocks
            content
            |> Enum.filter(&(is_map(&1) and Map.get(&1, "type") == "text"))
            |> Enum.map(&Map.get(&1, "text", ""))

          true ->
            []
        end
      end)
      |> Enum.join("\n")

    # Print to console
    IO.puts(text_content)
    IO.puts("")

    # Return for file saving
    text_content
  end

  defp generate_summary(results, output_dir) do
    successful = Enum.count(results, &(&1.status == :success))
    failed = length(results) - successful
    total_duration = Enum.sum(Enum.map(results, &(&1[:duration_ms] || 0)))

    summary = """
    # Batch Processing Summary

    **Generated:** #{DateTime.utc_now() |> DateTime.to_iso8601()}

    ## Statistics
    - Total files: #{length(results)}
    - Successful: #{successful}
    - Failed: #{failed}
    - Total duration: #{Float.round(total_duration / 1000, 2)}s

    ## Results
    #{Enum.map_join(results, "\n", fn result ->
      status = if result.status == :success, do: "✅", else: "❌"
      "#{status} #{Path.basename(result.file)} (#{result[:duration_ms] || 0}ms)"
    end)}

    ## Files Processed
    #{Enum.map_join(results, "\n", fn result -> if result.status == :success do
        "- #{result.file} → #{result.output_file}"
      else
        "- #{result.file} → ERROR: #{result[:error] || "Unknown"}"
      end end)}
    """

    File.write!(Path.join(output_dir, "summary.md"), summary)

    IO.puts("\n📊 Summary:")
    IO.puts("   Total: #{length(results)} files")
    IO.puts("   ✅ Success: #{successful}")
    IO.puts("   ❌ Failed: #{failed}")
    IO.puts("   ⏱️  Time: #{Float.round(total_duration / 1000, 2)}s")
  end
end

# CLI interface
case System.argv() do
  [directory, operation] ->
    SimpleBatch.process_directory(directory, operation)

  [directory] ->
    SimpleBatch.process_directory(directory, "analyze")

  [] ->
    SimpleBatch.process_directory("lib/", "analyze")

  _ ->
    IO.puts("""
    Usage:
      mix run examples/simple_batch.exs <directory> <operation>
      
    Operations:
      analyze   - Analyze code quality
      comment   - Add comments to code
      document  - Generate documentation
      
    Examples:
      mix run examples/simple_batch.exs lib/ analyze
      mix run examples/simple_batch.exs lib/ document
    """)
end
