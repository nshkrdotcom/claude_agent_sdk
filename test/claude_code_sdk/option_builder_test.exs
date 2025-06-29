defmodule ClaudeCodeSDK.OptionBuilderTest do
  use ExUnit.Case

  alias ClaudeCodeSDK.{OptionBuilder, Options}

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
      options = OptionBuilder.with_working_directory("/my/project", base)

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
      options = OptionBuilder.with_system_prompt("Analyze this", base)

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
      with_dir = OptionBuilder.with_working_directory("/project", base)
      options = OptionBuilder.with_system_prompt("Be helpful", with_dir)

      assert options.max_turns == 10
      assert options.cwd == "/project"
      assert options.system_prompt == "Be helpful"
    end

    test "merge preserves all non-overridden fields" do
      base = OptionBuilder.build_documentation_options()
      merged = OptionBuilder.merge(base, %{max_turns: 10})

      assert merged.max_turns == 10
      assert merged.allowed_tools == ["Read", "Write"]
      assert merged.disallowed_tools == ["Bash", "Edit"]
      assert merged.permission_mode == :accept_edits
    end
  end
end
