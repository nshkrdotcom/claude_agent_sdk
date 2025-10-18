defmodule ClaudeAgentSDK.SDKMCPServerTest do
  @moduledoc """
  Integration tests for SDK MCP server creation and usage.

  Mirrors the Python test_sdk_mcp_integration.py test patterns.
  """

  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Tool, Options}

  describe "create_sdk_mcp_server/2" do
    defmodule CalculatorTools do
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

    test "creates SDK MCP server with tools" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "test-server",
          version: "1.0.0",
          tools: [CalculatorTools.Add, CalculatorTools.GreetUser]
        )

      assert server.type == :sdk
      assert server.name == "test-server"
      assert server.version == "1.0.0"
      assert is_pid(server.registry_pid)
    end

    test "server has correct tool count" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "calc-server",
          version: "1.0.0",
          tools: [CalculatorTools.Add, CalculatorTools.GreetUser]
        )

      {:ok, tools} = Tool.Registry.list_tools(server.registry_pid)
      assert length(tools) == 2

      names = Enum.map(tools, & &1.name)
      assert :add in names
      assert :greet_user in names
    end

    test "creates empty server with no tools" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "empty-server",
          version: "2.0.0",
          tools: []
        )

      {:ok, tools} = Tool.Registry.list_tools(server.registry_pid)
      assert tools == []
    end

    test "server config includes all required fields" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "full-server",
          version: "1.5.0",
          tools: [CalculatorTools.Add]
        )

      assert Map.has_key?(server, :type)
      assert Map.has_key?(server, :name)
      assert Map.has_key?(server, :version)
      assert Map.has_key?(server, :registry_pid)
    end
  end

  describe "SDK MCP server in Options" do
    test "accepts SDK server in mcp_servers option" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "calc",
          version: "1.0.0",
          tools: [CalculatorTools.Add]
        )

      options = %Options{
        mcp_config: %{"calc" => server}
      }

      assert options.mcp_config["calc"].type == :sdk
    end

    test "accepts mix of SDK and external servers" do
      sdk_server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "sdk-tools",
          version: "1.0.0",
          tools: [CalculatorTools.Add]
        )

      external_server = %{
        type: :stdio,
        command: "node",
        args: ["server.js"]
      }

      options = %Options{
        mcp_config: %{
          "sdk" => sdk_server,
          "external" => external_server
        }
      }

      assert options.mcp_config["sdk"].type == :sdk
      assert options.mcp_config["external"].type == :stdio
    end
  end

  describe "tool execution through server" do
    setup do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "test-exec",
          version: "1.0.0",
          tools: [CalculatorTools.Add, CalculatorTools.GreetUser]
        )

      %{server: server}
    end

    test "executes tool successfully", %{server: server} do
      {:ok, result} = Tool.Registry.execute_tool(server.registry_pid, :add, %{"a" => 5, "b" => 3})

      assert result["content"] == [%{"type" => "text", "text" => "5 + 3 = 8"}]
    end

    test "executes different tools", %{server: server} do
      {:ok, result} =
        Tool.Registry.execute_tool(server.registry_pid, :greet_user, %{"name" => "Alice"})

      assert result["content"] == [%{"type" => "text", "text" => "Hello, Alice!"}]
    end

    test "handles tool not found", %{server: server} do
      assert {:error, :not_found} =
               Tool.Registry.execute_tool(server.registry_pid, :nonexistent, %{})
    end
  end

  describe "error handling" do
    defmodule ErrorTools do
      use ClaudeAgentSDK.Tool

      deftool :fail_tool,
              "Always fails",
              %{type: "object"} do
        def execute(_args) do
          {:error, "Expected error"}
        end
      end

      deftool :raise_tool,
              "Raises exception",
              %{type: "object"} do
        def execute(_args) do
          raise "Intentional exception"
        end
      end
    end

    test "handles tool errors gracefully" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "error-server",
          version: "1.0.0",
          tools: [ErrorTools.FailTool]
        )

      assert {:error, "Expected error"} =
               Tool.Registry.execute_tool(server.registry_pid, :fail_tool, %{})
    end

    test "handles exceptions in tools" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "exception-server",
          version: "1.0.0",
          tools: [ErrorTools.RaiseTool]
        )

      result = Tool.Registry.execute_tool(server.registry_pid, :raise_tool, %{})

      # Should catch exception and return error tuple
      assert match?({:error, _}, result)
    end
  end

  describe "image content support" do
    defmodule ImageTools do
      use ClaudeAgentSDK.Tool

      deftool :generate_chart,
              "Generates a chart and returns it as an image",
              %{
                type: "object",
                properties: %{title: %{type: "string"}},
                required: ["title"]
              } do
        def execute(%{"title" => title}) do
          # Simple 1x1 PNG in base64
          png_data =
            <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0,
              1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 9, 112, 72, 89, 115, 0, 0, 11, 19, 0,
              0, 11, 19, 1, 0, 154, 156, 24, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96,
              96, 0, 0, 0, 4, 0, 1, 93, 85, 33, 28, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
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

    test "returns image content correctly" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "image-server",
          version: "1.0.0",
          tools: [ImageTools.GenerateChart]
        )

      {:ok, result} =
        Tool.Registry.execute_tool(server.registry_pid, :generate_chart, %{"title" => "Sales"})

      assert length(result["content"]) == 2
      [text, image] = result["content"]

      assert text["type"] == "text"
      assert text["text"] == "Generated chart: Sales"

      assert image["type"] == "image"
      assert is_binary(image["data"])
      assert image["mimeType"] == "image/png"
    end
  end

  describe "server lifecycle" do
    test "server registry is supervised" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "lifecycle-test",
          version: "1.0.0",
          tools: [CalculatorTools.Add]
        )

      # Registry should be a running process
      assert Process.alive?(server.registry_pid)

      # Can still use registry
      {:ok, tools} = Tool.Registry.list_tools(server.registry_pid)
      assert length(tools) == 1
    end

    test "multiple servers can coexist" do
      server1 =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "server1",
          version: "1.0.0",
          tools: [CalculatorTools.Add]
        )

      server2 =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "server2",
          version: "1.0.0",
          tools: [CalculatorTools.GreetUser]
        )

      assert server1.registry_pid != server2.registry_pid

      {:ok, tools1} = Tool.Registry.list_tools(server1.registry_pid)
      {:ok, tools2} = Tool.Registry.list_tools(server2.registry_pid)

      assert length(tools1) == 1
      assert length(tools2) == 1
      assert hd(tools1).name == :add
      assert hd(tools2).name == :greet_user
    end
  end
end
