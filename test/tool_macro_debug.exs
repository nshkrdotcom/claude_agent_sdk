defmodule ToolMacroDebug do
  use ClaudeAgentSDK.Tool

  deftool :simple_add,
          "Simple addition",
          %{type: "object"} do
    def execute(%{"a" => a, "b" => b}) do
      {:ok, %{"result" => a + b}}
    end
  end
end

# Check if module was created
IO.puts("ToolMacroDebug module loaded: #{Code.ensure_loaded?(ToolMacroDebug)}")
IO.puts("ToolMacroDebug.SimpleAdd exists: #{Code.ensure_loaded?(ToolMacroDebug.SimpleAdd)}")

if Code.ensure_loaded?(ToolMacroDebug.SimpleAdd) do
  IO.puts(
    "Has __tool_metadata__: #{function_exported?(ToolMacroDebug.SimpleAdd, :__tool_metadata__, 0)}"
  )

  IO.puts("Has execute: #{function_exported?(ToolMacroDebug.SimpleAdd, :execute, 1)}")

  if function_exported?(ToolMacroDebug.SimpleAdd, :__tool_metadata__, 0) do
    metadata = ToolMacroDebug.SimpleAdd.__tool_metadata__()
    IO.puts("Metadata: #{inspect(metadata)}")
  end
end

if function_exported?(ToolMacroDebug, :__tools__, 0) do
  tools = ToolMacroDebug.__tools__()
  IO.puts("Tools registered: #{length(tools)}")
  IO.puts("Tools: #{inspect(tools)}")
end
