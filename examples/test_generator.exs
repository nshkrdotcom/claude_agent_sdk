#!/usr/bin/env elixir

# Test Generator - Automatically generate comprehensive test suites
# Usage: mix run examples/test_generator.exs lib/my_module.ex

defmodule TestGenerator do
  @moduledoc """
  Generates comprehensive ExUnit test suites for Elixir modules.
  """

  def generate_tests(module_file) do
    IO.puts("🧪 Generating tests for: #{module_file}")
    
    unless File.exists?(module_file) do
      IO.puts("❌ File not found: #{module_file}")
      System.halt(1)
    end
    
    content = File.read!(module_file)
    module_name = extract_module_name(content)
    
    IO.puts("📋 Module: #{module_name}")
    
    # Generate comprehensive test suite
    test_content = generate_test_suite(content, module_name)
    
    # Create test file
    test_file_path = create_test_file_path(module_name)
    File.write!(test_file_path, test_content)
    
    IO.puts("✅ Test file created: #{test_file_path}")
    
    # Try to run the tests
    run_and_fix_tests(test_file_path, content, module_name)
  end
  
  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([A-Z][A-Za-z0-9_.]*)/m, content) do
      [_, module_name] -> module_name
      _ -> "UnknownModule"
    end
  end
  
  defp generate_test_suite(module_content, module_name) do
    IO.puts("🔍 Analyzing module structure...")
    
    # First, analyze the module to understand its structure
    analysis = ClaudeCodeSDK.query("""
    Analyze this Elixir module to understand its structure:
    
    ```elixir
    #{module_content}
    ```
    
    Extract:
    1. All public functions with their arities
    2. Function parameters and return types
    3. Dependencies and imports
    4. Any GenServer or other OTP behaviors
    5. Error conditions and edge cases
    6. Required setup/teardown
    """)
    |> extract_assistant_content()
    
    IO.puts("🧪 Generating test suite...")
    
    # Generate the actual test suite
    test_suite = ClaudeCodeSDK.query("""
    Generate a comprehensive ExUnit test suite for this module:
    
    Module analysis:
    #{analysis}
    
    Full module code:
    ```elixir
    #{module_content}
    ```
    
    Generate tests that include:
    1. Setup and teardown functions if needed
    2. Tests for all public functions
    3. Happy path testing
    4. Edge case testing (empty inputs, nil values, boundary conditions)
    5. Error condition testing
    6. Property-based test suggestions using StreamData
    7. Mock/stub patterns for external dependencies
    8. Integration tests if the module interacts with other systems
    
    Follow these guidelines:
    - Use descriptive test names
    - Group related tests with describe blocks
    - Include docstrings for complex test cases
    - Use setup blocks efficiently
    - Follow ExUnit best practices
    - Include assert_raise for error conditions
    - Add property tests for mathematical functions
    
    Format as a complete ExUnit test file.
    """, %ClaudeCodeSDK.Options{max_turns: 3})
    |> extract_assistant_content()
    
    # Clean up the generated tests
    clean_test_suite(test_suite, module_name)
  end
  
  defp clean_test_suite(test_content, module_name) do
    IO.puts("🧹 Cleaning up generated tests...")
    
    ClaudeCodeSDK.query("""
    Clean up and optimize this ExUnit test file:
    
    ```elixir
    #{test_content}
    ```
    
    Ensure:
    1. Proper module name: #{module_name}Test
    2. Correct use ExUnit.Case syntax
    3. No syntax errors or typos
    4. Proper indentation and formatting
    5. Remove any duplicate test cases
    6. Ensure all tests have clear, descriptive names
    7. Add missing imports if needed
    8. Fix any invalid Elixir syntax
    
    Return only the cleaned test file content.
    """)
    |> extract_assistant_content()
  end
  
  defp create_test_file_path(module_name) do
    # Convert module name to file path
    file_name = module_name
                |> String.split(".")
                |> Enum.map(&Macro.underscore/1)
                |> Enum.join("/")
                |> String.downcase()
    
    test_file = "test/#{file_name}_test.exs"
    
    # Ensure test directory exists
    test_dir = Path.dirname(test_file)
    File.mkdir_p!(test_dir)
    
    test_file
  end
  
  defp run_and_fix_tests(test_file_path, original_content, module_name) do
    IO.puts("🏃 Running generated tests...")
    
    case System.cmd("mix", ["test", test_file_path], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("✅ All tests passed!")
        IO.puts(output)
        
      {error_output, _} ->
        IO.puts("❌ Tests failed, attempting to fix...")
        IO.puts("Error output:")
        IO.puts(error_output)
        
        fix_failing_tests(test_file_path, error_output, original_content, module_name)
    end
  end
  
  defp fix_failing_tests(test_file_path, error_output, original_content, module_name) do
    current_test_content = File.read!(test_file_path)
    
    IO.puts("🔧 Fixing test failures...")
    
    fixed_content = ClaudeCodeSDK.query("""
    Fix the failing tests based on this error output:
    
    Error output:
    #{error_output}
    
    Original module being tested:
    ```elixir
    #{original_content}
    ```
    
    Current test file:
    ```elixir
    #{current_test_content}
    ```
    
    Fix the issues by:
    1. Correcting syntax errors
    2. Fixing import statements
    3. Adjusting test expectations to match actual behavior
    4. Adding missing setup code
    5. Fixing function calls and parameters
    6. Ensuring proper assertions
    
    Return the corrected test file content.
    """)
    |> extract_assistant_content()
    
    # Write fixed tests
    File.write!(test_file_path, fixed_content)
    
    IO.puts("🔄 Re-running tests with fixes...")
    
    case System.cmd("mix", ["test", test_file_path], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("✅ Tests now pass after fixes!")
        IO.puts(output)
        
      {still_failing, _} ->
        IO.puts("⚠️  Some tests still failing:")
        IO.puts(still_failing)
        IO.puts("\n💡 Manual review may be needed for:")
        IO.puts("   - Complex business logic")
        IO.puts("   - External dependencies")  
        IO.puts("   - Stateful operations")
    end
  end
  
  def generate_property_tests(module_file) do
    IO.puts("🎲 Generating property-based tests for: #{module_file}")
    
    content = File.read!(module_file)
    module_name = extract_module_name(content)
    
    property_tests = ClaudeCodeSDK.query("""
    Generate property-based tests using StreamData for this module:
    
    ```elixir
    #{content}
    ```
    
    Focus on:
    1. Mathematical properties (associativity, commutativity, etc.)
    2. Round-trip properties (encode/decode, serialize/deserialize)
    3. Invariant properties (data structure invariants)
    4. Metamorphic properties (equivalent transformations)
    
    Use ExUnitProperties and StreamData generators.
    Include edge case generators for boundary conditions.
    """)
    |> extract_assistant_content()
    
    property_file = "test/#{Macro.underscore(module_name)}_property_test.exs"
    File.write!(property_file, property_tests)
    
    IO.puts("✅ Property tests created: #{property_file}")
  end
  
  def generate_integration_tests(module_file) do
    IO.puts("🔗 Generating integration tests for: #{module_file}")
    
    content = File.read!(module_file)
    module_name = extract_module_name(content)
    
    integration_tests = ClaudeCodeSDK.query("""
    Generate integration tests for this module:
    
    ```elixir
    #{content}
    ```
    
    Create tests that:
    1. Test the module in realistic scenarios
    2. Test interactions with other modules/systems
    3. Test end-to-end workflows
    4. Include setup/teardown for external resources
    5. Mock external dependencies appropriately
    6. Test error propagation across module boundaries
    """)
    |> extract_assistant_content()
    
    integration_file = "test/integration/#{Macro.underscore(module_name)}_integration_test.exs"
    File.mkdir_p!(Path.dirname(integration_file))
    File.write!(integration_file, integration_tests)
    
    IO.puts("✅ Integration tests created: #{integration_file}")
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
  [module_file] ->
    TestGenerator.generate_tests(module_file)
    
  [module_file, "property"] ->
    TestGenerator.generate_property_tests(module_file)
    
  [module_file, "integration"] ->
    TestGenerator.generate_integration_tests(module_file)
    
  [module_file, "all"] ->
    TestGenerator.generate_tests(module_file)
    TestGenerator.generate_property_tests(module_file)
    TestGenerator.generate_integration_tests(module_file)
    
  _ ->
    IO.puts("""
    Usage:
      mix run examples/test_generator.exs lib/my_module.ex              # Generate unit tests
      mix run examples/test_generator.exs lib/my_module.ex property     # Generate property tests
      mix run examples/test_generator.exs lib/my_module.ex integration  # Generate integration tests
      mix run examples/test_generator.exs lib/my_module.ex all          # Generate all test types
    """)
end