defmodule ClaudeAgentSDK.SDKMCPIntegrationTest do
  @moduledoc """
  Integration tests for SDK MCP server support - SIMPLIFIED VERSION

  These tests are SKIPPED until the control protocol JSONRPC routing is implemented.
  They demonstrate the intended API and verify the design.
  """

  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Options, Tool}
  alias ClaudeAgentSDK.TestSupport.CalculatorTools

  describe "SDK MCP server creation and configuration" do
    test "create_sdk_mcp_server returns correct structure" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "test-server",
          version: "1.0.0",
          tools: [CalculatorTools.Add]
        )

      assert server.type == :sdk
      assert server.name == "test-server"
      assert server.version == "1.0.0"
      assert is_pid(server.registry_pid)
    end

    test "tools are registered in the server registry" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "math",
          version: "1.0.0",
          tools: [CalculatorTools.Add, CalculatorTools.GreetUser]
        )

      {:ok, tools} = Tool.Registry.list_tools(server.registry_pid)
      assert length(tools) == 2
      assert Enum.any?(tools, &(&1.name == :add))
      assert Enum.any?(tools, &(&1.name == :greet_user))
    end

    test "Options accepts mcp_servers map" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "test",
          version: "1.0.0",
          tools: []
        )

      options = Options.new(mcp_servers: %{"test" => server})

      assert options.mcp_servers["test"].type == :sdk
      assert is_map(options.mcp_servers)
    end
  end

  describe "CLI args preparation" do
    test "prepare_servers_for_cli strips registry_pid from SDK servers" do
      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "sdk-server",
          version: "2.0.0",
          tools: []
        )

      servers = %{"sdk" => server}
      prepared = Options.prepare_servers_for_cli(servers)

      # SDK server should have metadata only (no registry_pid)
      assert prepared["sdk"]["type"] == "sdk"
      assert prepared["sdk"]["name"] == "sdk-server"
      assert prepared["sdk"]["version"] == "2.0.0"
      refute Map.has_key?(prepared["sdk"], "registry_pid")
    end

    test "prepare_servers_for_cli converts external servers to string keys" do
      servers = %{
        "external" => %{type: :stdio, command: "test", args: ["--version"]}
      }

      prepared = Options.prepare_servers_for_cli(servers)

      # stringify_keys converts atom keys AND values to strings for JSON
      assert prepared["external"]["type"] == "stdio"
      assert prepared["external"]["command"] == "test"
      assert prepared["external"]["args"] == ["--version"]
    end

    test "prepare_servers_for_cli handles mixed SDK and external servers" do
      sdk_server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "sdk",
          version: "1.0.0",
          tools: []
        )

      servers = %{
        "sdk" => sdk_server,
        "external" => %{type: :stdio, command: "echo", args: []}
      }

      prepared = Options.prepare_servers_for_cli(servers)

      # SDK server
      assert prepared["sdk"]["type"] == "sdk"
      refute Map.has_key?(prepared["sdk"], "registry_pid")

      # External server (stringify_keys converts atoms to strings)
      assert prepared["external"]["type"] == "stdio"
    end

    test "Options.to_args does NOT include SDK servers in --mcp-config" do
      sdk_server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "test",
          version: "1.0.0",
          tools: []
        )

      options = Options.new(mcp_servers: %{"test" => sdk_server})
      args = Options.to_args(options)

      # SDK servers should NOT be passed to CLI via --mcp-config
      # They are handled via control protocol in Client
      refute "--mcp-config" in args
    end

    test "Options.to_args includes external servers in --mcp-config" do
      external_server = %{
        type: :stdio,
        command: "uvx",
        args: ["mcp-server-time"]
      }

      options = Options.new(mcp_servers: %{"time" => external_server})
      args = Options.to_args(options)

      # External servers should be passed to CLI via --mcp-config
      assert "--mcp-config" in args
      config_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_config = Enum.at(args, config_index + 1)

      # Should be valid JSON
      servers = Jason.decode!(json_config)
      assert servers["time"]["type"] == "stdio"
      assert servers["time"]["command"] == "uvx"
    end

    test "Options.to_args includes only external servers when mixed with SDK servers" do
      sdk_server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "sdk-server",
          version: "1.0.0",
          tools: []
        )

      external_server = %{
        type: :stdio,
        command: "test",
        args: []
      }

      options =
        Options.new(mcp_servers: %{"sdk" => sdk_server, "external" => external_server})

      args = Options.to_args(options)

      # Should have --mcp-config with only external server
      assert "--mcp-config" in args
      config_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_config = Enum.at(args, config_index + 1)

      servers = Jason.decode!(json_config)
      # Only external server should be in config
      assert Map.has_key?(servers, "external")
      refute Map.has_key?(servers, "sdk")
    end
  end

  # The following tests verify the control protocol implementation

  describe "SDK MCP tool integration (LIVE TESTS)" do
    @tag :integration
    @tag :skip
    test "SDK MCP server responds to initialize request" do
      # This test would require simulating control protocol messages
      # For now, we rely on manual testing with live examples
      :ok
    end

    @tag :integration
    @tag :skip
    test "SDK MCP server lists tools correctly" do
      # This test would require simulating control protocol messages
      # For now, we rely on manual testing with live examples
      :ok
    end

    @tag :integration
    @tag :skip
    test "SDK MCP server executes tools correctly" do
      # This test would require simulating control protocol messages
      # For now, we rely on manual testing with live examples
      :ok
    end
  end
end
