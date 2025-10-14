#!/usr/bin/env elixir

# Simple Test Generator - Generate basic test templates
# Usage: mix run examples/simple_test_gen.exs <module_file>

defmodule SimpleTestGen do
  def generate_tests(module_file) do
    IO.puts("🧪 Simple Test Generator")
    IO.puts("Generating tests for: #{module_file}")

    unless File.exists?(module_file) do
      IO.puts("❌ File not found: #{module_file}")
      System.halt(1)
    end

    content = File.read!(module_file)
    module_name = extract_module_name(content)

    IO.puts("📋 Module: #{module_name}")
    IO.puts("📡 Generating test suite...")

    test_content =
      ClaudeAgentSDK.query("""
      Generate a basic ExUnit test suite for this Elixir module:

      ```elixir
      #{String.slice(content, 0, 1500)}#{if String.length(content) > 1500, do: "\n... (truncated)", else: ""}
      ```

      Generate:
      1. Basic test module structure for #{module_name}Test
      2. Tests for the main public functions
      3. Simple happy path tests
      4. One edge case test

      Keep it simple and focused. Use proper ExUnit syntax.
      """)
      |> extract_assistant_content()

    # Create test file path
    test_file_path = create_test_file_path(module_name)

    # Ensure test directory exists
    test_dir = Path.dirname(test_file_path)
    File.mkdir_p!(test_dir)

    # Write test file
    File.write!(test_file_path, test_content)

    IO.puts("\n🧪 Generated Test Suite:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("File: #{test_file_path}")
    IO.puts("Lines: #{String.split(test_content, "\n") |> length()}")

    IO.puts("\n💾 Test file created: #{test_file_path}")

    # Try to run the tests
    IO.puts("\n🏃 Running generated tests...")

    case System.cmd("mix", ["test", test_file_path], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("✅ Tests passed!")
        IO.puts(output)

      {error_output, _} ->
        IO.puts("⚠️  Tests had issues:")
        IO.puts(error_output)
        IO.puts("\n💡 The generated tests may need manual adjustments.")
    end

    IO.puts("✅ Test generation complete!")
  end

  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([A-Z][A-Za-z0-9_.]*)/m, content) do
      [_, module_name] -> module_name
      _ -> "UnknownModule"
    end
  end

  defp create_test_file_path(module_name) do
    # Convert module name to file path
    file_name =
      module_name
      |> String.split(".")
      |> Enum.map(&Macro.underscore/1)
      |> Enum.join("/")
      |> String.downcase()

    "test/#{file_name}_test.exs"
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
    SimpleTestGen.generate_tests(module_file)

  [] ->
    # Default to generating tests for the main SDK file
    SimpleTestGen.generate_tests("lib/claude_agent_sdk.ex")

  _ ->
    IO.puts("Usage: mix run examples/simple_test_gen.exs [module_file]")
end
