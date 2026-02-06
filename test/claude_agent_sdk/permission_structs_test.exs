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
end
