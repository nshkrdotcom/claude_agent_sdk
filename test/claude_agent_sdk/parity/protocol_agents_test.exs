defmodule ClaudeAgentSDK.Parity.ProtocolAgentsTest do
  @moduledoc """
  Tests for Phase 1: agents parameter in initialize request.

  The `encode_initialize_request/4` function accepts an optional 4th `agents`
  parameter that, when non-nil and non-empty, is included in the request_data
  sent to the CLI during initialization.
  """

  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.ControlProtocol.Protocol

  describe "encode_initialize_request/4 agents parameter" do
    test "nil agents returns JSON without agents key" do
      hooks_config = %{"PreToolUse" => []}
      {_req_id, json} = Protocol.encode_initialize_request(hooks_config, nil, nil, nil)

      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded["request"], "agents"),
             "Expected 'agents' key to be absent when agents is nil"
    end

    test "empty map agents returns JSON without agents key" do
      hooks_config = %{"PreToolUse" => []}
      {_req_id, json} = Protocol.encode_initialize_request(hooks_config, nil, nil, %{})

      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded["request"], "agents"),
             "Expected 'agents' key to be absent when agents is an empty map"
    end

    test "non-empty agents map includes agents in request_data" do
      hooks_config = %{"PreToolUse" => []}

      agents = %{
        "research-agent" => %{
          "name" => "research-agent",
          "model" => "claude-sonnet-4",
          "instructions" => "You are a research assistant."
        }
      }

      {_req_id, json} = Protocol.encode_initialize_request(hooks_config, nil, nil, agents)

      decoded = Jason.decode!(json)

      assert Map.has_key?(decoded["request"], "agents"),
             "Expected 'agents' key to be present when agents is non-empty"

      assert decoded["request"]["agents"] == agents
    end
  end

  describe "encode_mcp_status_request/1" do
    test "returns valid control_request with subtype mcp_status" do
      {req_id, json} = Protocol.encode_mcp_status_request()

      assert is_binary(req_id)
      assert String.starts_with?(req_id, "req_")

      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request"]["subtype"] == "mcp_status"
      assert decoded["request_id"] == req_id
    end

    test "with custom request_id uses that id" do
      custom_id = "req_custom_mcp_status_42"
      {req_id, json} = Protocol.encode_mcp_status_request(custom_id)

      assert req_id == custom_id

      decoded = Jason.decode!(json)

      assert decoded["request_id"] == custom_id
      assert decoded["request"]["subtype"] == "mcp_status"
    end
  end
end
