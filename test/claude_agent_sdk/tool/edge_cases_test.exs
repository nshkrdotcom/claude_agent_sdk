defmodule ClaudeAgentSDK.Tool.EdgeCasesTest do
  @moduledoc """
  Edge case tests for the Tool system.
  """

  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.TestSupport.EdgeCase.ArrayTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.ConcurrentTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.LargeInputTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.LargeOutputTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.MinimalTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.NestedTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.NumericTools
  alias ClaudeAgentSDK.TestSupport.EdgeCase.OptionalTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.SingleChar
  alias ClaudeAgentSDK.TestSupport.EdgeCase.StrictTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.TimeoutTool
  alias ClaudeAgentSDK.TestSupport.EdgeCase.UnderscoreTest
  alias ClaudeAgentSDK.Tool

  describe "empty tool definitions" do
    test "tool with minimal schema" do
      metadata = MinimalTool.Minimal.__tool_metadata__()
      assert metadata.input_schema == %{type: "object"}
    end

    test "tool with no required fields" do
      {:ok, result} = OptionalTool.Optional.execute(%{})
      assert result["content"]
    end
  end

  describe "complex input schemas" do
    test "nested object schema" do
      {:ok, result} =
        NestedTool.Nested.execute(%{"user" => %{"name" => "Alice", "age" => 30}})

      assert result["content"]
    end

    test "array schema" do
      {:ok, result} = ArrayTool.ArrayInput.execute(%{"items" => ["a", "b", "c"]})
      [%{"text" => text}] = result["content"]
      assert text == "Got 3 items"
    end
  end

  describe "special characters in tool names" do
    test "converts snake_case to module name correctly" do
      # Should create UnderscoreTest.MySpecialTool module
      assert Code.ensure_loaded?(UnderscoreTest.MySpecialTool)
      metadata = UnderscoreTest.MySpecialTool.__tool_metadata__()
      assert metadata.name == :my_special_tool
    end
  end

  describe "large payloads" do
    test "handles large input" do
      large_string = String.duplicate("a", 10_000)
      {:ok, result} = LargeInputTool.Large.execute(%{"data" => large_string})
      [%{"text" => text}] = result["content"]
      assert text == "Received 10000 bytes"
    end

    test "handles large output" do
      {:ok, result} = LargeOutputTool.LargeOut.execute(%{})
      [%{"text" => text}] = result["content"]
      assert byte_size(text) == 30_000
    end
  end

  describe "concurrent tool execution" do
    test "multiple tools execute concurrently without interference" do
      tasks =
        for i <- [10, 20, 30] do
          Task.async(fn ->
            ConcurrentTool.Concurrent.execute(%{"sleep_ms" => i})
          end)
        end

      results = Enum.map(tasks, &Task.await/1)
      assert length(results) == 3
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "error conditions" do
    test "gracefully handles malformed input" do
      # Missing required field
      assert {:error, msg} = StrictTool.Strict.execute(%{})
      assert msg =~ "Invalid input"

      # Wrong type
      assert {:error, msg} = StrictTool.Strict.execute(%{"required" => "not a number"})
      assert msg =~ "Invalid input"

      # Correct input
      assert {:ok, _} = StrictTool.Strict.execute(%{"required" => 42})
    end

    test "handles tool execution timeout" do
      # Tool execution itself succeeds
      task = Task.async(fn -> TimeoutTool.Timeout.execute(%{}) end)

      # But we can timeout the task
      result = Task.yield(task, 50) || Task.shutdown(task)
      assert is_nil(result)
    end
  end

  describe "tool naming edge cases" do
    test "handles numeric suffixes" do
      assert Code.ensure_loaded?(NumericTools.ToolV1)
      assert Code.ensure_loaded?(NumericTools.ToolV2)
    end

    test "handles single character names" do
      assert Code.ensure_loaded?(SingleChar.A)
      metadata = SingleChar.A.__tool_metadata__()
      assert metadata.name == :a
    end
  end

  describe "schema validation edge cases" do
    test "accepts complex JSON schema features" do
      schema = %{
        type: "object",
        properties: %{
          name: %{type: "string", minLength: 1, maxLength: 100},
          age: %{type: "number", minimum: 0, maximum: 150},
          email: %{type: "string", format: "email"},
          tags: %{type: "array", items: %{type: "string"}, minItems: 1}
        },
        required: ["name"],
        additionalProperties: false
      }

      assert Tool.valid_schema?(schema)
    end

    test "handles oneOf/anyOf/allOf" do
      schema = %{
        type: "object",
        properties: %{
          value: %{
            oneOf: [
              %{type: "string"},
              %{type: "number"}
            ]
          }
        }
      }

      assert Tool.valid_schema?(schema)
    end
  end
end
