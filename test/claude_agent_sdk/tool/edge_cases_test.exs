defmodule ClaudeAgentSDK.Tool.EdgeCasesTest do
  @moduledoc """
  Edge case tests for the Tool system.
  """

  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Tool

  describe "empty tool definitions" do
    test "tool with minimal schema" do
      defmodule MinimalTool do
        use ClaudeAgentSDK.Tool

        deftool :minimal,
                "Minimal tool",
                %{type: "object"} do
          def execute(_args) do
            {:ok, %{"content" => [%{"type" => "text", "text" => "success"}]}}
          end
        end
      end

      metadata = MinimalTool.Minimal.__tool_metadata__()
      assert metadata.input_schema == %{type: "object"}
    end

    test "tool with no required fields" do
      defmodule OptionalTool do
        use ClaudeAgentSDK.Tool

        deftool :optional,
                "All optional",
                %{
                  type: "object",
                  properties: %{
                    optional_field: %{type: "string"}
                  }
                } do
          def execute(args) do
            {:ok, %{"content" => [%{"type" => "text", "text" => inspect(args)}]}}
          end
        end
      end

      {:ok, result} = OptionalTool.Optional.execute(%{})
      assert result["content"]
    end
  end

  describe "complex input schemas" do
    test "nested object schema" do
      defmodule NestedTool do
        use ClaudeAgentSDK.Tool

        deftool :nested,
                "Nested schema",
                %{
                  type: "object",
                  properties: %{
                    user: %{
                      type: "object",
                      properties: %{
                        name: %{type: "string"},
                        age: %{type: "number"}
                      }
                    }
                  }
                } do
          def execute(%{"user" => user}) do
            {:ok, %{"content" => [%{"type" => "text", "text" => inspect(user)}]}}
          end
        end
      end

      {:ok, result} =
        NestedTool.Nested.execute(%{"user" => %{"name" => "Alice", "age" => 30}})

      assert result["content"]
    end

    test "array schema" do
      defmodule ArrayTool do
        use ClaudeAgentSDK.Tool

        deftool :array_input,
                "Takes array",
                %{
                  type: "object",
                  properties: %{
                    items: %{
                      type: "array",
                      items: %{type: "string"}
                    }
                  }
                } do
          def execute(%{"items" => items}) do
            count = length(items)
            {:ok, %{"content" => [%{"type" => "text", "text" => "Got #{count} items"}]}}
          end
        end
      end

      {:ok, result} = ArrayTool.ArrayInput.execute(%{"items" => ["a", "b", "c"]})
      [%{"text" => text}] = result["content"]
      assert text == "Got 3 items"
    end
  end

  describe "special characters in tool names" do
    test "converts snake_case to module name correctly" do
      defmodule UnderscoreTest do
        use ClaudeAgentSDK.Tool

        deftool :my_special_tool,
                "Tool with underscores",
                %{type: "object"} do
          def execute(_args) do
            {:ok, %{"content" => [%{"type" => "text", "text" => "ok"}]}}
          end
        end
      end

      # Should create UnderscoreTest.MySpecialTool module
      assert Code.ensure_loaded?(UnderscoreTest.MySpecialTool)
      metadata = UnderscoreTest.MySpecialTool.__tool_metadata__()
      assert metadata.name == :my_special_tool
    end
  end

  describe "large payloads" do
    test "handles large input" do
      defmodule LargeInputTool do
        use ClaudeAgentSDK.Tool

        deftool :large,
                "Large input",
                %{
                  type: "object",
                  properties: %{
                    data: %{type: "string"}
                  }
                } do
          def execute(%{"data" => data}) do
            size = byte_size(data)
            {:ok, %{"content" => [%{"type" => "text", "text" => "Received #{size} bytes"}]}}
          end
        end
      end

      large_string = String.duplicate("a", 10000)
      {:ok, result} = LargeInputTool.Large.execute(%{"data" => large_string})
      [%{"text" => text}] = result["content"]
      assert text == "Received 10000 bytes"
    end

    test "handles large output" do
      defmodule LargeOutputTool do
        use ClaudeAgentSDK.Tool

        deftool :large_out,
                "Large output",
                %{type: "object"} do
          def execute(_args) do
            large_text = String.duplicate("output", 5000)
            {:ok, %{"content" => [%{"type" => "text", "text" => large_text}]}}
          end
        end
      end

      {:ok, result} = LargeOutputTool.LargeOut.execute(%{})
      [%{"text" => text}] = result["content"]
      assert byte_size(text) == 30000
    end
  end

  describe "concurrent tool execution" do
    test "multiple tools execute concurrently without interference" do
      defmodule ConcurrentTool do
        use ClaudeAgentSDK.Tool

        deftool :concurrent,
                "Concurrent execution",
                %{
                  type: "object",
                  properties: %{
                    sleep_ms: %{type: "number"}
                  }
                } do
          def execute(%{"sleep_ms" => ms}) do
            Process.sleep(ms)
            {:ok, %{"content" => [%{"type" => "text", "text" => "Slept #{ms}ms"}]}}
          end
        end
      end

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
      defmodule StrictTool do
        use ClaudeAgentSDK.Tool

        deftool :strict,
                "Strict input",
                %{
                  type: "object",
                  properties: %{
                    required: %{type: "number"}
                  },
                  required: ["required"]
                } do
          def execute(%{"required" => num}) when is_number(num) do
            {:ok, %{"content" => [%{"type" => "text", "text" => "Got #{num}"}]}}
          end

          def execute(_args) do
            {:error, "Invalid input: required field missing or wrong type"}
          end
        end
      end

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
      defmodule TimeoutTool do
        use ClaudeAgentSDK.Tool

        deftool :timeout,
                "May timeout",
                %{type: "object"} do
          def execute(_args) do
            # Simulate long-running operation
            Process.sleep(100)
            {:ok, %{"content" => [%{"type" => "text", "text" => "completed"}]}}
          end
        end
      end

      # Tool execution itself succeeds
      task = Task.async(fn -> TimeoutTool.Timeout.execute(%{}) end)

      # But we can timeout the task
      result = Task.yield(task, 50) || Task.shutdown(task)
      assert is_nil(result)
    end
  end

  describe "tool naming edge cases" do
    test "handles numeric suffixes" do
      defmodule NumericTools do
        use ClaudeAgentSDK.Tool

        deftool :tool_v1,
                "Version 1",
                %{type: "object"} do
          def execute(_), do: {:ok, %{"content" => []}}
        end

        deftool :tool_v2,
                "Version 2",
                %{type: "object"} do
          def execute(_), do: {:ok, %{"content" => []}}
        end
      end

      assert Code.ensure_loaded?(NumericTools.ToolV1)
      assert Code.ensure_loaded?(NumericTools.ToolV2)
    end

    test "handles single character names" do
      defmodule SingleChar do
        use ClaudeAgentSDK.Tool

        deftool :a,
                "Single char",
                %{type: "object"} do
          def execute(_), do: {:ok, %{"content" => []}}
        end
      end

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
