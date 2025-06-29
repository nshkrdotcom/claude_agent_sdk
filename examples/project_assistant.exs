#!/usr/bin/env elixir

# Project Assistant - Interactive development helper
# Usage: mix run examples/project_assistant.exs

defmodule ProjectAssistant do
  @moduledoc """
  Interactive development assistant for Elixir projects.
  Provides code analysis, suggestions, and pair programming capabilities.
  """

  def start_interactive_session do
    IO.puts("""
    🤖 Project Assistant - Interactive Development Helper
    ====================================================
    
    Available commands:
      analyze <file>        - Analyze a file for improvements
      refactor <file>       - Get refactoring suggestions
      debug <file>          - Help debug issues
      optimize <file>       - Performance optimization suggestions
      test <file>           - Generate test suggestions
      explain <file>        - Explain how code works
      compare <file1> <file2> - Compare two files
      scaffold <type>       - Generate boilerplate code
      quit                  - Exit assistant
    
    Type 'help' for more details.
    """)
    
    interactive_loop()
  end
  
  defp interactive_loop do
    input = IO.gets("🤖 > ") |> String.trim()
    
    case parse_command(input) do
      {:quit} ->
        IO.puts("👋 Goodbye!")
        
      {:help} ->
        show_help()
        interactive_loop()
        
      {:analyze, file} ->
        analyze_file(file)
        interactive_loop()
        
      {:refactor, file} ->
        suggest_refactoring(file)
        interactive_loop()
        
      {:debug, file} ->
        debug_assistance(file)
        interactive_loop()
        
      {:optimize, file} ->
        optimize_suggestions(file)
        interactive_loop()
        
      {:test, file} ->
        test_suggestions(file)
        interactive_loop()
        
      {:explain, file} ->
        explain_code(file)
        interactive_loop()
        
      {:compare, file1, file2} ->
        compare_files(file1, file2)
        interactive_loop()
        
      {:scaffold, type} ->
        scaffold_code(type)
        interactive_loop()
        
      {:error, message} ->
        IO.puts("❌ #{message}")
        interactive_loop()
        
      _ ->
        IO.puts("❓ Unknown command. Type 'help' for available commands.")
        interactive_loop()
    end
  end
  
  defp parse_command(input) do
    case String.split(input, " ", parts: 3) do
      ["quit"] -> {:quit}
      ["help"] -> {:help}
      ["analyze", file] -> {:analyze, file}
      ["refactor", file] -> {:refactor, file}
      ["debug", file] -> {:debug, file}
      ["optimize", file] -> {:optimize, file}
      ["test", file] -> {:test, file}
      ["explain", file] -> {:explain, file}
      ["compare", file1, file2] -> {:compare, file1, file2}
      ["scaffold", type] -> {:scaffold, type}
      _ -> {:error, "Invalid command format"}
    end
  end
  
  defp show_help do
    IO.puts("""
    🤖 Project Assistant Commands:
    
    File Analysis:
      analyze <file>        - Comprehensive code analysis
      refactor <file>       - Refactoring opportunities
      debug <file>          - Debug assistance and issue detection
      optimize <file>       - Performance optimization suggestions
      test <file>           - Test generation and coverage analysis
      explain <file>        - Code explanation and documentation
    
    Comparison:
      compare <file1> <file2> - Compare two files for differences
    
    Code Generation:
      scaffold genserver    - Generate GenServer boilerplate
      scaffold supervisor   - Generate Supervisor boilerplate
      scaffold liveview     - Generate LiveView component
      scaffold module       - Generate basic module
      scaffold test         - Generate test template
    
    Other:
      help                  - Show this help
      quit                  - Exit assistant
    """)
  end
  
  defp analyze_file(file_path) do
    if File.exists?(file_path) do
      IO.puts("🔍 Analyzing #{file_path}...")
      
      content = File.read!(file_path)
    
    analysis = ClaudeCodeSDK.query("""
    Analyze this Elixir file for code quality and provide actionable feedback:
    
    File: #{file_path}
    ```elixir
    #{content}
    ```
    
    Provide analysis on:
    1. Code structure and organization
    2. Naming conventions and clarity
    3. Error handling patterns
    4. Performance considerations
    5. Security concerns
    6. Maintainability issues
    7. Documentation quality
    8. Test coverage gaps
    
    For each issue, provide specific suggestions for improvement.
    """)
    |> extract_assistant_content()
    
    IO.puts("\n📋 Analysis Results:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(analysis)
  end
  
  defp suggest_refactoring(file_path) do
    unless File.exists?(file_path) do
      IO.puts("❌ File not found: #{file_path}")
      :error
    end
    
    IO.puts("🔄 Generating refactoring suggestions for #{file_path}...")
    
    content = File.read!(file_path)
    
    suggestions = ClaudeCodeSDK.query("""
    Suggest specific refactoring improvements for this Elixir code:
    
    File: #{file_path}
    ```elixir
    #{content}
    ```
    
    Focus on:
    1. Function decomposition and single responsibility
    2. Code duplication elimination
    3. Pattern matching improvements
    4. Data structure optimization
    5. Error handling enhancement
    6. Module boundary improvements
    7. Performance optimizations
    
    For each suggestion:
    - Explain the current issue
    - Show the improved code
    - Explain the benefits
    - Estimate the effort required
    """)
    |> extract_assistant_content()
    
    IO.puts("\n🔄 Refactoring Suggestions:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(suggestions)
  end
  
  defp debug_assistance(file_path) do
    unless File.exists?(file_path) do
      IO.puts("❌ File not found: #{file_path}")
      :error
    end
    
    IO.puts("🐛 Analyzing #{file_path} for potential issues...")
    
    content = File.read!(file_path)
    
    debug_help = ClaudeCodeSDK.query("""
    Help debug this Elixir code by identifying potential issues:
    
    File: #{file_path}
    ```elixir
    #{content}
    ```
    
    Look for:
    1. Common Elixir pitfalls and anti-patterns
    2. Potential runtime errors
    3. Memory leaks or resource issues
    4. Concurrency problems
    5. Logic errors in pattern matching
    6. Improper error handling
    7. State management issues
    
    For each issue:
    - Explain what could go wrong
    - Show how to reproduce the issue
    - Provide the fix
    - Suggest debugging strategies
    """)
    |> extract_assistant_content()
    
    IO.puts("\n🐛 Debug Analysis:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(debug_help)
  end
  
  defp optimize_suggestions(file_path) do
    unless File.exists?(file_path) do
      IO.puts("❌ File not found: #{file_path}")
      :error
    end
    
    IO.puts("⚡ Analyzing #{file_path} for performance optimizations...")
    
    content = File.read!(file_path)
    
    optimizations = ClaudeCodeSDK.query("""
    Suggest performance optimizations for this Elixir code:
    
    File: #{file_path}
    ```elixir
    #{content}
    ```
    
    Focus on:
    1. Algorithm efficiency improvements
    2. Memory usage optimization
    3. Concurrency and parallelization opportunities
    4. Database query optimization
    5. Stream processing improvements
    6. Caching strategies
    7. Hot path optimizations
    
    For each optimization:
    - Identify the bottleneck
    - Explain the performance impact
    - Show the optimized code
    - Provide benchmarking suggestions
    """)
    |> extract_assistant_content()
    
    IO.puts("\n⚡ Performance Optimizations:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(optimizations)
  end
  
  defp test_suggestions(file_path) do
    unless File.exists?(file_path) do
      IO.puts("❌ File not found: #{file_path}")
      :error
    end
    
    IO.puts("🧪 Analyzing #{file_path} for test improvements...")
    
    content = File.read!(file_path)
    
    test_advice = ClaudeCodeSDK.query("""
    Analyze this Elixir code and suggest testing improvements:
    
    File: #{file_path}
    ```elixir
    #{content}
    ```
    
    Provide:
    1. Test coverage analysis
    2. Missing test scenarios
    3. Edge cases to test
    4. Property-based testing opportunities
    5. Integration testing needs
    6. Mocking strategies for dependencies
    7. Performance testing suggestions
    
    Include specific test case examples for the most critical functions.
    """)
    |> extract_assistant_content()
    
    IO.puts("\n🧪 Testing Suggestions:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(test_advice)
  end
  
  defp explain_code(file_path) do
    unless File.exists?(file_path) do
      IO.puts("❌ File not found: #{file_path}")
      :error
    end
    
    IO.puts("📖 Explaining #{file_path}...")
    
    content = File.read!(file_path)
    
    explanation = ClaudeCodeSDK.query("""
    Explain how this Elixir code works in detail:
    
    File: #{file_path}
    ```elixir
    #{content}
    ```
    
    Provide:
    1. High-level purpose and functionality
    2. Step-by-step breakdown of key functions
    3. Data flow and transformations
    4. Design patterns used
    5. Dependencies and their roles
    6. Error handling strategy
    7. Performance characteristics
    8. Usage examples
    
    Make it educational and comprehensive for developers learning the codebase.
    """)
    |> extract_assistant_content()
    
    IO.puts("\n📖 Code Explanation:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(explanation)
  end
  
  defp compare_files(file1, file2) do
    unless File.exists?(file1) and File.exists?(file2) do
      IO.puts("❌ One or both files not found: #{file1}, #{file2}")
      :error
    end
    
    IO.puts("🔍 Comparing #{file1} and #{file2}...")
    
    content1 = File.read!(file1)
    content2 = File.read!(file2)
    
    comparison = ClaudeCodeSDK.query("""
    Compare these two Elixir files and analyze their differences:
    
    File 1: #{file1}
    ```elixir
    #{content1}
    ```
    
    File 2: #{file2}
    ```elixir
    #{content2}
    ```
    
    Analyze:
    1. Functional differences
    2. Code style variations
    3. Performance implications
    4. Maintainability comparison
    5. Which approach is better and why
    6. Opportunities to merge or consolidate
    7. Common patterns and differences
    
    Provide actionable recommendations.
    """)
    |> extract_assistant_content()
    
    IO.puts("\n🔍 File Comparison:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(comparison)
  end
  
  defp scaffold_code(type) do
    IO.puts("🏗️ Generating #{type} boilerplate...")
    
    scaffold = case type do
      "genserver" -> generate_genserver_scaffold()
      "supervisor" -> generate_supervisor_scaffold()
      "liveview" -> generate_liveview_scaffold()
      "module" -> generate_module_scaffold()
      "test" -> generate_test_scaffold()
      _ ->
        IO.puts("❌ Unknown scaffold type: #{type}")
        IO.puts("Available types: genserver, supervisor, liveview, module, test")
        :error
    end
    
    IO.puts("\n🏗️ Generated Code:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts(scaffold)
    
    # Ask if user wants to save to file
    save_choice = IO.gets("💾 Save to file? (y/N): ") |> String.trim() |> String.downcase()
    
    if save_choice in ["y", "yes"] do
      filename = IO.gets("📁 Enter filename: ") |> String.trim()
      File.write!(filename, scaffold)
      IO.puts("✅ Saved to #{filename}")
    end
  end
  
  defp generate_genserver_scaffold do
    name = IO.gets("Enter GenServer name: ") |> String.trim()
    
    ClaudeCodeSDK.query("""
    Generate a complete GenServer module named #{name} with:
    
    1. Proper module structure and documentation
    2. Client API functions
    3. GenServer callbacks (init, handle_call, handle_cast, handle_info)
    4. State management example
    5. Error handling patterns
    6. Supervision tree integration
    7. Common GenServer patterns (synchronous/asynchronous calls)
    
    Include comprehensive documentation and examples.
    """)
    |> extract_assistant_content()
  end
  
  defp generate_supervisor_scaffold do
    name = IO.gets("Enter Supervisor name: ") |> String.trim()
    
    ClaudeCodeSDK.query("""
    Generate a Supervisor module named #{name} with:
    
    1. Proper supervision strategy
    2. Child specifications
    3. Dynamic child management
    4. Restart strategies
    5. Documentation and examples
    6. Integration with application tree
    
    Include examples of common supervision patterns.
    """)
    |> extract_assistant_content()
  end
  
  defp generate_liveview_scaffold do
    name = IO.gets("Enter LiveView component name: ") |> String.trim()
    
    ClaudeCodeSDK.query("""
    Generate a Phoenix LiveView component named #{name} with:
    
    1. Mount and handle_event callbacks
    2. State management
    3. Template with form handling
    4. Real-time updates
    5. Error handling
    6. Testing setup
    
    Include common LiveView patterns and best practices.
    """)
    |> extract_assistant_content()
  end
  
  defp generate_module_scaffold do
    name = IO.gets("Enter module name: ") |> String.trim()
    purpose = IO.gets("Enter module purpose: ") |> String.trim()
    
    ClaudeCodeSDK.query("""
    Generate an Elixir module named #{name} for #{purpose} with:
    
    1. Module documentation
    2. Public API functions
    3. Private helper functions
    4. Proper error handling
    5. Type specifications
    6. Usage examples
    7. Best practices for the domain
    
    Make it production-ready with comprehensive documentation.
    """)
    |> extract_assistant_content()
  end
  
  defp generate_test_scaffold do
    module_name = IO.gets("Enter module to test: ") |> String.trim()
    
    ClaudeCodeSDK.query("""
    Generate an ExUnit test module for #{module_name} with:
    
    1. Proper test module structure
    2. Setup and teardown functions
    3. Test cases for common scenarios
    4. Edge case testing
    5. Property-based test examples
    6. Mock patterns for external dependencies
    7. Integration test examples
    
    Follow ExUnit best practices and naming conventions.
    """)
    |> extract_assistant_content()
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

# Start the interactive session
ProjectAssistant.start_interactive_session()