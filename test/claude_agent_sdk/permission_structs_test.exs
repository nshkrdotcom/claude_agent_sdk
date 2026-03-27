defmodule ClaudeAgentSDK.PermissionStructsTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Permission.{RuleValue, Update}

  test "Update enforces :type when building struct directly" do
    assert_raise ArgumentError, fn ->
      struct!(Update, %{})
    end
  end

  test "RuleValue enforces :tool_name when building struct directly" do
    assert_raise ArgumentError, fn ->
      struct!(RuleValue, %{})
    end
  end

  test "constructors still build valid structs" do
    update = Update.add_rules(rules: [RuleValue.new("Bash", "echo *")], behavior: :allow)

    assert %Update{type: :add_rules, behavior: :allow} = update
    assert [%RuleValue{tool_name: "Bash", rule_content: "echo *"}] = update.rules
  end

  test "RuleValue preserves unknown wire fields for forward-compatible projections" do
    assert {:ok, rule} =
             RuleValue.parse(%{
               "toolName" => "Bash",
               "ruleContent" => "echo *",
               "futureFlag" => true
             })

    assert rule.extra == %{"futureFlag" => true}
    assert RuleValue.to_map(rule)["futureFlag"] == true
  end

  test "Update parses raw maps, normalizes wire enums, and preserves unknown fields" do
    assert {:ok, update} =
             Update.parse(%{
               "type" => "addRules",
               "rules" => [%{"toolName" => "Bash", "ruleContent" => "echo *"}],
               "behavior" => "allow",
               "destination" => "session",
               "futureFlag" => "kept"
             })

    assert update.type == :add_rules
    assert update.behavior == :allow
    assert update.destination == :session
    assert [%RuleValue{tool_name: "Bash"}] = update.rules
    assert update.extra == %{"futureFlag" => "kept"}
    assert Update.to_map(update)["futureFlag"] == "kept"
  end
end
