defmodule ClaudeAgentSDK.ControlProtocol.ProtocolTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.ControlProtocol.Protocol

  describe "encode_initialize_request/3" do
    test "encodes initialize request with hooks" do
      hooks_config = %{
        "PreToolUse" => [
          %{
            "matcher" => "Bash",
            "hookCallbackIds" => ["hook_0"]
          }
        ]
      }

      {request_id, json} = Protocol.encode_initialize_request(hooks_config, nil, "req_123")

      assert request_id == "req_123"
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_123"
      assert decoded["request"]["subtype"] == "initialize"
      assert decoded["request"]["hooks"] == hooks_config
    end

    test "generates request ID when not provided" do
      {request_id, json} = Protocol.encode_initialize_request(nil, nil, nil)

      assert is_binary(request_id)
      assert String.starts_with?(request_id, "req_")

      decoded = Jason.decode!(json)
      assert decoded["request_id"] == request_id
    end

    test "encodes with nil hooks" do
      {_request_id, json} = Protocol.encode_initialize_request(nil, nil, "req_456")

      decoded = Jason.decode!(json)
      assert decoded["request"]["hooks"] == nil
    end

    test "encodes with SDK MCP servers" do
      hooks_config = %{
        "PreToolUse" => [
          %{
            "matcher" => "Bash",
            "hookCallbackIds" => ["hook_0"]
          }
        ]
      }

      sdk_mcp_servers = %{
        "math-tools" => %{"name" => "math-tools", "version" => "1.0.0"}
      }

      {request_id, json} =
        Protocol.encode_initialize_request(hooks_config, sdk_mcp_servers, "req_789")

      assert request_id == "req_789"
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_789"
      assert decoded["request"]["subtype"] == "initialize"
      assert decoded["request"]["hooks"] == hooks_config
      assert decoded["request"]["sdkMcpServers"] == sdk_mcp_servers
    end
  end

  describe "encode_hook_response/3" do
    test "encodes success response with hook output" do
      output = %{
        hookSpecificOutput: %{
          hookEventName: "PreToolUse",
          permissionDecision: "deny"
        }
      }

      json = Protocol.encode_hook_response("req_123", output, :success)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_response"
      assert decoded["response"]["subtype"] == "success"
      assert decoded["response"]["request_id"] == "req_123"
      assert decoded["response"]["response"]["hookSpecificOutput"]["permissionDecision"] == "deny"
    end

    test "encodes error response" do
      json = Protocol.encode_hook_response("req_456", "Callback not found", :error)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_response"
      assert decoded["response"]["subtype"] == "error"
      assert decoded["response"]["request_id"] == "req_456"
      assert decoded["response"]["error"] == "Callback not found"
    end
  end

  describe "decode_message/1" do
    test "decodes control_request message" do
      json = """
      {"type":"control_request","request_id":"req_123","request":{"subtype":"hook_callback","callback_id":"hook_0","input":{}}}
      """

      assert {:ok, {:control_request, data}} = Protocol.decode_message(json)
      assert data["request_id"] == "req_123"
      assert data["request"]["subtype"] == "hook_callback"
    end

    test "decodes control_response message" do
      json = """
      {"type":"control_response","response":{"subtype":"success","request_id":"req_123","response":{}}}
      """

      assert {:ok, {:control_response, data}} = Protocol.decode_message(json)
      assert data["response"]["subtype"] == "success"
    end

    test "decodes regular SDK message" do
      json = """
      {"type":"assistant","message":{"role":"assistant","content":"Hello"}}
      """

      assert {:ok, {:sdk_message, data}} = Protocol.decode_message(json)
      assert data["type"] == "assistant"
    end

    test "returns error for invalid JSON" do
      assert {:error, _reason} = Protocol.decode_message("not json")
    end

    test "returns error for empty string" do
      assert {:error, _reason} = Protocol.decode_message("")
    end
  end

  describe "generate_request_id/0" do
    test "generates unique request IDs" do
      id1 = Protocol.generate_request_id()
      id2 = Protocol.generate_request_id()
      id3 = Protocol.generate_request_id()

      assert id1 != id2
      assert id2 != id3
      assert String.starts_with?(id1, "req_")
      assert String.starts_with?(id2, "req_")
    end

    test "request IDs contain counter and random component" do
      id = Protocol.generate_request_id()

      assert String.starts_with?(id, "req_")
      # Format: req_{counter}_{hex}
      parts = String.split(id, "_")
      assert length(parts) == 3
    end
  end

  describe "is_control_message?/1" do
    test "returns true for control_request" do
      msg = %{"type" => "control_request"}
      assert Protocol.is_control_message?(msg) == true
    end

    test "returns true for control_response" do
      msg = %{"type" => "control_response"}
      assert Protocol.is_control_message?(msg) == true
    end

    test "returns false for SDK messages" do
      msg = %{"type" => "assistant"}
      assert Protocol.is_control_message?(msg) == false
    end

    test "returns false for unknown types" do
      msg = %{"type" => "unknown"}
      assert Protocol.is_control_message?(msg) == false
    end

    test "returns false for messages without type" do
      msg = %{"data" => "something"}
      assert Protocol.is_control_message?(msg) == false
    end
  end
end
