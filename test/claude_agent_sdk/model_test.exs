defmodule ClaudeAgentSDK.ModelTest do
  @moduledoc """
  Tests for Model validation and normalization.

  Following TDD approach - these tests are written before implementation
  and should initially fail (RED phase).
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Model

  describe "validate/1" do
    test "should_return_short_form_when_given_short_form_opus" do
      assert {:ok, "opus"} = Model.validate("opus")
    end

    test "should_return_short_form_when_given_short_form_sonnet" do
      assert {:ok, "sonnet"} = Model.validate("sonnet")
    end

    test "should_return_short_form_when_given_short_form_haiku" do
      assert {:ok, "haiku"} = Model.validate("haiku")
    end

    test "should_return_same_name_when_given_full_form" do
      assert {:ok, "claude-opus-4-1-20250805"} = Model.validate("claude-opus-4-1-20250805")
      assert {:ok, "claude-sonnet-4-5-20250929"} = Model.validate("claude-sonnet-4-5-20250929")
      assert {:ok, "claude-haiku-4-5-20251001"} = Model.validate("claude-haiku-4-5-20251001")
    end

    test "should_return_error_when_given_invalid_model" do
      assert {:error, :invalid_model} = Model.validate("invalid-model-name")
    end

    test "should_return_error_when_given_nil" do
      assert {:error, :invalid_model} = Model.validate(nil)
    end

    test "should_return_error_when_given_empty_string" do
      assert {:error, :invalid_model} = Model.validate("")
    end
  end

  describe "list_models/0" do
    test "should_return_list_of_all_known_models" do
      models = Model.list_models()
      assert is_list(models)
      assert length(models) > 0
    end

    test "should_include_both_short_and_full_forms" do
      models = Model.list_models()

      # Should include short forms
      assert "opus" in models
      assert "sonnet" in models
      assert "haiku" in models

      # Should include full forms
      assert "claude-opus-4-1-20250805" in models
      assert "claude-sonnet-4-5-20250929" in models
      assert "claude-haiku-4-5-20251001" in models
    end

    test "should_return_sorted_list" do
      models = Model.list_models()
      assert models == Enum.sort(models)
    end
  end

  describe "suggest/1" do
    test "should_suggest_opus_when_given_opuss" do
      suggestions = Model.suggest("opuss")
      assert is_list(suggestions)
      assert "opus" in suggestions or "claude-opus-4-1-20250805" in suggestions
    end

    test "should_suggest_sonnet_when_given_sonet" do
      suggestions = Model.suggest("sonet")
      assert is_list(suggestions)
      assert "sonnet" in suggestions or "claude-sonnet-4-5-20250929" in suggestions
    end

    test "should_return_empty_when_no_similar_models" do
      suggestions = Model.suggest("completely-unrelated-xyz123")
      assert suggestions == []
    end

    test "should_return_top_3_suggestions_maximum" do
      suggestions = Model.suggest("claude")
      assert is_list(suggestions)
      assert length(suggestions) <= 3
    end

    test "should_return_empty_when_given_non_binary" do
      assert Model.suggest(nil) == []
      assert Model.suggest(123) == []
    end
  end
end
