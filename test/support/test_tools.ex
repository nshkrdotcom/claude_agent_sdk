defmodule ClaudeAgentSDK.TestSupport.CalculatorTools do
  @moduledoc false

  use ClaudeAgentSDK.Tool

  deftool :add,
          "Add two numbers",
          %{
            type: "object",
            properties: %{a: %{type: "number"}, b: %{type: "number"}},
            required: ["a", "b"]
          } do
    def execute(%{"a" => a, "b" => b}) do
      result = a + b
      {:ok, %{"content" => [%{"type" => "text", "text" => "#{a} + #{b} = #{result}"}]}}
    end
  end

  deftool :greet_user,
          "Greets a user by name",
          %{
            type: "object",
            properties: %{name: %{type: "string"}},
            required: ["name"]
          } do
    def execute(%{"name" => name}) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "Hello, #{name}!"}]}}
    end
  end
end

defmodule ClaudeAgentSDK.TestSupport.ErrorTools do
  @moduledoc false

  use ClaudeAgentSDK.Tool

  deftool :fail_tool,
          "Always fails",
          %{type: "object"} do
    def execute(_input) do
      {:error, "Expected error"}
    end
  end

  deftool :raise_tool,
          "Raises an exception",
          %{type: "object"} do
    def execute(_input) do
      raise "Intentional error"
    end
  end
end

defmodule ClaudeAgentSDK.TestSupport.ImageTools do
  @moduledoc false

  use ClaudeAgentSDK.Tool

  deftool :generate_chart,
          "Generates a chart image",
          %{
            type: "object",
            properties: %{
              title: %{type: "string"}
            },
            required: ["title"]
          } do
    def execute(%{"title" => title}) do
      # Simple 1x1 PNG in base64
      png_data =
        <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
          2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 9, 112, 72, 89, 115, 0, 0, 11, 19, 0, 0, 11, 19,
          1, 0, 154, 156, 24, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96, 96, 0, 0, 0, 4,
          0, 1, 93, 85, 33, 28, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
        |> Base.encode64()

      {:ok,
       %{
         "content" => [
           %{"type" => "text", "text" => "Generated chart: #{title}"},
           %{
             "type" => "image",
             "data" => png_data,
             "mimeType" => "image/png"
           }
         ]
       }}
    end
  end
end
