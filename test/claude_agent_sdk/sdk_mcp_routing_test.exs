defmodule ClaudeAgentSDK.SDKMCPRoutingTest do
  use ClaudeAgentSDK.SupertesterCase
  @moduletag capture_log: true

  alias ClaudeAgentSDK.{Client, Options}
  alias ClaudeAgentSDK.TestSupport.{CalculatorTools, MockTransport}

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  test "supports resources/list via SDK MCP routing with empty capabilities" do
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
            %{"type" => "control_response", "id" => ^request_id} -> true
            _ -> false
          end)
        end,
        timeout: 5_000
      )

    result = response["response"]["result"]
    assert result["resources"] == []
  end

  defp safe_stop(client) do
    try do
      Client.stop(client)
    catch
      :exit, _ -> :ok
    end
  end
end
