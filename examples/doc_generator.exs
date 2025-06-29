#!/usr/bin/env elixir

# Documentation Generator - Generate comprehensive API documentation
# Usage: mix run examples/doc_generator.exs lib/

defmodule DocGenerator do
  @moduledoc """
  Generates comprehensive documentation for Elixir projects.
  """

  def generate_docs(source_path) do
    IO.puts("📚 Generating documentation for: #{source_path}")
    
    # Find all Elixir files
    elixir_files = find_elixir_files(source_path)
    IO.puts("Found #{length(elixir_files)} Elixir files")
    
    # Analyze each module
    module_docs = Enum.map(elixir_files, &analyze_module/1)
    
    # Generate comprehensive documentation
    generate_api_reference(module_docs, source_path)
    generate_getting_started_guide(module_docs, source_path)
    generate_examples_guide(module_docs, source_path)
    generate_architecture_overview(module_docs, source_path)
    
    IO.puts("✅ Documentation generated successfully!")
  end
  
  defp find_elixir_files(path) do
    Path.wildcard("#{path}/**/*.{ex,exs}")
    |> Enum.reject(&String.contains?(&1, "test/"))
    |> Enum.reject(&String.ends_with?(&1, "_test.exs"))
  end
  
  defp analyze_module(file_path) do
    IO.puts("📖 Analyzing: #{file_path}")
    
    content = File.read!(file_path)
    
    # Extract module structure
    module_info = ClaudeCodeSDK.query("""
    Analyze this Elixir module and extract structured information:
    
    File: #{file_path}
    ```elixir
    #{content}
    ```
    
    Extract:
    1. Module name and purpose (from @moduledoc)
    2. All public functions with their signatures and @doc strings
    3. Types and specs defined (@type, @spec)
    4. Key dependencies and imports
    5. GenServer callbacks or other behaviors
    6. Configuration options or settings
    7. Error types that can be raised
    8. Usage examples from existing docs
    
    Format as structured information, not prose.
    """)
    |> extract_assistant_content()
    
    %{
      file: file_path,
      content: content,
      analysis: module_info,
      module_name: extract_module_name(content)
    }
  end
  
  defp generate_api_reference(module_docs, _source_path) do
    IO.puts("📋 Generating API Reference...")
    
    api_docs = ClaudeCodeSDK.query("""
    Generate a comprehensive API reference from these module analyses:
    
    #{Enum.map_join(module_docs, "\n\n---\n\n", fn %{file: file, analysis: analysis} ->
      "File: #{file}\n#{analysis}"
    end)}
    
    Create:
    1. Table of contents with all modules
    2. For each module:
       - Purpose and overview
       - Installation/usage instructions
       - Function documentation with examples
       - Type specifications
       - Error handling patterns
    3. Cross-references between related modules
    4. Code examples for common use cases
    
    Use proper Markdown formatting with syntax highlighting.
    """, %ClaudeCodeSDK.Options{max_turns: 5})
    |> extract_assistant_content()
    
    File.write!("API_REFERENCE.md", api_docs)
    IO.puts("✅ API_REFERENCE.md created")
  end
  
  defp generate_getting_started_guide(module_docs, source_path) do
    IO.puts("🚀 Generating Getting Started Guide...")
    
    # Extract the main module (usually the project's primary interface)
    main_modules = Enum.filter(module_docs, fn %{file: file} ->
      basename = Path.basename(file, ".ex")
      project_name = Path.basename(source_path)
      String.contains?(basename, project_name) or String.ends_with?(file, "/lib/#{project_name}.ex")
    end)
    
    getting_started = ClaudeCodeSDK.query("""
    Create a Getting Started guide for this Elixir project:
    
    Main modules:
    #{Enum.map_join(main_modules, "\n\n", fn %{analysis: analysis} -> analysis end)}
    
    All modules overview:
    #{Enum.map_join(module_docs, "\n", fn %{module_name: name, file: file} -> "- #{name} (#{file})" end)}
    
    Generate:
    1. Project overview and purpose
    2. Installation instructions
    3. Quick start tutorial with code examples
    4. Configuration options
    5. Common use cases with step-by-step examples
    6. Troubleshooting section
    7. Next steps and advanced usage pointers
    
    Make it beginner-friendly but comprehensive.
    """)
    |> extract_assistant_content()
    
    File.write!("GETTING_STARTED.md", getting_started)
    IO.puts("✅ GETTING_STARTED.md created")
  end
  
  defp generate_examples_guide(module_docs, _source_path) do
    IO.puts("💡 Generating Examples Guide...")
    
    examples = ClaudeCodeSDK.query("""
    Create a comprehensive examples guide from these modules:
    
    #{Enum.map_join(module_docs, "\n\n---\n\n", fn %{file: file, analysis: analysis} ->
      "File: #{file}\n#{analysis}"
    end)}
    
    Generate practical examples for:
    1. Basic usage patterns
    2. Advanced configuration scenarios
    3. Integration with other libraries
    4. Error handling patterns
    5. Performance optimization
    6. Testing strategies
    7. Production deployment considerations
    
    Each example should:
    - Have a clear use case description
    - Include complete, runnable code
    - Explain key concepts
    - Show expected output
    - Include error handling where appropriate
    """)
    |> extract_assistant_content()
    
    File.write!("EXAMPLES.md", examples)
    IO.puts("✅ EXAMPLES.md created")
  end
  
  defp generate_architecture_overview(module_docs, source_path) do
    IO.puts("🏗️ Generating Architecture Overview...")
    
    architecture = ClaudeCodeSDK.query("""
    Create an architecture overview document for this Elixir project:
    
    Project path: #{source_path}
    
    Modules:
    #{Enum.map_join(module_docs, "\n\n", fn %{file: file, module_name: name, analysis: analysis} ->
      "Module: #{name}\nFile: #{file}\n#{analysis}"
    end)}
    
    Create:
    1. High-level architecture diagram (ASCII or description)
    2. Module responsibilities and relationships
    3. Data flow between components
    4. Key design patterns used
    5. Dependencies and their purposes
    6. Configuration and runtime behavior
    7. Scalability and performance characteristics
    8. Extension points and customization options
    
    Focus on helping developers understand the overall system design.
    """)
    |> extract_assistant_content()
    
    File.write!("ARCHITECTURE.md", architecture)
    IO.puts("✅ ARCHITECTURE.md created")
  end
  
  def generate_module_docs(module_file) do
    IO.puts("📝 Generating detailed docs for: #{module_file}")
    
    content = File.read!(module_file)
    module_name = extract_module_name(content)
    
    detailed_docs = ClaudeCodeSDK.query("""
    Generate comprehensive documentation for this specific module:
    
    ```elixir
    #{content}
    ```
    
    Create:
    1. Module overview and purpose
    2. Detailed function documentation with:
       - Parameter descriptions
       - Return value descriptions
       - Usage examples
       - Error conditions
       - See also references
    3. Type documentation
    4. Configuration options
    5. Integration examples
    6. Performance considerations
    7. Common pitfalls and how to avoid them
    
    Format as a complete Markdown document.
    """)
    |> extract_assistant_content()
    
    output_file = "docs/#{Macro.underscore(module_name)}.md"
    File.mkdir_p!(Path.dirname(output_file))
    File.write!(output_file, detailed_docs)
    
    IO.puts("✅ Module docs created: #{output_file}")
  end
  
  def generate_changelog(git_range \\ "HEAD~10..HEAD") do
    IO.puts("📝 Generating changelog for: #{git_range}")
    
    # Get git log
    {commits, 0} = System.cmd("git", ["log", "--oneline", git_range])
    
    changelog = ClaudeCodeSDK.query("""
    Generate a user-friendly changelog from these git commits:
    
    ```
    #{commits}
    ```
    
    Create:
    1. Categorized changes (Added, Changed, Fixed, Removed, Security)
    2. Impact assessment for each change
    3. Migration notes if breaking changes
    4. Version recommendation (major/minor/patch)
    
    Focus on user-facing changes and improvements.
    """)
    |> extract_assistant_content()
    
    File.write!("CHANGELOG_DRAFT.md", changelog)
    IO.puts("✅ CHANGELOG_DRAFT.md created")
  end
  
  def generate_contributing_guide(source_path) do
    IO.puts("🤝 Generating contributing guide...")
    
    # Analyze project structure
    project_files = [
      "mix.exs",
      "README.md", 
      ".github/workflows",
      "test/",
      "lib/"
    ] |> Enum.filter(&File.exists?(Path.join(source_path, &1)))
    
    contributing = ClaudeCodeSDK.query("""
    Generate a contributing guide for this Elixir project:
    
    Project structure includes: #{Enum.join(project_files, ", ")}
    Source path: #{source_path}
    
    Create:
    1. Development setup instructions
    2. Code style guidelines
    3. Testing requirements
    4. Pull request process
    5. Issue reporting guidelines
    6. Code review checklist
    7. Release process
    8. Community guidelines
    
    Make it welcoming to new contributors while maintaining quality standards.
    """)
    |> extract_assistant_content()
    
    File.write!("CONTRIBUTING.md", contributing)
    IO.puts("✅ CONTRIBUTING.md created")
  end
  
  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([A-Z][A-Za-z0-9_.]*)/m, content) do
      [_, module_name] -> module_name
      _ -> "UnknownModule"
    end
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
  [source_path] ->
    DocGenerator.generate_docs(source_path)
    
  [source_path, "module", module_file] ->
    DocGenerator.generate_module_docs(module_file)
    
  [source_path, "changelog"] ->
    DocGenerator.generate_changelog()
    
  [source_path, "changelog", git_range] ->
    DocGenerator.generate_changelog(git_range)
    
  [source_path, "contributing"] ->
    DocGenerator.generate_contributing_guide(source_path)
    
  [] ->
    DocGenerator.generate_docs("lib/")
    
  _ ->
    IO.puts("""
    Usage:
      mix run examples/doc_generator.exs lib/                           # Generate all docs
      mix run examples/doc_generator.exs lib/ module lib/my_module.ex   # Generate module docs
      mix run examples/doc_generator.exs lib/ changelog                 # Generate changelog
      mix run examples/doc_generator.exs lib/ changelog HEAD~5..HEAD    # Changelog for range
      mix run examples/doc_generator.exs lib/ contributing              # Generate CONTRIBUTING.md
    """)
end