defmodule ClaudeAgentSDK.Parity.HooksNewEventsTest do
  @moduledoc """
  Tests for Phase 2: 6 new hook events.

  Verifies that the 6 new hook event types (:post_tool_use_failure,
  :subagent_start, :notification, :permission_request, :session_start,
  :session_end) are properly supported in event conversion, round-tripping,
  enumeration, and config validation.
  """

  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Hooks

  @new_events [
    {:post_tool_use_failure, "PostToolUseFailure"},
    {:subagent_start, "SubagentStart"},
    {:notification, "Notification"},
    {:permission_request, "PermissionRequest"},
    {:session_start, "SessionStart"},
    {:session_end, "SessionEnd"}
  ]

  describe "event_to_string/1 for new events" do
    for {atom, string} <- @new_events do
      test "converts #{atom} to #{string}" do
        assert Hooks.event_to_string(unquote(atom)) == unquote(string)
      end
    end
  end

  describe "string_to_event/1 round-trips for new events" do
    for {atom, string} <- @new_events do
      test "round-trips #{atom} through string_to_event(event_to_string(#{atom}))" do
        string_form = Hooks.event_to_string(unquote(atom))
        assert string_form == unquote(string)
        assert Hooks.string_to_event(string_form) == unquote(atom)
      end
    end
  end

  describe "all_valid_events/0" do
    test "returns exactly 12 events" do
      events = Hooks.all_valid_events()
      assert length(events) == 12
    end

    test "includes all 6 new events" do
      events = Hooks.all_valid_events()

      for {atom, _string} <- @new_events do
        assert atom in events, "Expected #{atom} to be in all_valid_events()"
      end
    end

    test "includes all 6 original events" do
      events = Hooks.all_valid_events()

      original_events = [
        :pre_tool_use,
        :post_tool_use,
        :user_prompt_submit,
        :stop,
        :subagent_stop,
        :pre_compact
      ]

      for event <- original_events do
        assert event in events, "Expected #{event} to be in all_valid_events()"
      end
    end
  end

  describe "validate_config/1 accepts all 12 event types" do
    test "accepts config with all 12 event types" do
      matcher = %ClaudeAgentSDK.Hooks.Matcher{
        matcher: nil,
        hooks: [fn _, _, _ -> %{} end]
      }

      all_events = Hooks.all_valid_events()
      config = Map.new(all_events, fn event -> {event, [matcher]} end)

      assert Hooks.validate_config(config) == :ok
    end

    for {atom, _string} <- @new_events do
      test "accepts config with #{atom} event individually" do
        matcher = %ClaudeAgentSDK.Hooks.Matcher{
          matcher: nil,
          hooks: [fn _, _, _ -> %{} end]
        }

        config = %{unquote(atom) => [matcher]}
        assert Hooks.validate_config(config) == :ok
      end
    end
  end
end
