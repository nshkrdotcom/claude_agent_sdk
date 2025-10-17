defmodule ClaudeAgentSDK.Hooks.OutputTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Hooks.Output

  describe "allow/1" do
    test "creates output to allow PreToolUse with default reason" do
      output = Output.allow()

      assert output == %{
               hookSpecificOutput: %{
                 hookEventName: "PreToolUse",
                 permissionDecision: "allow",
                 permissionDecisionReason: "Approved"
               }
             }
    end

    test "creates output to allow PreToolUse with custom reason" do
      output = Output.allow("Security check passed")

      assert output.hookSpecificOutput.permissionDecisionReason == "Security check passed"
    end
  end

  describe "deny/1" do
    test "creates output to deny PreToolUse" do
      output = Output.deny("Command blocked")

      assert output == %{
               hookSpecificOutput: %{
                 hookEventName: "PreToolUse",
                 permissionDecision: "deny",
                 permissionDecisionReason: "Command blocked"
               }
             }
    end

    test "requires reason" do
      output = Output.deny("Security violation")
      assert output.hookSpecificOutput.permissionDecisionReason == "Security violation"
    end
  end

  describe "ask/1" do
    test "creates output to ask user for permission" do
      output = Output.ask("Confirm this action")

      assert output == %{
               hookSpecificOutput: %{
                 hookEventName: "PreToolUse",
                 permissionDecision: "ask",
                 permissionDecisionReason: "Confirm this action"
               }
             }
    end
  end

  describe "add_context/2" do
    test "creates output to add context for PostToolUse" do
      output = Output.add_context("PostToolUse", "Command completed successfully")

      assert output == %{
               hookSpecificOutput: %{
                 hookEventName: "PostToolUse",
                 additionalContext: "Command completed successfully"
               }
             }
    end

    test "creates output to add context for UserPromptSubmit" do
      output = Output.add_context("UserPromptSubmit", "Current time: 10:00 AM")

      assert output.hookSpecificOutput.hookEventName == "UserPromptSubmit"
      assert output.hookSpecificOutput.additionalContext == "Current time: 10:00 AM"
    end
  end

  describe "stop/1" do
    test "creates output to stop execution" do
      output = Output.stop("Critical error detected")

      assert output == %{
               continue: false,
               stopReason: "Critical error detected"
             }
    end
  end

  describe "block/1" do
    test "creates output to block with decision field" do
      output = Output.block("Tool execution failed")

      assert output == %{
               decision: "block",
               reason: "Tool execution failed"
             }
    end
  end

  describe "continue/0" do
    test "creates output to continue execution" do
      output = Output.continue()

      assert output == %{continue: true}
    end
  end

  describe "with_system_message/2" do
    test "adds system message to output" do
      output =
        %{test: "value"}
        |> Output.with_system_message("Warning: high resource usage")

      assert output.systemMessage == "Warning: high resource usage"
      assert output.test == "value"
    end

    test "works with empty output" do
      output = Output.with_system_message(%{}, "Info message")

      assert output == %{systemMessage: "Info message"}
    end
  end

  describe "with_reason/2" do
    test "adds reason to output" do
      output =
        %{test: "value"}
        |> Output.with_reason("Tool validation failed")

      assert output.reason == "Tool validation failed"
      assert output.test == "value"
    end
  end

  describe "suppress_output/1" do
    test "adds suppressOutput flag to output" do
      output =
        %{test: "value"}
        |> Output.suppress_output()

      assert output.suppressOutput == true
      assert output.test == "value"
    end
  end

  describe "validate/1" do
    test "validates valid output map" do
      output = %{continue: true}
      assert Output.validate(output) == :ok
    end

    test "validates output with hook specific output" do
      output = %{
        hookSpecificOutput: %{
          hookEventName: "PreToolUse",
          permissionDecision: "allow"
        }
      }

      assert Output.validate(output) == :ok
    end

    test "rejects non-map output" do
      assert {:error, msg} = Output.validate("not a map")
      assert msg =~ "must be a map"
    end

    test "validates empty map" do
      assert Output.validate(%{}) == :ok
    end
  end

  describe "to_json_map/1" do
    test "converts atom keys to strings" do
      output = %{
        continue: false,
        stopReason: "Error occurred"
      }

      result = Output.to_json_map(output)

      assert result == %{
               "continue" => false,
               "stopReason" => "Error occurred"
             }
    end

    test "converts hookSpecificOutput" do
      output = %{
        hookSpecificOutput: %{
          hookEventName: "PreToolUse",
          permissionDecision: "deny"
        }
      }

      result = Output.to_json_map(output)

      assert result["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
      assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
    end

    test "preserves string keys" do
      output = %{
        "already_string" => "value",
        atom_key: "value2"
      }

      result = Output.to_json_map(output)

      assert result["already_string"] == "value"
      assert result["atom_key"] == "value2"
    end

    test "handles nested maps" do
      output = %{
        nested: %{
          inner_atom: "value"
        }
      }

      result = Output.to_json_map(output)

      assert result["nested"]["inner_atom"] == "value"
    end
  end

  describe "helper combinations" do
    test "can combine allow with system message" do
      output =
        Output.allow("Security approved")
        |> Output.with_system_message("Auto-approved by policy")

      assert output.hookSpecificOutput.permissionDecision == "allow"
      assert output.systemMessage == "Auto-approved by policy"
    end

    test "can combine deny with reason and system message" do
      output =
        Output.deny("Invalid command")
        |> Output.with_reason("Command failed validation")
        |> Output.with_system_message("Blocked by security policy")

      assert output.hookSpecificOutput.permissionDecision == "deny"
      assert output.reason == "Command failed validation"
      assert output.systemMessage == "Blocked by security policy"
    end

    test "can combine stop with reason" do
      output =
        Output.stop("Critical failure")
        |> Output.with_reason("System check failed")

      assert output.continue == false
      assert output.stopReason == "Critical failure"
      assert output.reason == "System check failed"
    end
  end
end
