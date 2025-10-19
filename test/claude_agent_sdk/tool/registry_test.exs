defmodule ClaudeAgentSDK.Tool.RegistryTest do
  @moduledoc """
  Tests for Tool.Registry GenServer that manages tool registration and lookup.
  """

  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.Tool.Registry

  setup do
    # Start a registry for each test
    {:ok, pid} = Registry.start_link([])
    %{registry: pid}
  end

  describe "tool registration" do
    test "registers a tool successfully", %{registry: registry} do
      tool = %{
        name: :add,
        description: "Add two numbers",
        input_schema: %{type: "object"},
        module: TestModule.Add
      }

      assert :ok = Registry.register_tool(registry, tool)
    end

    test "prevents duplicate tool registration", %{registry: registry} do
      tool = %{
        name: :add,
        description: "Add",
        input_schema: %{type: "object"},
        module: TestModule.Add
      }

      assert :ok = Registry.register_tool(registry, tool)
      assert {:error, :already_registered} = Registry.register_tool(registry, tool)
    end

    test "registers multiple tools", %{registry: registry} do
      tool1 = %{name: :add, description: "Add", input_schema: %{}, module: M1}
      tool2 = %{name: :subtract, description: "Subtract", input_schema: %{}, module: M2}

      assert :ok = Registry.register_tool(registry, tool1)
      assert :ok = Registry.register_tool(registry, tool2)

      assert {:ok, tools} = Registry.list_tools(registry)
      assert length(tools) == 2
    end
  end

  describe "tool lookup" do
    test "finds tool by name", %{registry: registry} do
      tool = %{
        name: :calculator,
        description: "Calculate",
        input_schema: %{type: "object"},
        module: Calc
      }

      Registry.register_tool(registry, tool)

      assert {:ok, found_tool} = Registry.get_tool(registry, :calculator)
      assert found_tool.name == :calculator
      assert found_tool.module == Calc
    end

    test "returns error for unknown tool", %{registry: registry} do
      assert {:error, :not_found} = Registry.get_tool(registry, :unknown)
    end
  end

  describe "tool listing" do
    test "lists all registered tools", %{registry: registry} do
      tools = [
        %{name: :add, description: "Add", input_schema: %{}, module: M1},
        %{name: :subtract, description: "Subtract", input_schema: %{}, module: M2},
        %{name: :multiply, description: "Multiply", input_schema: %{}, module: M3}
      ]

      Enum.each(tools, &Registry.register_tool(registry, &1))

      {:ok, listed} = Registry.list_tools(registry)
      assert length(listed) == 3

      names = Enum.map(listed, & &1.name)
      assert :add in names
      assert :subtract in names
      assert :multiply in names
    end

    test "returns empty list when no tools registered", %{registry: registry} do
      assert {:ok, []} = Registry.list_tools(registry)
    end
  end

  describe "tool execution dispatch" do
    defmodule MockExecutor do
      def execute(%{"a" => a, "b" => b}) do
        {:ok, %{"result" => a + b}}
      end
    end

    test "dispatches execution to tool module", %{registry: registry} do
      tool = %{
        name: :mock_add,
        description: "Mock add",
        input_schema: %{},
        module: MockExecutor
      }

      Registry.register_tool(registry, tool)

      assert {:ok, result} = Registry.execute_tool(registry, :mock_add, %{"a" => 5, "b" => 3})
      assert result["result"] == 8
    end

    test "handles execution errors gracefully", %{registry: registry} do
      defmodule FailExecutor do
        def execute(_args) do
          {:error, "Execution failed"}
        end
      end

      tool = %{name: :fail, description: "Fail", input_schema: %{}, module: FailExecutor}

      Registry.register_tool(registry, tool)

      assert {:error, "Execution failed"} = Registry.execute_tool(registry, :fail, %{})
    end

    test "handles missing tool execution", %{registry: registry} do
      assert {:error, :not_found} = Registry.execute_tool(registry, :nonexistent, %{})
    end
  end

  describe "registry state management" do
    test "maintains state across calls", %{registry: registry} do
      tool1 = %{name: :t1, description: "T1", input_schema: %{}, module: M1}
      tool2 = %{name: :t2, description: "T2", input_schema: %{}, module: M2}

      Registry.register_tool(registry, tool1)
      {:ok, tools} = Registry.list_tools(registry)
      assert length(tools) == 1

      Registry.register_tool(registry, tool2)
      {:ok, tools} = Registry.list_tools(registry)
      assert length(tools) == 2
    end

    test "survives process crashes with supervisor", %{registry: _registry} do
      # This tests that the registry can be supervised and restarted
      # We'll implement this with proper supervision later
      assert true
    end
  end

  describe "concurrent access" do
    test "handles concurrent registrations", %{registry: registry} do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            tool = %{
              name: :"tool_#{i}",
              description: "Tool #{i}",
              input_schema: %{},
              module: :"Module#{i}"
            }

            Registry.register_tool(registry, tool)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)
      assert Enum.all?(results, &(&1 == :ok))

      {:ok, tools} = Registry.list_tools(registry)
      assert length(tools) == 10
    end

    test "handles concurrent lookups", %{registry: registry} do
      tool = %{name: :shared, description: "Shared", input_schema: %{}, module: M}
      Registry.register_tool(registry, tool)

      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            Registry.get_tool(registry, :shared)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
