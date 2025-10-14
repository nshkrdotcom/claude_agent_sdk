#!/usr/bin/env elixir

# Project Assistant - Interactive development helper (Fixed version)
# Usage: mix run examples/project_assistant_fixed.exs

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
      explain <file>        - Explain how code works
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

      {:explain, file} ->
        explain_code(file)
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
      ["explain", file] -> {:explain, file}
      ["scaffold", type] -> {:scaffold, type}
      _ -> {:error, "Invalid command format"}
    end
  end

  defp show_help do
    IO.puts("""
    🤖 Project Assistant Commands:

    File Analysis:
      analyze <file>        - Comprehensive code analysis
      explain <file>        - Code explanation and documentation

    Code Generation:
      scaffold genserver    - Generate GenServer boilerplate
      scaffold module       - Generate basic module

    Other:
      help                  - Show this help
      quit                  - Exit assistant
    """)
  end

  defp analyze_file(file_path) do
    if File.exists?(file_path) do
      IO.puts("🔍 Analyzing #{file_path}...")

      content = File.read!(file_path)

      analysis =
        ClaudeAgentSDK.query("""
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
        5. Documentation quality

        For each issue, provide specific suggestions for improvement.
        """)
        |> extract_assistant_content()

      IO.puts("\n📋 Analysis Results:")
      IO.puts("=" |> String.duplicate(50))
      IO.puts(analysis)
    else
      IO.puts("❌ File not found: #{file_path}")
    end
  end

  defp explain_code(file_path) do
    if File.exists?(file_path) do
      IO.puts("📖 Explaining #{file_path}...")

      content = File.read!(file_path)

      explanation =
        ClaudeAgentSDK.query("""
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
        5. Usage examples

        Make it educational for developers learning the codebase.
        """)
        |> extract_assistant_content()

      IO.puts("\n📖 Code Explanation:")
      IO.puts("=" |> String.duplicate(50))
      IO.puts(explanation)
    else
      IO.puts("❌ File not found: #{file_path}")
    end
  end

  defp scaffold_code(type) do
    IO.puts("🏗️ Generating #{type} boilerplate...")

    scaffold =
      case type do
        "genserver" ->
          generate_genserver_scaffold()

        "module" ->
          generate_module_scaffold()

        _ ->
          IO.puts("❌ Unknown scaffold type: #{type}")
          IO.puts("Available types: genserver, module")
          nil
      end

    if scaffold do
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
  end

  defp generate_genserver_scaffold do
    name = IO.gets("Enter GenServer name: ") |> String.trim()

    ClaudeAgentSDK.query("""
    Generate a complete GenServer module named #{name} with:

    1. Proper module structure and documentation
    2. Client API functions
    3. GenServer callbacks (init, handle_call, handle_cast, handle_info)
    4. State management example
    5. Error handling patterns

    Include comprehensive documentation and examples.
    """)
    |> extract_assistant_content()
  end

  defp generate_module_scaffold do
    name = IO.gets("Enter module name: ") |> String.trim()
    purpose = IO.gets("Enter module purpose: ") |> String.trim()

    ClaudeAgentSDK.query("""
    Generate an Elixir module named #{name} for #{purpose} with:

    1. Module documentation
    2. Public API functions
    3. Private helper functions
    4. Proper error handling
    5. Usage examples

    Make it production-ready with comprehensive documentation.
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
