defmodule ClaudeAgentSDK.Tool.RegistryTest do
  @moduledoc """
  Tests for Tool.Registry GenServer that manages tool registration and lookup.
  """

  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.TestEnvHelpers
  alias ClaudeAgentSDK.Tool.Registry

  setup do
    # Start a registry for each test
    {:ok, pid} = Registry.start_link([])
    %{registry: pid}
  end

  describe "tool registration" do
    test "registers a tool successfully", %{registry: registry} do
      tool = %{
        name: "add",
        description: "Add two numbers",
        input_schema: %{type: "object"},
        module: TestModule.Add
      }

      assert :ok = Registry.register_tool(registry, tool)
    end

    test "prevents duplicate tool registration", %{registry: registry} do
      tool = %{
        name: "add",
        description: "Add",
        input_schema: %{type: "object"},
        module: TestModule.Add
      }

      assert :ok = Registry.register_tool(registry, tool)
      assert {:error, :already_registered} = Registry.register_tool(registry, tool)
    end

    test "registers multiple tools", %{registry: registry} do
      tool1 = %{name: "add", description: "Add", input_schema: %{}, module: M1}
      tool2 = %{name: "subtract", description: "Subtract", input_schema: %{}, module: M2}

      assert :ok = Registry.register_tool(registry, tool1)
      assert :ok = Registry.register_tool(registry, tool2)

      assert {:ok, tools} = Registry.list_tools(registry)
      assert length(tools) == 2
    end
  end

  describe "tool lookup" do
    test "finds tool by name", %{registry: registry} do
      tool = %{
        name: "calculator",
        description: "Calculate",
        input_schema: %{type: "object"},
        module: Calc
      }

      Registry.register_tool(registry, tool)

      assert {:ok, found_tool} = Registry.get_tool(registry, "calculator")
      assert found_tool.name == "calculator"
      assert found_tool.module == Calc
    end

    test "returns error for unknown tool", %{registry: registry} do
      assert {:error, :not_found} = Registry.get_tool(registry, "unknown")
    end
  end

  describe "tool listing" do
    test "lists all registered tools", %{registry: registry} do
      tools = [
        %{name: "add", description: "Add", input_schema: %{}, module: M1},
        %{name: "subtract", description: "Subtract", input_schema: %{}, module: M2},
        %{name: "multiply", description: "Multiply", input_schema: %{}, module: M3}
      ]

      Enum.each(tools, &Registry.register_tool(registry, &1))

      {:ok, listed} = Registry.list_tools(registry)
      assert length(listed) == 3

      names = Enum.map(listed, & &1.name)
      assert "add" in names
      assert "subtract" in names
      assert "multiply" in names
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
        name: "mock_add",
        description: "Mock add",
        input_schema: %{},
        module: MockExecutor
      }

      Registry.register_tool(registry, tool)

      assert {:ok, result} = Registry.execute_tool(registry, "mock_add", %{"a" => 5, "b" => 3})
      assert result["result"] == 8
    end

    test "handles execution errors gracefully", %{registry: registry} do
      defmodule FailExecutor do
        def execute(_args) do
          {:error, "Execution failed"}
        end
      end

      tool = %{name: "fail", description: "Fail", input_schema: %{}, module: FailExecutor}

      Registry.register_tool(registry, tool)

      assert {:error, "Execution failed"} = Registry.execute_tool(registry, "fail", %{})
    end

    test "handles missing tool execution", %{registry: registry} do
      assert {:error, :not_found} = Registry.execute_tool(registry, "nonexistent", %{})
    end

    defmodule ControlledSlowExecutor do
      @owner_key {__MODULE__, :owner}

      def put_owner(pid), do: :persistent_term.put(@owner_key, pid)
      def clear_owner, do: :persistent_term.erase(@owner_key)

      def execute(_args) do
        owner = :persistent_term.get(@owner_key)
        send(owner, {:slow_executor_started, self()})

        receive do
          :release_slow_executor ->
            {:ok, %{"result" => "released"}}
        end
      end
    end

    defmodule TimeoutExecutor do
      def execute(_args) do
        Process.sleep(200)
        {:ok, %{"result" => "late"}}
      end
    end

    test "list_tools remains responsive while a slow tool executes", %{registry: registry} do
      ControlledSlowExecutor.put_owner(self())

      on_exit(fn ->
        ControlledSlowExecutor.clear_owner()
      end)

      tool = %{
        name: "slow_tool",
        description: "Slow",
        input_schema: %{},
        module: ControlledSlowExecutor
      }

      Registry.register_tool(registry, tool)

      execute_task = Task.async(fn -> Registry.execute_tool(registry, "slow_tool", %{}) end)

      assert_receive {:slow_executor_started, tool_pid}, 1_000

      list_task = Task.async(fn -> Registry.list_tools(registry) end)
      assert {:ok, tools} = Task.await(list_task, 100)
      assert Enum.any?(tools, &(&1.name == "slow_tool"))

      send(tool_pid, :release_slow_executor)
      assert {:ok, %{"result" => "released"}} = Task.await(execute_task, 1_000)
    end

    test "tool execution timeout returns structured error", %{registry: registry} do
      config_mod = ClaudeAgentSDK.Config.Timeouts
      previous = Application.get_env(:claude_agent_sdk, config_mod)
      Application.put_env(:claude_agent_sdk, config_mod, tool_execution_ms: 50)

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:claude_agent_sdk, config_mod)
        else
          Application.put_env(:claude_agent_sdk, config_mod, previous)
        end
      end)

      tool = %{
        name: "timeout_tool",
        description: "Timeout",
        input_schema: %{},
        module: TimeoutExecutor
      }

      Registry.register_tool(registry, tool)

      assert {:error, {:execution_failed, message}} =
               Registry.execute_tool(registry, "timeout_tool", %{})

      assert message =~ "timed out"
      assert {:ok, _tools} = Registry.list_tools(registry)
    end

    test "returns structured error instead of crashing in strict task supervisor mode", %{
      registry: registry
    } do
      missing_supervisor = :missing_tool_registry_task_supervisor

      TestEnvHelpers.with_task_supervisor_env(missing_supervisor, true, fn ->
        tool = %{
          name: "strict_tool",
          description: "Strict",
          input_schema: %{},
          module: MockExecutor
        }

        Registry.register_tool(registry, tool)

        assert {:error, {:execution_failed, message}} =
                 Registry.execute_tool(registry, "strict_tool", %{"a" => 1, "b" => 2})

        assert message =~ "task supervisor"
        assert Process.alive?(registry)
      end)
    end
  end

  describe "registry state management" do
    test "maintains state across calls", %{registry: registry} do
      tool1 = %{name: "t1", description: "T1", input_schema: %{}, module: M1}
      tool2 = %{name: "t2", description: "T2", input_schema: %{}, module: M2}

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
              name: "tool_#{i}",
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
      tool = %{name: "shared", description: "Shared", input_schema: %{}, module: M}
      Registry.register_tool(registry, tool)

      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            Registry.get_tool(registry, "shared")
          end)
        end

      results = Enum.map(tasks, &Task.await/1)
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
end
