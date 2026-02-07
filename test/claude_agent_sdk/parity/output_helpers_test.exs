defmodule ClaudeAgentSDK.Parity.OutputHelpersTest do
  @moduledoc """
  Tests for Phase 3: new output helpers.

  Verifies the composable output helpers: `with_additional_context/2`,
  `with_updated_mcp_output/2`, `permission_decision/1`, `permission_allow/0`,
  and `permission_deny/1`.
  """

  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Hooks.Output
  alias ClaudeAgentSDK.Permission.Result

  describe "with_additional_context/2" do
    test "adds additionalContext to hookSpecificOutput" do
      output =
        %{}
        |> Output.with_additional_context("Extra context for Claude")

      assert output.hookSpecificOutput.additionalContext == "Extra context for Claude"
    end

    test "composes with existing hookSpecificOutput" do
      output =
        Output.allow("Approved")
        |> Output.with_additional_context("Command took 2.3s")

      # The original allow fields should still be present
      assert output.hookSpecificOutput.permissionDecision == "allow"
      assert output.hookSpecificOutput.permissionDecisionReason == "Approved"
      # And the new context should be added
      assert output.hookSpecificOutput.additionalContext == "Command took 2.3s"
    end
  end

  describe "with_updated_mcp_output/2" do
    test "adds updatedMCPToolOutput to hookSpecificOutput" do
      mcp_output = %{"content" => [%{"type" => "text", "text" => "filtered response"}]}

      output =
        Output.continue()
        |> Output.with_updated_mcp_output(mcp_output)

      assert output.hookSpecificOutput.updatedMCPToolOutput == mcp_output
    end

    test "composes with existing hookSpecificOutput" do
      mcp_output = %{"content" => [%{"type" => "text", "text" => "modified"}]}

      output =
        Output.allow("Approved")
        |> Output.with_updated_mcp_output(mcp_output)

      assert output.hookSpecificOutput.permissionDecision == "allow"
      assert output.hookSpecificOutput.updatedMCPToolOutput == mcp_output
    end
  end

  describe "permission_decision/1" do
    test "creates PermissionRequest output with allow result" do
      result = Result.allow()
      output = Output.permission_decision(result)

      assert output.hookSpecificOutput.hookEventName == "PermissionRequest"
      assert output.hookSpecificOutput.decision == %{"type" => "allow"}
    end

    test "creates PermissionRequest output with deny result" do
      result = Result.deny("Not allowed in this context")
      output = Output.permission_decision(result)

      assert output.hookSpecificOutput.hookEventName == "PermissionRequest"

      assert output.hookSpecificOutput.decision == %{
               "type" => "deny",
               "reason" => "Not allowed in this context"
             }
    end
  end

  describe "permission_allow/0" do
    test "creates allow permission decision" do
      output = Output.permission_allow()

      assert output.hookSpecificOutput.hookEventName == "PermissionRequest"
      assert output.hookSpecificOutput.decision == %{"type" => "allow"}
    end
  end

  describe "permission_deny/1" do
    test "creates deny permission decision with reason" do
      output = Output.permission_deny("Tool not permitted in this context")

      assert output.hookSpecificOutput.hookEventName == "PermissionRequest"

      assert output.hookSpecificOutput.decision == %{
               "type" => "deny",
               "reason" => "Tool not permitted in this context"
             }
    end
  end

  describe "wire-format parity (to_json_map/1)" do
    test "PostToolUse updatedMCPToolOutput key matches Python SDK" do
      mcp_output = %{"content" => [%{"type" => "text", "text" => "filtered"}]}

      json =
        Output.continue()
        |> Output.with_updated_mcp_output(mcp_output)
        |> Output.to_json_map()

      assert json["hookSpecificOutput"]["updatedMCPToolOutput"] == mcp_output
      refute Map.has_key?(json["hookSpecificOutput"], "updatedMcpOutput")
    end

    test "PermissionRequest uses 'decision' key, not 'permissionDecision'" do
      json =
        Output.permission_allow()
        |> Output.to_json_map()

      assert json["hookSpecificOutput"]["hookEventName"] == "PermissionRequest"
      assert Map.has_key?(json["hookSpecificOutput"], "decision")
      refute Map.has_key?(json["hookSpecificOutput"], "permissionDecision")
    end

    test "PermissionRequest allow produces {type: allow} payload" do
      json =
        Output.permission_allow()
        |> Output.to_json_map()

      assert json["hookSpecificOutput"]["decision"] == %{"type" => "allow"}
    end

    test "PermissionRequest deny produces {type: deny, reason: ...} payload" do
      json =
        Output.permission_deny("Not permitted")
        |> Output.to_json_map()

      assert json["hookSpecificOutput"]["decision"] == %{
               "type" => "deny",
               "reason" => "Not permitted"
             }
    end

    test "PreToolUse permissionDecision key is unchanged" do
      json =
        Output.allow("Approved")
        |> Output.to_json_map()

      assert json["hookSpecificOutput"]["permissionDecision"] == "allow"
      assert json["hookSpecificOutput"]["permissionDecisionReason"] == "Approved"
    end

    test "with_updated_mcp_output accepts non-map values" do
      output =
        Output.continue()
        |> Output.with_updated_mcp_output("plain string result")

      assert output.hookSpecificOutput.updatedMCPToolOutput == "plain string result"

      json = Output.to_json_map(output)
      assert json["hookSpecificOutput"]["updatedMCPToolOutput"] == "plain string result"
    end

    test "permission_decision accepts raw map passthrough" do
      raw_decision = %{"type" => "allow", "custom_field" => "value"}
      output = Output.permission_decision(raw_decision)

      json = Output.to_json_map(output)
      assert json["hookSpecificOutput"]["decision"] == raw_decision
    end
  end
end
