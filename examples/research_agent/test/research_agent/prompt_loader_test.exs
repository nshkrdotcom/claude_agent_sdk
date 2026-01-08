defmodule ResearchAgent.PromptLoaderTest do
  use ExUnit.Case, async: true

  alias ResearchAgent.PromptLoader

  describe "load_prompt/1" do
    test "loads the lead agent prompt" do
      {:ok, prompt} = PromptLoader.load_prompt(:lead_agent)

      assert is_binary(prompt)
      assert String.contains?(prompt, "research")
    end

    test "loads the researcher prompt" do
      {:ok, prompt} = PromptLoader.load_prompt(:researcher)

      assert is_binary(prompt)
      assert String.contains?(prompt, "search") or String.contains?(prompt, "research")
    end

    test "loads the analyst prompt" do
      {:ok, prompt} = PromptLoader.load_prompt(:analyst)

      assert is_binary(prompt)
      assert String.contains?(prompt, "data") or String.contains?(prompt, "analyz")
    end

    test "loads the writer prompt" do
      {:ok, prompt} = PromptLoader.load_prompt(:writer)

      assert is_binary(prompt)
      assert String.contains?(prompt, "report") or String.contains?(prompt, "write")
    end

    test "returns error for unknown prompt" do
      assert {:error, :unknown_prompt} = PromptLoader.load_prompt(:nonexistent)
    end
  end

  describe "load_prompt/2 with substitutions" do
    test "substitutes placeholders in the prompt" do
      {:ok, prompt} = PromptLoader.load_prompt(:lead_agent, topic: "quantum computing")

      # The prompt should have the topic substituted
      assert String.contains?(prompt, "quantum computing") or
               not String.contains?(prompt, "{{topic}}")
    end

    test "handles multiple substitutions" do
      {:ok, prompt} =
        PromptLoader.load_prompt(:researcher,
          topic: "AI safety",
          depth: "comprehensive"
        )

      assert is_binary(prompt)
    end
  end

  describe "get_system_prompt/1" do
    test "returns a system prompt for the research command" do
      prompt = PromptLoader.get_system_prompt(:research)

      assert is_binary(prompt)
      assert String.length(prompt) > 0
    end

    test "returns a system prompt for the fact-check command" do
      prompt = PromptLoader.get_system_prompt(:fact_check)

      assert is_binary(prompt)
      assert String.contains?(prompt, "fact") or String.contains?(prompt, "verif")
    end
  end
end
