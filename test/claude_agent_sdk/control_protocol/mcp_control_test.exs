defmodule ClaudeAgentSDK.ControlProtocol.McpControlTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.ControlProtocol.Protocol

  describe "encode_mcp_reconnect_request/2" do
    test "creates control request with mcp_reconnect subtype" do
      {request_id, json} = Protocol.encode_mcp_reconnect_request("my-server", "req_1")

      assert request_id == "req_1"
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_1"
      assert decoded["request"]["subtype"] == "mcp_reconnect"
      assert decoded["request"]["serverName"] == "my-server"
    end

    test "generates request ID when not provided" do
      {request_id, json} = Protocol.encode_mcp_reconnect_request("my-server")

      assert is_binary(request_id)
      assert String.starts_with?(request_id, "req_")

      decoded = Jason.decode!(json)
      assert decoded["request_id"] == request_id
    end
  end

  describe "encode_mcp_toggle_request/3" do
    test "creates control request with mcp_toggle subtype and enabled true" do
      {request_id, json} = Protocol.encode_mcp_toggle_request("my-server", true, "req_2")

      assert request_id == "req_2"
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request"]["subtype"] == "mcp_toggle"
      assert decoded["request"]["serverName"] == "my-server"
      assert decoded["request"]["enabled"] == true
    end

    test "creates control request with enabled false" do
      {_request_id, json} = Protocol.encode_mcp_toggle_request("my-server", false)

      decoded = Jason.decode!(json)
      assert decoded["request"]["enabled"] == false
    end
  end

  describe "encode_stop_task_request/2" do
    test "creates control request with stop_task subtype" do
      {request_id, json} = Protocol.encode_stop_task_request("task-abc", "req_3")

      assert request_id == "req_3"
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request"]["subtype"] == "stop_task"
      assert decoded["request"]["task_id"] == "task-abc"
    end

    test "generates request ID when not provided" do
      {request_id, _json} = Protocol.encode_stop_task_request("task-xyz")

      assert is_binary(request_id)
      assert String.starts_with?(request_id, "req_")
    end
  end
end
