defmodule ResearchAgent.Commands.FactCheckTest do
  use ExUnit.Case, async: false

  alias ResearchAgent.Commands.FactCheck

  @output_dir Path.join(
                System.tmp_dir!(),
                "fact_check_test_#{System.unique_integer([:positive])}"
              )

  setup do
    File.mkdir_p!(@output_dir)
    on_exit(fn -> File.rm_rf!(@output_dir) end)
    :ok
  end

  describe "parse_args/1" do
    test "extracts claim from arguments" do
      {:ok, parsed} = FactCheck.parse_args(["The", "sky", "is", "blue"])

      assert parsed.claim == "The sky is blue"
    end

    test "handles quoted claim" do
      {:ok, parsed} = FactCheck.parse_args(["Water boils at 100 degrees Celsius"])

      assert parsed.claim == "Water boils at 100 degrees Celsius"
    end

    test "returns error for empty arguments" do
      assert {:error, :no_claim} = FactCheck.parse_args([])
    end

    test "extracts thoroughness option" do
      {:ok, parsed} = FactCheck.parse_args(["--thoroughness", "high", "claim", "text"])

      assert parsed.claim == "claim text"
      assert parsed.thoroughness == :high
    end

    test "uses default thoroughness" do
      {:ok, parsed} = FactCheck.parse_args(["some", "claim"])

      assert parsed.thoroughness == :standard
    end
  end

  describe "build_options/1" do
    test "creates SDK options with fact-check configuration" do
      parsed = %{claim: "Test claim", thoroughness: :standard}
      options = FactCheck.build_options(parsed, @output_dir)

      assert is_binary(options.model)
      assert is_list(options.allowed_tools)
      assert "WebSearch" in options.allowed_tools
    end

    test "enables Task tool for parallel verification" do
      parsed = %{claim: "Test claim", thoroughness: :high}
      options = FactCheck.build_options(parsed, @output_dir)

      assert "Task" in options.allowed_tools
    end
  end

  describe "build_prompt/1" do
    test "creates a fact-check prompt with the claim" do
      parsed = %{claim: "Earth is flat", thoroughness: :standard}
      prompt = FactCheck.build_prompt(parsed)

      assert is_binary(prompt)
      assert String.contains?(prompt, "Earth is flat")
    end

    test "includes verification instructions" do
      parsed = %{claim: "Test claim", thoroughness: :standard}
      prompt = FactCheck.build_prompt(parsed)

      assert String.contains?(prompt, "verif") or String.contains?(prompt, "fact")
    end

    test "adjusts prompt based on thoroughness" do
      high_parsed = %{claim: "Test", thoroughness: :high}
      standard_parsed = %{claim: "Test", thoroughness: :standard}

      high_prompt = FactCheck.build_prompt(high_parsed)
      standard_prompt = FactCheck.build_prompt(standard_parsed)

      assert high_prompt != standard_prompt
    end
  end

  describe "format_result/1" do
    test "formats a true verdict" do
      result = %{
        verdict: true,
        confidence: 0.95,
        sources: ["source1.com", "source2.org"],
        explanation: "Multiple reliable sources confirm this."
      }

      formatted = FactCheck.format_result(result)

      assert is_binary(formatted)
      assert String.contains?(formatted, "TRUE") or String.contains?(formatted, "true")
    end

    test "formats a false verdict" do
      result = %{
        verdict: false,
        confidence: 0.85,
        sources: ["fact-check.com"],
        explanation: "This has been debunked."
      }

      formatted = FactCheck.format_result(result)

      assert String.contains?(formatted, "FALSE") or String.contains?(formatted, "false")
    end

    test "formats an uncertain verdict" do
      result = %{
        verdict: :uncertain,
        confidence: 0.5,
        sources: [],
        explanation: "Insufficient evidence."
      }

      formatted = FactCheck.format_result(result)

      assert String.contains?(formatted, "UNCERTAIN") or String.contains?(formatted, "uncertain")
    end
  end
end
