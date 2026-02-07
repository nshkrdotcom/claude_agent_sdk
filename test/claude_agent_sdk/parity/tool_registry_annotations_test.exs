defmodule ClaudeAgentSDK.Parity.ToolRegistryAnnotationsTest do
  @moduledoc """
  Tests for Phase 4: Tool.Registry handles annotations correctly.

  Verifies that tools registered with annotations are stored,
  retrieved, and listed with their annotations intact.
  """

  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Tool.Registry

  setup do
    {:ok, pid} = Registry.start_link([])
    %{registry: pid}
  end

  describe "register and list_tools with annotations" do
    test "tool with annotations is listed with annotations preserved", %{registry: registry} do
      tool = %{
        name: "read_file",
        description: "Read a file from disk",
        input_schema: %{type: "object", properties: %{path: %{type: "string"}}},
        module: SomeModule.ReadFile,
        annotations: %{readOnlyHint: true, openWorldHint: false}
      }

      assert :ok = Registry.register_tool(registry, tool)

      {:ok, tools} = Registry.list_tools(registry)
      assert length(tools) == 1

      [listed_tool] = tools
      assert listed_tool.name == "read_file"
      assert listed_tool.annotations == %{readOnlyHint: true, openWorldHint: false}
    end

    test "tool without annotations is listed normally", %{registry: registry} do
      tool = %{
        name: "simple_tool",
        description: "A simple tool",
        input_schema: %{type: "object"},
        module: SomeModule.Simple
      }

      assert :ok = Registry.register_tool(registry, tool)

      {:ok, tools} = Registry.list_tools(registry)
      assert length(tools) == 1

      [listed_tool] = tools
      assert listed_tool.name == "simple_tool"
      refute Map.has_key?(listed_tool, :annotations)
    end

    test "mixed tools with and without annotations both listed correctly", %{registry: registry} do
      annotated_tool = %{
        name: "annotated",
        description: "Has annotations",
        input_schema: %{type: "object"},
        module: SomeModule.Annotated,
        annotations: %{destructiveHint: true}
      }

      plain_tool = %{
        name: "plain",
        description: "No annotations",
        input_schema: %{type: "object"},
        module: SomeModule.Plain
      }

      assert :ok = Registry.register_tool(registry, annotated_tool)
      assert :ok = Registry.register_tool(registry, plain_tool)

      {:ok, tools} = Registry.list_tools(registry)
      assert length(tools) == 2

      annotated = Enum.find(tools, &(&1.name == "annotated"))
      assert annotated.annotations == %{destructiveHint: true}

      plain = Enum.find(tools, &(&1.name == "plain"))
      refute Map.has_key?(plain, :annotations)
    end
  end

  describe "register and get_tool with annotations" do
    test "tool with annotations round-trips through register/get", %{registry: registry} do
      annotations = %{
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
        title: "My Annotated Tool"
      }

      tool = %{
        name: "roundtrip",
        description: "Round-trip test tool",
        input_schema: %{type: "object", properties: %{x: %{type: "number"}}},
        module: SomeModule.Roundtrip,
        annotations: annotations
      }

      assert :ok = Registry.register_tool(registry, tool)

      {:ok, retrieved} = Registry.get_tool(registry, "roundtrip")

      assert retrieved.name == "roundtrip"
      assert retrieved.description == "Round-trip test tool"
      assert retrieved.module == SomeModule.Roundtrip
      assert retrieved.annotations == annotations
      assert retrieved.annotations.readOnlyHint == true
      assert retrieved.annotations.destructiveHint == false
      assert retrieved.annotations.idempotentHint == true
      assert retrieved.annotations.openWorldHint == false
      assert retrieved.annotations.title == "My Annotated Tool"
    end

    test "tool without annotations round-trips without annotations key", %{registry: registry} do
      tool = %{
        name: "no_annotations",
        description: "No annotations tool",
        input_schema: %{type: "object"},
        module: SomeModule.NoAnnotations
      }

      assert :ok = Registry.register_tool(registry, tool)

      {:ok, retrieved} = Registry.get_tool(registry, "no_annotations")

      assert retrieved.name == "no_annotations"
      refute Map.has_key?(retrieved, :annotations)
    end
  end

  describe "atom name normalization with annotations" do
    test "tool registered with atom name can be retrieved by string name with annotations", %{
      registry: registry
    } do
      tool = %{
        name: :my_tool,
        description: "Atom-named tool",
        input_schema: %{type: "object"},
        module: SomeModule.MyTool,
        annotations: %{readOnlyHint: true}
      }

      assert :ok = Registry.register_tool(registry, tool)

      {:ok, retrieved} = Registry.get_tool(registry, "my_tool")
      assert retrieved.annotations == %{readOnlyHint: true}
    end
  end
end
