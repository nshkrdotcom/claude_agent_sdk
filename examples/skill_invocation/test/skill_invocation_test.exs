defmodule SkillInvocationTest do
  use ExUnit.Case, async: true

  alias SkillInvocation

  describe "skill_tool_definition/0" do
    test "returns valid Skill tool definition" do
      definition = SkillInvocation.skill_tool_definition()

      assert is_map(definition)
      assert definition.name == "Skill"
      assert is_binary(definition.description)
      assert is_map(definition.input_schema)
    end

    test "input schema has required properties" do
      definition = SkillInvocation.skill_tool_definition()
      schema = definition.input_schema

      assert schema["type"] == "object"
      assert is_map(schema["properties"])
      assert Map.has_key?(schema["properties"], "skill")
      assert schema["required"] == ["skill"]
    end
  end

  describe "available_skills/0" do
    test "returns list of available skills" do
      skills = SkillInvocation.available_skills()

      assert is_list(skills)
      refute Enum.empty?(skills)

      # Each skill should have name and description
      Enum.each(skills, fn skill ->
        assert is_map(skill)
        assert Map.has_key?(skill, :name)
        assert Map.has_key?(skill, :description)
        assert is_binary(skill.name)
        assert is_binary(skill.description)
      end)
    end

    test "includes known built-in skills" do
      skills = SkillInvocation.available_skills()
      skill_names = Enum.map(skills, & &1.name)

      # These are documented Claude Code skills
      assert "commit" in skill_names or "pdf" in skill_names or "markitdown" in skill_names
    end
  end

  describe "format_skill_invocation/2" do
    test "formats skill invocation without args" do
      formatted = SkillInvocation.format_skill_invocation("commit", nil)

      assert is_binary(formatted)
      assert String.contains?(formatted, "commit")
    end

    test "formats skill invocation with args" do
      formatted = SkillInvocation.format_skill_invocation("pdf", "document.pdf")

      assert is_binary(formatted)
      assert String.contains?(formatted, "pdf")
      assert String.contains?(formatted, "document.pdf")
    end

    test "handles empty args string" do
      formatted = SkillInvocation.format_skill_invocation("review-pr", "")

      assert is_binary(formatted)
      assert String.contains?(formatted, "review-pr")
    end
  end

  describe "parse_skill_name/1" do
    test "parses simple skill name" do
      assert SkillInvocation.parse_skill_name("commit") == {:ok, "commit"}
    end

    test "parses fully qualified skill name" do
      assert SkillInvocation.parse_skill_name("claude-scientific-writer:pdf") ==
               {:ok, "claude-scientific-writer:pdf"}
    end

    test "rejects empty skill name" do
      assert SkillInvocation.parse_skill_name("") == {:error, :empty_skill_name}
    end

    test "rejects nil skill name" do
      assert SkillInvocation.parse_skill_name(nil) == {:error, :nil_skill_name}
    end
  end
end
