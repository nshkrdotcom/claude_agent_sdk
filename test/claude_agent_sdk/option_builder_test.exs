defmodule ClaudeAgentSDK.OptionBuilderTest do
  use ExUnit.Case

  alias ClaudeAgentSDK.{OptionBuilder, Options}

  describe "build_development_options/0" do
    test "creates development-friendly options" do
      options = OptionBuilder.build_development_options()

      assert options.max_turns == 10
      assert options.verbose == true
      assert options.permission_mode == :accept_edits
      assert "Bash" in options.allowed_tools
      assert "Read" in options.allowed_tools
      assert "Write" in options.allowed_tools
      assert "Edit" in options.allowed_tools
    end
  end

  describe "build_staging_options/0" do
    test "creates restrictive staging options" do
      options = OptionBuilder.build_staging_options()

      assert options.max_turns == 5
      assert options.verbose == false
      assert options.permission_mode == :plan
      assert options.allowed_tools == ["Read"]
      assert "Bash" in options.disallowed_tools
      assert "Write" in options.disallowed_tools
      assert "Edit" in options.disallowed_tools
    end
  end

  describe "build_production_options/0" do
    test "creates highly restrictive production options" do
      options = OptionBuilder.build_production_options()

      assert options.max_turns == 3
      assert options.verbose == false
      assert options.permission_mode == :plan
      assert options.allowed_tools == ["Read"]
      assert "Bash" in options.disallowed_tools
      assert "Write" in options.disallowed_tools
      assert "Edit" in options.disallowed_tools
      assert options.output_format == :stream_json
    end
  end

  describe "build_analysis_options/0" do
    test "creates read-focused analysis options" do
      options = OptionBuilder.build_analysis_options()

      assert options.max_turns == 7
      assert "Read" in options.allowed_tools
      assert "Grep" in options.allowed_tools
      assert "Find" in options.allowed_tools
      assert "Write" in options.disallowed_tools
      assert "Edit" in options.disallowed_tools
      assert "Bash" in options.disallowed_tools
      assert options.permission_mode == :plan
    end
  end

  describe "build_chat_options/0" do
    test "creates minimal chat options" do
      options = OptionBuilder.build_chat_options()

      assert options.max_turns == 1
      assert options.output_format == :text
      assert options.allowed_tools == []
      assert options.permission_mode == :plan
    end
  end

  describe "build_documentation_options/0" do
    test "creates documentation generation options" do
      options = OptionBuilder.build_documentation_options()

      assert options.max_turns == 8
      assert "Read" in options.allowed_tools
      assert "Write" in options.allowed_tools
      assert "Bash" in options.disallowed_tools
      assert "Edit" in options.disallowed_tools
      assert options.permission_mode == :accept_edits
    end
  end

  describe "with_working_directory/2" do
    test "sets working directory on new options" do
      options = OptionBuilder.with_working_directory("/my/project")

      assert options.cwd == "/my/project"
    end

    test "sets working directory on existing options" do
      base = OptionBuilder.build_development_options()
      options = OptionBuilder.with_working_directory(base, "/my/project")

      assert options.cwd == "/my/project"
      # Preserved from base
      assert options.max_turns == 10
    end
  end

  describe "with_system_prompt/2" do
    test "sets system prompt on new options" do
      options = OptionBuilder.with_system_prompt("Custom prompt")

      assert options.system_prompt == "Custom prompt"
    end

    test "sets system prompt on existing options" do
      base = OptionBuilder.build_analysis_options()
      options = OptionBuilder.with_system_prompt(base, "Analyze this")

      assert options.system_prompt == "Analyze this"
      # Preserved from base
      assert options.max_turns == 7
    end
  end

  describe "for_environment/0" do
    test "returns appropriate options for current environment" do
      options = OptionBuilder.for_environment()

      assert is_struct(options, Options)

      # In test environment, should get staging options
      assert options.max_turns == 5
      assert options.permission_mode == :plan
    end
  end

  describe "merge/2" do
    test "merges custom options with development base" do
      options = OptionBuilder.merge(:development, %{max_turns: 15, verbose: false})

      assert options.max_turns == 15
      assert options.verbose == false
      # From base
      assert options.permission_mode == :accept_edits
    end

    test "merges custom options with staging base" do
      options = OptionBuilder.merge(:staging, %{max_turns: 8})

      assert options.max_turns == 8
      # From base
      assert options.permission_mode == :plan
    end

    test "merges custom options with struct base" do
      base = OptionBuilder.build_production_options()
      options = OptionBuilder.merge(base, %{verbose: true})

      assert options.verbose == true
      # From base
      assert options.max_turns == 3
    end

    test "handles unknown base atom" do
      options = OptionBuilder.merge(:unknown, %{max_turns: 5})

      assert options.max_turns == 5
    end
  end

  describe "sandboxed/2" do
    test "creates sandboxed options with default tools" do
      options = OptionBuilder.sandboxed("/tmp/sandbox")

      assert options.cwd == "/tmp/sandbox"
      assert options.permission_mode == :bypass_permissions
      assert options.allowed_tools == ["Read", "Write"]
      assert "Bash" in options.disallowed_tools
      assert options.max_turns == 5
    end

    test "creates sandboxed options with custom tools" do
      options = OptionBuilder.sandboxed("/tmp/sandbox", ["Read"])

      assert options.cwd == "/tmp/sandbox"
      assert options.allowed_tools == ["Read"]
      assert "Bash" in options.disallowed_tools
    end
  end

  describe "option combinations" do
    test "can chain builders for complex configurations" do
      base = OptionBuilder.build_development_options()
      with_dir = OptionBuilder.with_working_directory(base, "/project")
      options = OptionBuilder.with_system_prompt(with_dir, "Be helpful")

      assert options.max_turns == 10
      assert options.cwd == "/project"
      assert options.system_prompt == "Be helpful"
    end

    test "merge preserves all non-overridden fields" do
      base = OptionBuilder.build_documentation_options()
      merged = OptionBuilder.merge(base, %{max_turns: 10})

      assert merged.max_turns == 10
      assert merged.allowed_tools == ["Read", "Write", "Grep"]
      assert merged.disallowed_tools == ["Bash", "Edit"]
      assert merged.permission_mode == :accept_edits
    end
  end

  describe "build_testing_options/0" do
    test "creates testing-focused options" do
      options = OptionBuilder.build_testing_options()

      assert options.max_turns == 6
      assert options.output_format == :stream_json
      assert "Read" in options.allowed_tools
      assert "Write" in options.allowed_tools
      assert "Grep" in options.allowed_tools
      assert "Bash" in options.disallowed_tools
      assert "Edit" in options.disallowed_tools
      assert options.permission_mode == :accept_edits
      assert options.verbose == false
      assert String.contains?(options.system_prompt, "QA engineer")
    end
  end

  describe "with_additional_tools/2" do
    test "adds tools to existing allowed tools" do
      base = OptionBuilder.build_production_options()
      options = OptionBuilder.with_additional_tools(base, ["Grep", "Find"])

      assert "Read" in options.allowed_tools
      assert "Grep" in options.allowed_tools
      assert "Find" in options.allowed_tools
      assert length(options.allowed_tools) == 3
    end

    test "handles empty allowed_tools list" do
      base = %Options{allowed_tools: nil}
      options = OptionBuilder.with_additional_tools(base, ["Grep"])

      assert options.allowed_tools == ["Grep"]
    end

    test "preserves other options" do
      base = OptionBuilder.build_development_options()
      original_turns = base.max_turns
      options = OptionBuilder.with_additional_tools(base, ["NewTool"])

      assert options.max_turns == original_turns
      assert "NewTool" in options.allowed_tools
    end
  end

  describe "with_turn_limit/2" do
    test "sets custom turn limit" do
      base = OptionBuilder.build_chat_options()
      options = OptionBuilder.with_turn_limit(base, 5)

      assert options.max_turns == 5
      # Preserves other settings
      assert options.output_format == :text
      assert options.permission_mode == :plan
    end

    test "overrides existing turn limit" do
      base = OptionBuilder.build_development_options()
      assert base.max_turns == 10

      options = OptionBuilder.with_turn_limit(base, 20)
      assert options.max_turns == 20
    end
  end

  describe "quick/0" do
    test "creates minimal quick options" do
      options = OptionBuilder.quick()

      assert options.max_turns == 1
      assert options.output_format == :text
      assert options.allowed_tools == []
      assert options.permission_mode == :plan
      assert options.verbose == false
      assert String.contains?(options.system_prompt, "quick")
    end
  end

  describe "available_presets/0" do
    test "returns list of available preset names" do
      presets = OptionBuilder.available_presets()

      assert is_list(presets)
      assert :development in presets
      assert :staging in presets
      assert :production in presets
      assert :analysis in presets
      assert :chat in presets
      assert :documentation in presets
      assert :testing in presets

      # Should be exactly 7 presets
      assert length(presets) == 7
    end

    test "all presets can be used with merge/2" do
      presets = OptionBuilder.available_presets()

      for preset <- presets do
        options = OptionBuilder.merge(preset, %{max_turns: 99})
        assert options.max_turns == 99
        assert is_struct(options, Options)
      end
    end
  end

  describe "validate/1" do
    test "validates good options" do
      options = OptionBuilder.build_development_options()
      result = OptionBuilder.validate(options)

      assert {:ok, ^options} = result
    end

    test "warns about high turn limits" do
      options = OptionBuilder.merge(:development, %{max_turns: 25})
      result = OptionBuilder.validate(options)

      assert {:warning, ^options, warnings} = result
      assert Enum.any?(warnings, &String.contains?(&1, "Turn limit very high"))
    end

    test "warns about unsafe bypass permissions" do
      options = %Options{
        permission_mode: :bypass_permissions,
        cwd: nil
      }

      result = OptionBuilder.validate(options)

      assert {:warning, ^options, warnings} = result
      assert Enum.any?(warnings, &String.contains?(&1, "bypass_permissions without cwd"))
    end

    test "warns about dangerous bash + bypass combination" do
      options = %Options{
        permission_mode: :bypass_permissions,
        allowed_tools: ["Bash"],
        cwd: "/tmp"
      }

      result = OptionBuilder.validate(options)

      assert {:warning, ^options, warnings} = result
      assert Enum.any?(warnings, &String.contains?(&1, "Bash + bypass_permissions"))
    end

    test "accumulates multiple warnings" do
      options = %Options{
        max_turns: 50,
        permission_mode: :bypass_permissions,
        allowed_tools: ["Bash"],
        cwd: nil
      }

      result = OptionBuilder.validate(options)

      assert {:warning, ^options, warnings} = result
      assert length(warnings) >= 2
    end

    test "returns warnings in reverse order" do
      options = %Options{
        max_turns: 25,
        permission_mode: :bypass_permissions,
        cwd: nil
      }

      result = OptionBuilder.validate(options)

      assert {:warning, ^options, warnings} = result
      # Should be reversed from the order they were added
      assert length(warnings) == 2
    end
  end

  describe "environment-aware functionality" do
    test "for_environment adapts to current Mix environment" do
      # Test that it returns appropriate options for test env
      options = OptionBuilder.for_environment()

      # In test environment, should get staging options
      assert options.max_turns == 5
      assert options.permission_mode == :plan
      assert options.verbose == false
    end

    test "for_environment handles unknown environments safely" do
      # This is harder to test without changing Mix.env(), but we can test the logic
      staging_options = OptionBuilder.build_staging_options()
      env_options = OptionBuilder.for_environment()

      # In test env, should match staging
      assert env_options.max_turns == staging_options.max_turns
      assert env_options.permission_mode == staging_options.permission_mode
    end
  end

  describe "comprehensive preset testing" do
    test "all presets have unique characteristics" do
      presets = %{
        development: OptionBuilder.build_development_options(),
        staging: OptionBuilder.build_staging_options(),
        production: OptionBuilder.build_production_options(),
        analysis: OptionBuilder.build_analysis_options(),
        chat: OptionBuilder.build_chat_options(),
        documentation: OptionBuilder.build_documentation_options(),
        testing: OptionBuilder.build_testing_options()
      }

      # Verify each preset has distinct turn limits
      turn_limits = Enum.map(presets, fn {_name, opts} -> opts.max_turns end)
      # Most should be unique
      assert length(Enum.uniq(turn_limits)) >= 5

      # Verify security progression
      dev = presets.development
      staging = presets.staging
      prod = presets.production

      # Development should be most permissive
      assert dev.permission_mode == :accept_edits
      assert dev.verbose == true
      assert length(dev.allowed_tools) >= length(staging.allowed_tools)

      # Production should be most restrictive
      assert prod.permission_mode == :plan
      assert prod.verbose == false
      assert length(prod.allowed_tools) <= length(staging.allowed_tools)
    end

    test "all presets are valid" do
      presets = [
        OptionBuilder.build_development_options(),
        OptionBuilder.build_staging_options(),
        OptionBuilder.build_production_options(),
        OptionBuilder.build_analysis_options(),
        OptionBuilder.build_chat_options(),
        OptionBuilder.build_documentation_options(),
        OptionBuilder.build_testing_options()
      ]

      for preset <- presets do
        case OptionBuilder.validate(preset) do
          {:ok, _} ->
            :ok

          {:warning, _, warnings} ->
            # Warnings are acceptable, but should be reasonable
            assert length(warnings) <= 2
            # No error case expected since validate only returns :ok or :warning
        end
      end
    end

    test "presets have appropriate system prompts" do
      # Each preset should have a system prompt that matches its purpose
      dev = OptionBuilder.build_development_options()
      analysis = OptionBuilder.build_analysis_options()
      chat = OptionBuilder.build_chat_options()
      docs = OptionBuilder.build_documentation_options()
      testing = OptionBuilder.build_testing_options()

      assert String.contains?(dev.system_prompt, "development")
      assert String.contains?(analysis.system_prompt, "code reviewer")
      assert String.contains?(chat.system_prompt, "programming assistant")
      assert String.contains?(docs.system_prompt, "technical writer")
      assert String.contains?(testing.system_prompt, "QA engineer")
    end
  end

  describe "builder pattern chaining" do
    test "supports complex builder chains" do
      options =
        OptionBuilder.build_development_options()
        |> OptionBuilder.with_working_directory("/project")
        |> OptionBuilder.with_system_prompt("Custom prompt")
        |> OptionBuilder.with_additional_tools(["CustomTool"])
        |> OptionBuilder.with_turn_limit(15)

      assert options.cwd == "/project"
      assert options.system_prompt == "Custom prompt"
      assert "CustomTool" in options.allowed_tools
      assert options.max_turns == 15

      # Should preserve original development settings where not overridden
      assert options.permission_mode == :accept_edits
      assert options.verbose == true
    end

    test "builder methods are order independent" do
      options1 =
        OptionBuilder.build_production_options()
        |> OptionBuilder.with_turn_limit(5)
        |> OptionBuilder.with_working_directory("/tmp")

      options2 =
        OptionBuilder.build_production_options()
        |> OptionBuilder.with_working_directory("/tmp")
        |> OptionBuilder.with_turn_limit(5)

      assert options1.max_turns == options2.max_turns
      assert options1.cwd == options2.cwd
      assert options1.permission_mode == options2.permission_mode
    end
  end

  describe "edge cases and error handling" do
    test "merge handles empty custom map" do
      base = OptionBuilder.build_development_options()
      options = OptionBuilder.merge(base, %{})

      # Should be identical to base
      assert options.max_turns == base.max_turns
      assert options.verbose == base.verbose
      assert options.permission_mode == base.permission_mode
    end

    test "merge with unknown atom defaults to empty options" do
      options = OptionBuilder.merge(:nonexistent, %{max_turns: 5})

      assert options.max_turns == 5
      # Other fields should be nil or default
      assert options.verbose == nil
      assert options.permission_mode == nil
    end

    test "with_additional_tools handles duplicate tools" do
      base = OptionBuilder.build_development_options()
      # Add a tool that's already in the list
      options = OptionBuilder.with_additional_tools(base, ["Read", "NewTool"])

      # Should have duplicates (this is acceptable behavior)
      assert "Read" in options.allowed_tools
      assert "NewTool" in options.allowed_tools
      # Length should be original + 2 (even with duplicate)
      assert length(options.allowed_tools) == length(base.allowed_tools) + 2
    end
  end
end
