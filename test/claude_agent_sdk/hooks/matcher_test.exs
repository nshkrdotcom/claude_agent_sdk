defmodule ClaudeAgentSDK.Hooks.MatcherTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Hooks.Matcher

  describe "new/2" do
    test "creates matcher with specific tool" do
      callback = fn _, _, _ -> %{} end
      matcher = Matcher.new("Bash", [callback])

      assert matcher.matcher == "Bash"
      assert matcher.hooks == [callback]
    end

    test "creates matcher with regex pattern" do
      callback = fn _, _, _ -> %{} end
      matcher = Matcher.new("Write|Edit", [callback])

      assert matcher.matcher == "Write|Edit"
      assert matcher.hooks == [callback]
    end

    test "creates matcher for all tools" do
      callback = fn _, _, _ -> %{} end
      matcher = Matcher.new("*", [callback])

      assert matcher.matcher == "*"
    end

    test "creates matcher with nil (matches all)" do
      callback = fn _, _, _ -> %{} end
      matcher = Matcher.new(nil, [callback])

      assert matcher.matcher == nil
    end

    test "creates matcher with multiple hooks" do
      callback1 = fn _, _, _ -> %{} end
      callback2 = fn _, _, _ -> %{} end
      matcher = Matcher.new("Bash", [callback1, callback2])

      assert length(matcher.hooks) == 2
    end

    test "creates matcher with empty hooks list" do
      matcher = Matcher.new("Bash", [])

      assert matcher.hooks == []
    end
  end

  describe "to_cli_format/2" do
    test "converts matcher to CLI format with single hook" do
      callback = fn _, _, _ -> %{} end
      matcher = Matcher.new("Bash", [callback])

      id_fn = fn ^callback -> "hook_0" end
      result = Matcher.to_cli_format(matcher, id_fn)

      assert result == %{
               "matcher" => "Bash",
               "hookCallbackIds" => ["hook_0"]
             }
    end

    test "converts matcher to CLI format with multiple hooks" do
      callback1 = fn _, _, _ -> %{} end
      callback2 = fn _, _, _ -> %{} end
      matcher = Matcher.new("Write", [callback1, callback2])

      id_fn = fn
        ^callback1 -> "hook_0"
        ^callback2 -> "hook_1"
      end

      result = Matcher.to_cli_format(matcher, id_fn)

      assert result == %{
               "matcher" => "Write",
               "hookCallbackIds" => ["hook_0", "hook_1"]
             }
    end

    test "converts matcher with nil matcher" do
      callback = fn _, _, _ -> %{} end
      matcher = Matcher.new(nil, [callback])

      id_fn = fn ^callback -> "hook_0" end
      result = Matcher.to_cli_format(matcher, id_fn)

      assert result == %{
               "matcher" => nil,
               "hookCallbackIds" => ["hook_0"]
             }
    end

    test "preserves matcher pattern string" do
      callback = fn _, _, _ -> %{} end
      matcher = Matcher.new("Edit|MultiEdit|Write", [callback])

      id_fn = fn ^callback -> "hook_0" end
      result = Matcher.to_cli_format(matcher, id_fn)

      assert result["matcher"] == "Edit|MultiEdit|Write"
    end
  end
end
