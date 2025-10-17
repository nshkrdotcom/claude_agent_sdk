defmodule ClaudeAgentSDK.Hooks.HooksTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Hooks

  describe "event_to_string/1" do
    test "converts pre_tool_use to PreToolUse" do
      assert Hooks.event_to_string(:pre_tool_use) == "PreToolUse"
    end

    test "converts post_tool_use to PostToolUse" do
      assert Hooks.event_to_string(:post_tool_use) == "PostToolUse"
    end

    test "converts user_prompt_submit to UserPromptSubmit" do
      assert Hooks.event_to_string(:user_prompt_submit) == "UserPromptSubmit"
    end

    test "converts stop to Stop" do
      assert Hooks.event_to_string(:stop) == "Stop"
    end

    test "converts subagent_stop to SubagentStop" do
      assert Hooks.event_to_string(:subagent_stop) == "SubagentStop"
    end

    test "converts pre_compact to PreCompact" do
      assert Hooks.event_to_string(:pre_compact) == "PreCompact"
    end
  end

  describe "string_to_event/1" do
    test "converts PreToolUse to pre_tool_use" do
      assert Hooks.string_to_event("PreToolUse") == :pre_tool_use
    end

    test "converts PostToolUse to post_tool_use" do
      assert Hooks.string_to_event("PostToolUse") == :post_tool_use
    end

    test "converts UserPromptSubmit to user_prompt_submit" do
      assert Hooks.string_to_event("UserPromptSubmit") == :user_prompt_submit
    end

    test "converts Stop to stop" do
      assert Hooks.string_to_event("Stop") == :stop
    end

    test "converts SubagentStop to subagent_stop" do
      assert Hooks.string_to_event("SubagentStop") == :subagent_stop
    end

    test "converts PreCompact to pre_compact" do
      assert Hooks.string_to_event("PreCompact") == :pre_compact
    end

    test "returns nil for unknown event" do
      assert Hooks.string_to_event("UnknownEvent") == nil
    end
  end

  describe "validate_config/1" do
    test "validates empty config" do
      assert Hooks.validate_config(%{}) == :ok
    end

    test "validates config with valid event and matchers" do
      matcher = %ClaudeAgentSDK.Hooks.Matcher{
        matcher: "Bash",
        hooks: [fn _, _, _ -> %{} end]
      }

      config = %{pre_tool_use: [matcher]}
      assert Hooks.validate_config(config) == :ok
    end

    test "rejects non-map config" do
      assert {:error, msg} = Hooks.validate_config("not a map")
      assert msg =~ "must be a map"
    end

    test "rejects non-atom event keys" do
      assert {:error, msg} = Hooks.validate_config(%{"string_key" => []})
      assert msg =~ "must be an atom"
    end

    test "rejects invalid event name" do
      assert {:error, msg} = Hooks.validate_config(%{invalid_event: []})
      assert msg =~ "Invalid hook event"
    end

    test "rejects non-list matchers" do
      assert {:error, msg} = Hooks.validate_config(%{pre_tool_use: "not a list"})
      assert msg =~ "must be a list"
    end

    test "rejects invalid matcher struct" do
      assert {:error, msg} = Hooks.validate_config(%{pre_tool_use: [%{}]})
      assert msg =~ "must be a HookMatcher struct"
    end

    test "validates multiple events and matchers" do
      matcher1 = %ClaudeAgentSDK.Hooks.Matcher{
        matcher: "Bash",
        hooks: [fn _, _, _ -> %{} end]
      }

      matcher2 = %ClaudeAgentSDK.Hooks.Matcher{
        matcher: "Write",
        hooks: [fn _, _, _ -> %{} end]
      }

      config = %{
        pre_tool_use: [matcher1],
        post_tool_use: [matcher2]
      }

      assert Hooks.validate_config(config) == :ok
    end
  end

  describe "all_valid_events/0" do
    test "returns list of all valid hook events" do
      events = Hooks.all_valid_events()

      assert :pre_tool_use in events
      assert :post_tool_use in events
      assert :user_prompt_submit in events
      assert :stop in events
      assert :subagent_stop in events
      assert :pre_compact in events
      assert length(events) == 6
    end
  end
end
