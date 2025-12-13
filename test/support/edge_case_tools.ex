defmodule ClaudeAgentSDK.TestSupport.EdgeCase.MinimalTool do
  @moduledoc false

  use ClaudeAgentSDK.Tool

  deftool :minimal,
          "Minimal tool",
          %{type: "object"} do
    def execute(_args) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "success"}]}}
    end
  end
end

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.OptionalTool do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.NestedTool do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.ArrayTool do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.UnderscoreTest do
  @moduledoc false

  use ClaudeAgentSDK.Tool

  deftool :my_special_tool,
          "Tool with underscores",
          %{type: "object"} do
    def execute(_args) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "ok"}]}}
    end
  end
end

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.LargeInputTool do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.LargeOutputTool do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.ConcurrentTool do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.StrictTool do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.TimeoutTool do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.NumericTools do
  @moduledoc false

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

defmodule ClaudeAgentSDK.TestSupport.EdgeCase.SingleChar do
  @moduledoc false

  use ClaudeAgentSDK.Tool

  deftool :a,
          "Single char",
          %{type: "object"} do
    def execute(_), do: {:ok, %{"content" => []}}
  end
end
