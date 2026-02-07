defmodule ClaudeAgentSDK.Parity.ToolAnnotationsTest.AnnotatedTools do
  @moduledoc false
  use ClaudeAgentSDK.Tool

  deftool :read_data,
          "Read data from a source",
          %{type: "object", properties: %{source: %{type: "string"}}, required: ["source"]},
          annotations: %{readOnlyHint: true} do
    def execute(%{"source" => source}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "Read from #{source}"}]}}
    end
  end

  deftool :plain_tool,
          "A tool with no annotations",
          %{type: "object"} do
    def execute(_input) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "done"}]}}
    end
  end

  deftool :full_annotations,
          "Tool with all standard MCP annotation hints",
          %{type: "object", properties: %{path: %{type: "string"}}, required: ["path"]},
          annotations: %{
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false,
            title: "Full Annotation Tool"
          } do
    def execute(%{"path" => path}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "Processed #{path}"}]}}
    end
  end

  deftool :destructive_tool,
          "Destructive operation",
          %{type: "object"},
          annotations: %{destructiveHint: true, readOnlyHint: false} do
    def execute(_input) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "destroyed"}]}}
    end
  end
end

defmodule ClaudeAgentSDK.Parity.ToolAnnotationsTest do
  @moduledoc """
  Tests for Phase 4: MCP tool annotations in deftool macro.

  Verifies that the 5th argument (options keyword list with :annotations key)
  is correctly stored in tool metadata and accessible via __tool_metadata__/0.
  """

  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Parity.ToolAnnotationsTest.AnnotatedTools
  alias ClaudeAgentSDK.Tool

  describe "deftool with annotations (5-arg form)" do
    test "tool with annotations includes annotations in __tool_metadata__/0" do
      metadata = AnnotatedTools.ReadData.__tool_metadata__()

      assert Map.has_key?(metadata, :annotations)
      assert metadata.annotations == %{readOnlyHint: true}
    end

    test "tool without annotations does NOT include annotations key in __tool_metadata__/0" do
      metadata = AnnotatedTools.PlainTool.__tool_metadata__()

      refute Map.has_key?(metadata, :annotations)
    end

    test "annotations are preserved with correct values" do
      metadata = AnnotatedTools.ReadData.__tool_metadata__()

      assert metadata.annotations.readOnlyHint == true
      assert metadata.name == :read_data
      assert metadata.description == "Read data from a source"
    end

    test "tool with all standard MCP hints preserves them all" do
      metadata = AnnotatedTools.FullAnnotations.__tool_metadata__()

      assert Map.has_key?(metadata, :annotations)
      annotations = metadata.annotations

      assert annotations.readOnlyHint == true
      assert annotations.destructiveHint == false
      assert annotations.idempotentHint == true
      assert annotations.openWorldHint == false
      assert annotations.title == "Full Annotation Tool"
    end

    test "annotations with partial hints only include specified hints" do
      metadata = AnnotatedTools.DestructiveTool.__tool_metadata__()

      assert Map.has_key?(metadata, :annotations)
      annotations = metadata.annotations

      assert annotations.destructiveHint == true
      assert annotations.readOnlyHint == false
      refute Map.has_key?(annotations, :idempotentHint)
      refute Map.has_key?(annotations, :openWorldHint)
      refute Map.has_key?(annotations, :title)
    end
  end

  describe "annotated tools remain functional" do
    test "annotated tool execute/1 works correctly" do
      {:ok, result} = AnnotatedTools.ReadData.execute(%{"source" => "database"})
      assert result["content"] == [%{"type" => "text", "text" => "Read from database"}]
    end

    test "unannotated tool execute/1 works correctly" do
      {:ok, result} = AnnotatedTools.PlainTool.execute(%{})
      assert result["content"] == [%{"type" => "text", "text" => "done"}]
    end
  end

  describe "Tool.list_tools/1 reflects annotations" do
    test "lists tools including those with and without annotations" do
      tools = Tool.list_tools(AnnotatedTools)

      assert length(tools) == 4

      annotated = Enum.find(tools, &(&1.name == :read_data))
      assert annotated.annotations == %{readOnlyHint: true}

      plain = Enum.find(tools, &(&1.name == :plain_tool))
      assert plain.annotations == nil
    end
  end
end
