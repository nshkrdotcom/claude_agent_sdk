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

  use ClaudeAgentSDK.SupertesterCase

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

  describe "simple_schema/1" do
    test "creates schema with string properties" do
      schema = Tool.simple_schema([:name, :path])

      assert schema.type == "object"
      assert schema.properties.name.type == "string"
      assert schema.properties.path.type == "string"
      assert schema.required == ["name", "path"]
    end

    test "creates schema with typed properties" do
      schema =
        Tool.simple_schema(
          name: :string,
          count: :number,
          enabled: :boolean
        )

      assert schema.properties.name.type == "string"
      assert schema.properties.count.type == "number"
      assert schema.properties.enabled.type == "boolean"
      assert "name" in schema.required
      assert "count" in schema.required
      assert "enabled" in schema.required
    end

    test "creates schema with descriptions" do
      schema =
        Tool.simple_schema(
          name: {:string, "User's full name"},
          age: {:number, "Age in years"}
        )

      assert schema.properties.name.type == "string"
      assert schema.properties.name.description == "User's full name"
      assert schema.properties.age.type == "number"
      assert schema.properties.age.description == "Age in years"
    end

    test "supports optional fields" do
      schema =
        Tool.simple_schema(
          name: :string,
          email: {:string, optional: true}
        )

      assert schema.properties.name.type == "string"
      assert schema.properties.email.type == "string"
      assert "name" in schema.required
      refute "email" in schema.required
    end

    test "supports array type" do
      schema = Tool.simple_schema(tags: :array)

      assert schema.properties.tags.type == "array"
    end

    test "supports integer type" do
      schema = Tool.simple_schema(count: :integer)

      assert schema.properties.count.type == "integer"
    end

    test "empty list creates empty object schema" do
      schema = Tool.simple_schema([])

      assert schema.type == "object"
      assert schema.properties == %{}
      assert schema.required == []
    end
  end

  describe "simple_schema/1 with map syntax (Python parity)" do
    test "creates schema with atom keys and atom types" do
      schema = Tool.simple_schema(%{a: :float, b: :float})

      assert schema["type"] == "object"
      assert schema["properties"]["a"]["type"] == "number"
      assert schema["properties"]["b"]["type"] == "number"
      assert "a" in schema["required"]
      assert "b" in schema["required"]
    end

    test "creates schema with string keys" do
      schema = Tool.simple_schema(%{"name" => :string, "age" => :integer})

      assert schema["properties"]["name"]["type"] == "string"
      assert schema["properties"]["age"]["type"] == "integer"
      assert "name" in schema["required"]
      assert "age" in schema["required"]
    end

    test "supports module types for Python parity" do
      schema = Tool.simple_schema(%{"name" => String, "count" => Integer, "rate" => Float})

      assert schema["properties"]["name"]["type"] == "string"
      assert schema["properties"]["count"]["type"] == "integer"
      assert schema["properties"]["rate"]["type"] == "number"
    end

    test "supports :number type" do
      schema = Tool.simple_schema(%{value: :number})

      assert schema["properties"]["value"]["type"] == "number"
    end

    test "supports :boolean type" do
      schema = Tool.simple_schema(%{enabled: :boolean})

      assert schema["properties"]["enabled"]["type"] == "boolean"
    end

    test "supports :array type" do
      schema = Tool.simple_schema(%{items: :array})

      assert schema["properties"]["items"]["type"] == "array"
    end

    test "supports :object type" do
      schema = Tool.simple_schema(%{config: :object})

      assert schema["properties"]["config"]["type"] == "object"
    end

    test "all fields are required by default" do
      schema = Tool.simple_schema(%{a: :string, b: :integer, c: :boolean})

      assert length(schema["required"]) == 3
      assert "a" in schema["required"]
      assert "b" in schema["required"]
      assert "c" in schema["required"]
    end

    test "empty map creates empty object schema" do
      schema = Tool.simple_schema(%{})

      assert schema["type"] == "object"
      assert schema["properties"] == %{}
      assert schema["required"] == []
    end

    test "mixed atom and string keys" do
      schema = Tool.simple_schema(%{:a => :float, "b" => :integer})

      assert schema["properties"]["a"]["type"] == "number"
      assert schema["properties"]["b"]["type"] == "integer"
    end
  end
end
