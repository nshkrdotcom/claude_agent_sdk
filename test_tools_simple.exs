defmodule SimpleToolTest do
  use ClaudeAgentSDK.Tool

  deftool :test_tool, "Test", %{type: "object"} do
    def execute(_input) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "works"}]}}
    end
  end
end

IO.puts("Has __tools__?: #{function_exported?(SimpleToolTest, :__tools__, 0)}")

if function_exported?(SimpleToolTest, :__tools__, 0) do
  tools = SimpleToolTest.__tools__()
  IO.inspect(tools, label: "Tools")
  IO.puts("Tool count: #{length(tools)}")
else
  IO.puts("NO __tools__() function!")
end

IO.puts("\nHas execute?: #{function_exported?(SimpleToolTest.TestTool, :execute, 1)}")

if function_exported?(SimpleToolTest.TestTool, :execute, 1) do
  result = SimpleToolTest.TestTool.execute(%{})
  IO.inspect(result, label: "Execute result")
else
  IO.puts("NO execute() function!")
end
