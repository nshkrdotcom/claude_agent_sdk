defmodule ClaudeAgentSDK.ModelTest do
  @moduledoc """
  Tests for core-backed Model validation and normalization.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Model

  # ── validate/1 ──────────────────────────────────────────────────────

  describe "validate/1" do
    test "accepts all configured short-form aliases" do
      for alias_name <- Model.short_forms() do
        assert {:ok, ^alias_name} = Model.validate(alias_name),
               "expected short form #{inspect(alias_name)} to be valid"
      end
    end

    test "accepts all configured full model IDs" do
      for id <- Model.full_ids() do
        assert {:ok, ^id} = Model.validate(id),
               "expected full ID #{inspect(id)} to be valid"
      end
    end

    test "rejects unrecognized model names" do
      assert {:error, :invalid_model} = Model.validate("invalid-model-name")
      assert {:error, :invalid_model} = Model.validate("gpt-5")
    end

    test "rejects nil" do
      assert {:error, :invalid_model} = Model.validate(nil)
    end

    test "rejects empty string" do
      assert {:error, :invalid_model} = Model.validate("")
    end

    test "does not extend the model registry outside the shared core catalog" do
      assert {:error, :invalid_model} = Model.validate("custom-model-1")
    end
  end

  # ── default_model/0 ────────────────────────────────────────────────

  describe "default_model/0" do
    test "returns the shared core default" do
      assert Model.default_model() == "sonnet"
    end

    test "default is a valid model" do
      assert {:ok, _} = Model.validate(Model.default_model())
    end
  end

  # ── short_forms/0 ──────────────────────────────────────────────────

  describe "short_forms/0" do
    test "returns a non-empty list of strings" do
      forms = Model.short_forms()
      assert is_list(forms)
      assert forms != []
      assert Enum.all?(forms, &is_binary/1)
    end

    test "includes the well-known aliases" do
      forms = Model.short_forms()
      assert "opus" in forms
      assert "sonnet" in forms
      assert "haiku" in forms
    end
  end

  # ── full_ids/0 ─────────────────────────────────────────────────────

  describe "full_ids/0" do
    test "returns a non-empty list of strings" do
      ids = Model.full_ids()
      assert is_list(ids)
      assert ids != []
      assert Enum.all?(ids, &is_binary/1)
    end

    test "every full ID contains a version date or version number" do
      for id <- Model.full_ids() do
        assert String.contains?(id, "-"),
               "expected full ID #{inspect(id)} to contain a hyphen"
      end
    end
  end

  # ── list_models/0 ──────────────────────────────────────────────────

  describe "list_models/0" do
    test "returns a sorted list of all known models" do
      models = Model.list_models()
      assert is_list(models)
      assert models != []
      assert models == Enum.sort(models)
    end

    test "includes both short forms and full IDs" do
      models = Model.list_models()

      for alias_name <- Model.short_forms() do
        assert alias_name in models
      end

      for id <- Model.full_ids() do
        assert id in models
      end
    end

    test "ignores models outside the shared core catalog" do
      refute "runtime-added" in Model.list_models()
    end
  end

  # ── suggest/1 ──────────────────────────────────────────────────────

  describe "suggest/1" do
    test "suggests similar short forms" do
      suggestions = Model.suggest("opuss")
      assert is_list(suggestions)
      assert "opus" in suggestions
    end

    test "suggests similar full IDs" do
      suggestions = Model.suggest("sonet")
      assert "sonnet" in suggestions
    end

    test "returns empty list for completely unrelated input" do
      assert Model.suggest("completely-unrelated-xyz123") == []
    end

    test "returns at most 3 suggestions" do
      suggestions = Model.suggest("claude")
      assert length(suggestions) <= 3
    end

    test "returns empty list for non-binary input" do
      assert Model.suggest(nil) == []
      assert Model.suggest(123) == []
    end
  end

  # ── known_models/0 (internal) ─────────────────────────────────────

  describe "known_models/0" do
    test "merges short forms and full IDs into a single map" do
      km = Model.known_models()
      assert is_map(km)

      for alias_name <- Model.short_forms() do
        assert Map.has_key?(km, alias_name)
      end

      for id <- Model.full_ids() do
        assert Map.has_key?(km, id)
      end
    end
  end
end
