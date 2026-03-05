defmodule ClaudeAgentSDK.Config.ModelRegistryTest do
  use ClaudeAgentSDK.SupertesterCase

  describe "model registry" do
    test "contains opus short form" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert models.short_forms["opus"] == "opus"
    end

    test "contains sonnet short form" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert models.short_forms["sonnet"] == "sonnet"
    end

    test "contains haiku short form" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert models.short_forms["haiku"] == "haiku"
    end

    test "contains opus 1M short form" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert models.short_forms["opus[1m]"] == "opus[1m]"
    end

    test "contains sonnet 1M short form" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert models.short_forms["sonnet[1m]"] == "sonnet[1m]"
    end

    test "contains correct Sonnet 4.6 full ID" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert Map.has_key?(models.full_ids, "claude-sonnet-4-6")
    end

    test "contains correct Opus 4.6 full ID" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert Map.has_key?(models.full_ids, "claude-opus-4-6")
    end

    test "contains correct Haiku 4.5 full ID" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert Map.has_key?(models.full_ids, "claude-haiku-4-5-20251001")
    end

    test "default model is sonnet" do
      models = Application.get_env(:claude_agent_sdk, :models)
      assert models.default == "sonnet"
    end
  end
end
