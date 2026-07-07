defmodule ClaudeAgentSDK.HooksPermissions0180Test do
  @moduledoc """
  Section E parity: hook `"defer"` decision, generic updatedToolOutput,
  SessionStart reloadSkills/sessionTitle, MessageDisplay event, `:manual`
  permission mode, and enriched permission context fields.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Hooks
  alias ClaudeAgentSDK.Hooks.Output
  alias ClaudeAgentSDK.Permission
  alias ClaudeAgentSDK.Permission.Context

  describe "hook output helpers" do
    test "defer/1 produces a defer permission decision" do
      out = Output.defer("needs human review")
      assert out.hookSpecificOutput.hookEventName == "PreToolUse"
      assert out.hookSpecificOutput.permissionDecision == "defer"
      assert out.hookSpecificOutput.permissionDecisionReason == "needs human review"
    end

    test "with_updated_tool_output/2 sets updatedToolOutput" do
      out =
        Output.continue()
        |> Output.with_updated_tool_output(%{"content" => "replaced"})

      assert out.hookSpecificOutput.updatedToolOutput == %{"content" => "replaced"}
    end

    test "legacy with_updated_mcp_output still works alongside updatedToolOutput" do
      out =
        Output.continue()
        |> Output.with_updated_tool_output("new")
        |> Output.with_updated_mcp_output("legacy")

      assert out.hookSpecificOutput.updatedToolOutput == "new"
      assert out.hookSpecificOutput.updatedMCPToolOutput == "legacy"
    end

    test "SessionStart reloadSkills and sessionTitle" do
      out =
        Output.add_context("SessionStart", "welcome")
        |> Output.with_reload_skills()
        |> Output.with_session_title("My Session")

      assert out.hookSpecificOutput.reloadSkills == true
      assert out.hookSpecificOutput.sessionTitle == "My Session"
    end

    test "to_json_map serializes defer output" do
      json = Output.defer("x") |> Output.to_json_map()
      assert json["hookSpecificOutput"]["permissionDecision"] == "defer"
    end
  end

  describe "MessageDisplay hook event" do
    test "round-trips" do
      assert Hooks.event_to_string(:message_display) == "MessageDisplay"
      assert Hooks.string_to_event("MessageDisplay") == :message_display
    end
  end

  describe ":manual permission mode" do
    test "is a valid mode and maps to CLI string manual" do
      assert Permission.valid_mode?(:manual)
      assert Permission.mode_to_string(:manual) == "manual"
      assert Permission.string_to_mode("manual") == :manual
      assert :manual in Permission.valid_modes()
    end
  end

  describe "enriched permission context" do
    test "from_control_request surfaces the new fields" do
      request = %{
        "request_id" => "req-42",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{"command" => "ls"},
          "tool_use_id" => "tu_1",
          "agent_id" => "agent_1",
          "blocked_path" => "/etc/passwd",
          "decision_reason" => "policy",
          "title" => "Run a shell command?",
          "display_name" => "Bash",
          "description" => "Runs ls",
          "permission_suggestions" => []
        }
      }

      ctx = Context.from_control_request(request, "sess-1")

      assert ctx.tool_use_id == "tu_1"
      assert ctx.agent_id == "agent_1"
      assert ctx.blocked_path == "/etc/passwd"
      assert ctx.decision_reason == "policy"
      assert ctx.title == "Run a shell command?"
      assert ctx.display_name == "Bash"
      assert ctx.description == "Runs ls"
      assert ctx.request_id == "req-42"
    end
  end
end
