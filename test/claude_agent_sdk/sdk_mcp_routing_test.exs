defmodule ClaudeAgentSDK.SDKMCPRoutingTest do
  use ClaudeAgentSDK.SupertesterCase
  @moduletag capture_log: true

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.{CalculatorTools, ErrorTools, FakeCLI}

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  test "returns method-not-found for resources/list via SDK MCP routing" do
    server = sdk_server("calc", [CalculatorTools.Add])

    %{client: client, transport: transport} =
      start_client_with_fake_cli(%Options{mcp_servers: %{"calc" => server}})

    on_exit(fn -> safe_stop(client) end)

    request_id = "req_resources_list"

    FakeCLI.push_message(
      transport,
      sdk_mcp_request(request_id, "calc", %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "resources/list",
        "params" => %{}
      })
    )

    {:ok, response} = FakeCLI.wait_for_control_response(transport, request_id, 5_000)
    mcp_response = response["response"]["response"]["mcp_response"]
    error = mcp_response["error"]

    assert error["code"] == -32_601
    assert error["message"] == "Method not found: resources/list"
  end

  test "returns server-not-found for unknown SDK MCP server" do
    server = sdk_server("calc", [CalculatorTools.Add])

    %{client: client, transport: transport} =
      start_client_with_fake_cli(%Options{mcp_servers: %{"calc" => server}})

    on_exit(fn -> safe_stop(client) end)

    request_id = "req_unknown_server"

    FakeCLI.push_message(
      transport,
      sdk_mcp_request(request_id, "missing", %{
        "jsonrpc" => "2.0",
        "id" => "2",
        "method" => "tools/list",
        "params" => %{}
      })
    )

    {:ok, response} = FakeCLI.wait_for_control_response(transport, request_id, 5_000)
    error = response["response"]["response"]["mcp_response"]["error"]

    assert error["code"] == -32_601
    assert error["message"] == "Server 'missing' not found"
  end

  test "routes tools/list through the SDK MCP registry" do
    server = sdk_server("calc", [CalculatorTools.Add, CalculatorTools.GreetUser])

    %{client: client, transport: transport} =
      start_client_with_fake_cli(%Options{mcp_servers: %{"calc" => server}})

    on_exit(fn -> safe_stop(client) end)

    request_id = "req_tools_list"

    FakeCLI.push_message(
      transport,
      sdk_mcp_request(request_id, "calc", %{
        "jsonrpc" => "2.0",
        "id" => "3",
        "method" => "tools/list",
        "params" => %{}
      })
    )

    {:ok, response} = FakeCLI.wait_for_control_response(transport, request_id, 5_000)
    tools = response["response"]["response"]["mcp_response"]["result"]["tools"]
    names = Enum.map(tools, & &1["name"])

    assert "add" in names
    assert "greet_user" in names
  end

  test "normalizes SDK MCP tool failures into MCP error results" do
    server = sdk_server("errors", [ErrorTools.FailTool, ErrorTools.RaiseTool])

    %{client: client, transport: transport} =
      start_client_with_fake_cli(%Options{mcp_servers: %{"errors" => server}})

    on_exit(fn -> safe_stop(client) end)

    fail_request_id = "req_fail_tool"

    FakeCLI.push_message(
      transport,
      sdk_mcp_request(fail_request_id, "errors", %{
        "jsonrpc" => "2.0",
        "id" => "4",
        "method" => "tools/call",
        "params" => %{"name" => "fail_tool", "arguments" => %{}}
      })
    )

    {:ok, fail_response} = FakeCLI.wait_for_control_response(transport, fail_request_id, 5_000)
    fail_result = fail_response["response"]["response"]["mcp_response"]["result"]

    assert fail_result["is_error"] == true
    assert [%{"text" => "Expected error"}] = fail_result["content"]

    raise_request_id = "req_raise_tool"

    FakeCLI.push_message(
      transport,
      sdk_mcp_request(raise_request_id, "errors", %{
        "jsonrpc" => "2.0",
        "id" => "5",
        "method" => "tools/call",
        "params" => %{"name" => "raise_tool", "arguments" => %{}}
      })
    )

    {:ok, raise_response} = FakeCLI.wait_for_control_response(transport, raise_request_id, 5_000)
    error = raise_response["response"]["response"]["mcp_response"]["error"]

    assert error["code"] == -32_603
    assert error["message"] =~ "Intentional error"
  end

  defp start_client_with_fake_cli(options) do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options))

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    _request_id = FakeCLI.respond_initialize_success!(fake_cli)
    assert :ok = Client.await_initialized(client, 1_000)

    %{client: client, transport: fake_cli}
  end

  defp sdk_server(name, tools) do
    ClaudeAgentSDK.create_sdk_mcp_server(name: name, version: "1.0.0", tools: tools)
  end

  defp sdk_mcp_request(request_id, server_name, message) do
    %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "sdk_mcp_request",
        "serverName" => server_name,
        "message" => message
      }
    }
  end

  defp safe_stop(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
