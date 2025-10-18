defmodule ClaudeAgentSDK.ToolTest.TestTools do
  use ClaudeAgentSDK.Tool

  deftool :add,
          "Add two numbers",
          %{
            type: "object",
            properties: %{
              a: %{type: "number"},
              b: %{type: "number"}
            },
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      result = a + b
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a} + #{b} = #{result}"}]}}
    end
  end

  deftool :greet,
          "Greets a user",
          %{
            type: "object",
            properties: %{
              name: %{type: "string"}
            },
            required: ["name"]
          } do
    def execute(%{"name" => name}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "Hello, #{name}!"}]}}
    end
  end

  deftool :error_tool,
          "Always fails",
          %{type: "object"} do
    def execute(_args) do
      {:error, "Expected error"}
    end
  end
end

defmodule ClaudeAgentSDK.ToolTest do
  @moduledoc """
  Unit tests for the Tool system.

  Tests the `deftool` macro and tool metadata generation.
  """

  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Tool
  alias ClaudeAgentSDK.ToolTest.TestTools

  describe "deftool macro" do
    test "defines tool with correct metadata" do
      assert function_exported?(TestTools.Add, :__tool_metadata__, 0)

      metadata = TestTools.Add.__tool_metadata__()

      assert metadata.name == :add
      assert metadata.description == "Add two numbers"
      assert metadata.input_schema.type == "object"
      assert Map.has_key?(metadata.input_schema.properties, :a)
      assert Map.has_key?(metadata.input_schema.properties, :b)
    end

    test "generates execute function" do
      assert function_exported?(TestTools.Add, :execute, 1)

      {:ok, result} = TestTools.Add.execute(%{"a" => 5, "b" => 3})
      assert result["content"] == [%{"type" => "text", "text" => "5 + 3 = 8"}]
    end

    test "handles successful execution" do
      {:ok, result} = TestTools.Greet.execute(%{"name" => "Alice"})
      assert result["content"] == [%{"type" => "text", "text" => "Hello, Alice!"}]
    end

    test "handles error execution" do
      {:error, reason} = TestTools.ErrorTool.execute(%{})
      assert reason == "Expected error"
    end

    test "tool module has correct naming" do
      # deftool :add should create TestTools.Add module
      assert Code.ensure_loaded?(TestTools.Add)
      assert Code.ensure_loaded?(TestTools.Greet)
      assert Code.ensure_loaded?(TestTools.ErrorTool)
    end
  end

  describe "tool registration at compile time" do
    test "tools are discoverable" do
      # The Tool module should be able to list all tools defined in a module
      tools = Tool.list_tools(TestTools)

      assert length(tools) == 3
      assert :add in Enum.map(tools, & &1.name)
      assert :greet in Enum.map(tools, & &1.name)
      assert :error_tool in Enum.map(tools, & &1.name)
    end
  end

  describe "input schema validation" do
    test "validates required schema fields" do
      schema = %{
        type: "object",
        properties: %{
          a: %{type: "number"}
        },
        required: ["a"]
      }

      assert Tool.valid_schema?(schema)
    end

    test "accepts minimal schema" do
      schema = %{type: "object"}
      assert Tool.valid_schema?(schema)
    end
  end
end
