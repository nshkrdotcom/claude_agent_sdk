defmodule ClaudeAgentSDK.Config.ModelRegistryTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Model

  describe "model registry" do
    test "contains opus short form" do
      assert "opus" in Model.short_forms()
    end

    test "contains sonnet short form" do
      assert "sonnet" in Model.short_forms()
    end

    test "contains haiku short form" do
      assert "haiku" in Model.short_forms()
    end

    test "contains opus 1M short form" do
      assert "opus[1m]" in Model.short_forms()
    end

    test "contains sonnet 1M short form" do
      assert "sonnet[1m]" in Model.short_forms()
    end

    test "contains correct Sonnet 4.6 full ID" do
      assert "claude-sonnet-4-6" in Model.full_ids()
    end

    test "exposes current pinned IDs" do
      for id <- ~w(claude-opus-5-5 claude-sonnet-5-5 claude-haiku-5-5 claude-fable-5-2) do
        assert id in Model.full_ids()
      end
    end

    test "does not invent a bracketed Opus 5 provider id" do
      refute "claude-opus-5[1m]" in Model.full_ids()
      refute Enum.any?(Model.full_ids(), &String.starts_with?(&1, "claude-opus-5["))
      refute "claude-opus-5[1m]" in Model.list_models()
    end

    test "contains correct Opus 4.7 full ID" do
      assert "claude-opus-4-7" in Model.full_ids()
    end

    test "contains correct Opus 4.7 1M full ID" do
      assert "claude-opus-4-7[1m]" in Model.full_ids()
    end

    test "contains correct Sonnet 4.6 1M full ID" do
      assert "claude-sonnet-4-6[1m]" in Model.full_ids()
    end

    test "contains correct Haiku 4.5 full ID" do
      assert "claude-haiku-4-5-20251001" in Model.full_ids()
      assert "claude-haiku-4-5" in Model.full_ids()
    end

    test "does not expose stale Opus 4.6 IDs as current aliases" do
      refute "claude-opus-4-6" in Model.full_ids()
      refute "claude-opus-4-6[1m]" in Model.full_ids()
    end

    test "does not expose private catalog entries in public helper lists" do
      refute "legacy-sonnet" in Model.short_forms()
      refute "claude-3-7-sonnet-legacy" in Model.full_ids()
    end

    test "default model matches the shared core default" do
      assert Model.default_model() == "sonnet"
    end
  end
end
