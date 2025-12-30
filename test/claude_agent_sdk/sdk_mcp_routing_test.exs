defmodule ClaudeAgentSDK.SDKMCPRoutingTest do
  use ClaudeAgentSDK.SupertesterCase
  @moduletag capture_log: true

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.{CalculatorTools, ErrorTools, MockTransport}

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  test "returns method-not-found for resources/list via SDK MCP routing" do
    server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "calc",
        version: "1.0.0",
        tools: [CalculatorTools.Add]
      )

    options = %Options{
      mcp_servers: %{"calc" => server}
    }

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    transport =
      receive do
        {:mock_transport_started, pid} -> pid
      after
        500 -> flunk("Transport did not start")
      end

    # Ensure subscription is complete by making a synchronous call to the client
    _ = :sys.get_state(client)

    request_id = "req_resources_list"

    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "sdk_mcp_request",
        "serverName" => "calc",
        "message" => %{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "resources/list",
          "params" => %{}
        }
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))

    response =
      SupertesterCase.eventually(
        fn ->
          transport
          |> MockTransport.recorded_messages()
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(fn
            # New Python SDK-compatible format: request_id is inside response.response
            %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
            _ -> false
          end)
        end,
        timeout: 5_000
      )

    mcp_response = response["response"]["response"]["mcp_response"]
    error = mcp_response["error"]
    assert error["code"] == -32_601
    assert error["message"] == "Method not found: resources/list"
  end

  test "returns method-not-found for resources/list with Python MCP subtype" do
    server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "calc",
        version: "1.0.0",
        tools: [CalculatorTools.Add]
      )

    options = %Options{
      mcp_servers: %{"calc" => server}
    }

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    transport =
      receive do
        {:mock_transport_started, pid} -> pid
      after
        500 -> flunk("Transport did not start")
      end

    _ = :sys.get_state(client)

    request_id = "req_resources_list_py"

    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "mcp_message",
        "server_name" => "calc",
        "message" => %{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "resources/list",
          "params" => %{}
        }
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))

    response =
      SupertesterCase.eventually(
        fn ->
          transport
          |> MockTransport.recorded_messages()
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(fn
            # New Python SDK-compatible format: request_id is inside response.response
            %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
            _ -> false
          end)
        end,
        timeout: 5_000
      )

    mcp_response = response["response"]["response"]["mcp_response"]
    error = mcp_response["error"]
    assert error["code"] == -32_601
    assert error["message"] == "Method not found: resources/list"
  end

  test "returns method-not-found for prompts/list" do
    server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "calc",
        version: "1.0.0",
        tools: [CalculatorTools.Add]
      )

    options = %Options{
      mcp_servers: %{"calc" => server}
    }

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    transport =
      receive do
        {:mock_transport_started, pid} -> pid
      after
        500 -> flunk("Transport did not start")
      end

    _ = :sys.get_state(client)

    request_id = "req_prompts_list"

    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "sdk_mcp_request",
        "serverName" => "calc",
        "message" => %{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "prompts/list",
          "params" => %{}
        }
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))

    response =
      SupertesterCase.eventually(
        fn ->
          transport
          |> MockTransport.recorded_messages()
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(fn
            %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
            _ -> false
          end)
        end,
        timeout: 5_000
      )

    mcp_response = response["response"]["response"]["mcp_response"]
    error = mcp_response["error"]
    assert error["code"] == -32_601
    assert error["message"] == "Method not found: prompts/list"
  end

  test "initialize returns configured server name and version" do
    server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "calc-real",
        version: "2.3.4",
        tools: [CalculatorTools.Add]
      )

    options = %Options{
      mcp_servers: %{"calc" => server}
    }

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    transport =
      receive do
        {:mock_transport_started, pid} -> pid
      after
        500 -> flunk("Transport did not start")
      end

    _ = :sys.get_state(client)

    request_id = "req_init"

    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "sdk_mcp_request",
        "serverName" => "calc",
        "message" => %{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "initialize",
          "params" => %{}
        }
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))

    response =
      SupertesterCase.eventually(
        fn ->
          transport
          |> MockTransport.recorded_messages()
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(fn
            %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
            _ -> false
          end)
        end,
        timeout: 5_000
      )

    mcp_response = response["response"]["response"]["mcp_response"]
    server_info = mcp_response["result"]["serverInfo"]
    assert server_info["name"] == "calc-real"
    assert server_info["version"] == "2.3.4"
  end

  test "tools/call returns successful result payloads" do
    server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "calc",
        version: "1.0.0",
        tools: [CalculatorTools.Add]
      )

    options = %Options{
      mcp_servers: %{"calc" => server}
    }

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    transport =
      receive do
        {:mock_transport_started, pid} -> pid
      after
        500 -> flunk("Transport did not start")
      end

    _ = :sys.get_state(client)

    request_id = "req_tool_call_success"

    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "sdk_mcp_request",
        "serverName" => "calc",
        "message" => %{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "tools/call",
          "params" => %{
            "name" => "add",
            "arguments" => %{"a" => 5, "b" => 3}
          }
        }
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))

    response =
      SupertesterCase.eventually(
        fn ->
          transport
          |> MockTransport.recorded_messages()
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(fn
            %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
            _ -> false
          end)
        end,
        timeout: 5_000
      )

    mcp_response = response["response"]["response"]["mcp_response"]
    refute Map.has_key?(mcp_response, "error")

    result = mcp_response["result"]
    assert Enum.any?(result["content"], &(&1["text"] == "5 + 3 = 8"))
  end

  test "tools/call returns is_error in result instead of JSONRPC error" do
    server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "errors",
        version: "1.0.0",
        tools: [ErrorTools.FailTool, ErrorTools.RaiseTool]
      )

    options = %Options{
      mcp_servers: %{"errors" => server}
    }

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    transport =
      receive do
        {:mock_transport_started, pid} -> pid
      after
        500 -> flunk("Transport did not start")
      end

    _ = :sys.get_state(client)

    request_id = "req_tool_call_error"

    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "sdk_mcp_request",
        "serverName" => "errors",
        "message" => %{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "tools/call",
          "params" => %{
            "name" => "raise_tool",
            "arguments" => %{}
          }
        }
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))

    response =
      SupertesterCase.eventually(
        fn ->
          transport
          |> MockTransport.recorded_messages()
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(fn
            %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
            _ -> false
          end)
        end,
        timeout: 5_000
      )

    mcp_response = response["response"]["response"]["mcp_response"]
    refute Map.has_key?(mcp_response, "error")

    result = mcp_response["result"]
    assert result["is_error"] == true
    refute Map.has_key?(result, "isError")
    assert is_list(result["content"])
  end

  test "tools/call wraps tool errors with is_error result payload" do
    server =
      ClaudeAgentSDK.create_sdk_mcp_server(
        name: "errors",
        version: "1.0.0",
        tools: [ErrorTools.FailTool]
      )

    options = %Options{
      mcp_servers: %{"errors" => server}
    }

    {:ok, client} =
      Client.start_link(options,
        transport: MockTransport,
        transport_opts: [test_pid: self()]
      )

    on_exit(fn -> safe_stop(client) end)

    transport =
      receive do
        {:mock_transport_started, pid} -> pid
      after
        500 -> flunk("Transport did not start")
      end

    _ = :sys.get_state(client)

    request_id = "req_tool_call_fail"

    request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => %{
        "subtype" => "sdk_mcp_request",
        "serverName" => "errors",
        "message" => %{
          "jsonrpc" => "2.0",
          "id" => "1",
          "method" => "tools/call",
          "params" => %{
            "name" => "fail_tool",
            "arguments" => %{}
          }
        }
      }
    }

    MockTransport.push_message(transport, Jason.encode!(request))

    response =
      SupertesterCase.eventually(
        fn ->
          transport
          |> MockTransport.recorded_messages()
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(fn
            %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
            _ -> false
          end)
        end,
        timeout: 5_000
      )

    mcp_response = response["response"]["response"]["mcp_response"]
    refute Map.has_key?(mcp_response, "error")

    result = mcp_response["result"]
    assert result["is_error"] == true
    assert is_list(result["content"])
  end

  defp safe_stop(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
