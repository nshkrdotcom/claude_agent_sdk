defmodule ResearchAgent.Commands.ResearchTest do
  use ExUnit.Case, async: false

  alias ResearchAgent.Commands.Research

  @output_dir Path.join(
                System.tmp_dir!(),
                "research_cmd_test_#{System.unique_integer([:positive])}"
              )

  setup do
    File.mkdir_p!(@output_dir)
    on_exit(fn -> File.rm_rf!(@output_dir) end)
    :ok
  end

  describe "parse_args/1" do
    test "extracts topic from arguments" do
      {:ok, parsed} = Research.parse_args(["quantum", "computing", "applications"])

      assert parsed.topic == "quantum computing applications"
    end

    test "handles single word topic" do
      {:ok, parsed} = Research.parse_args(["AI"])

      assert parsed.topic == "AI"
    end

    test "returns error for empty arguments" do
      assert {:error, :no_topic} = Research.parse_args([])
    end

    test "extracts depth option" do
      {:ok, parsed} = Research.parse_args(["--depth", "deep", "AI", "safety"])

      assert parsed.topic == "AI safety"
      assert parsed.depth == :deep
    end

    test "extracts format option" do
      {:ok, parsed} = Research.parse_args(["--format", "detailed", "machine", "learning"])

      assert parsed.topic == "machine learning"
      assert parsed.format == :detailed
    end

    test "uses default options when not specified" do
      {:ok, parsed} = Research.parse_args(["test", "topic"])

      assert parsed.depth == :standard
      assert parsed.format == :summary
    end
  end

  describe "build_options/1" do
    test "creates SDK options with research configuration" do
      parsed = %{topic: "AI", depth: :standard, format: :summary}
      options = Research.build_options(parsed, @output_dir)

      assert is_binary(options.model)
      assert is_list(options.allowed_tools)
      assert "Task" in options.allowed_tools
      assert "WebSearch" in options.allowed_tools
    end

    test "includes hooks for subagent tracking" do
      parsed = %{topic: "test", depth: :standard, format: :summary}
      options = Research.build_options(parsed, @output_dir)

      assert options.hooks != nil
      assert Map.has_key?(options.hooks, :pre_tool_use)
    end
  end

  describe "build_prompt/1" do
    test "creates a research prompt with the topic" do
      parsed = %{topic: "climate change", depth: :standard, format: :summary}
      prompt = Research.build_prompt(parsed)

      assert is_binary(prompt)
      assert String.contains?(prompt, "climate change")
    end

    test "adjusts prompt based on depth" do
      deep_parsed = %{topic: "AI", depth: :deep, format: :summary}
      standard_parsed = %{topic: "AI", depth: :standard, format: :summary}

      deep_prompt = Research.build_prompt(deep_parsed)
      standard_prompt = Research.build_prompt(standard_parsed)

      assert deep_prompt != standard_prompt
    end
  end
end
