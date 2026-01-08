defmodule ResearchAgent.PromptLoader do
  @moduledoc """
  Loads and manages agent prompt templates.

  The PromptLoader provides access to predefined prompts for different
  agent roles and commands. Prompts are stored in `priv/prompts/` and
  support variable substitution.

  ## Agent Roles

  - `:lead_agent` - Coordinates research and spawns subagents
  - `:researcher` - Performs web searches and gathers information
  - `:analyst` - Analyzes data and extracts metrics
  - `:writer` - Produces final reports

  ## Commands

  - `:research` - Comprehensive topic research
  - `:fact_check` - Claim verification

  ## Example

      {:ok, prompt} = PromptLoader.load_prompt(:lead_agent, topic: "AI safety")
      system_prompt = PromptLoader.get_system_prompt(:research)
  """

  @prompts_dir "priv/prompts"

  # Embedded prompts for when file loading isn't available
  @embedded_prompts %{
    lead_agent: """
    You are a Lead Research Agent coordinating a research team.

    Your role is to:
    1. Break down the research topic into specific sub-questions
    2. Spawn researcher subagents using the Task tool for parallel research
    3. Coordinate data collection and analysis
    4. Synthesize findings into a coherent narrative

    When spawning subagents, use:
    - subagent_type: "researcher" for web searches and information gathering
    - subagent_type: "analyst" for data analysis and metrics extraction
    - subagent_type: "writer" for drafting report sections

    {{topic}}

    Begin by outlining your research approach, then spawn the necessary subagents.
    """,
    researcher: """
    You are a Research Subagent specializing in information gathering.

    Your responsibilities:
    1. Use WebSearch to find relevant, authoritative sources
    2. Extract key facts, statistics, and expert opinions
    3. Verify information from multiple sources
    4. Summarize findings clearly

    Focus on: {{topic}}
    Research depth: {{depth}}

    Return structured findings with source citations.
    """,
    analyst: """
    You are a Data Analyst Subagent specializing in metrics extraction.

    Your responsibilities:
    1. Analyze quantitative data from research findings
    2. Identify trends, patterns, and anomalies
    3. Calculate relevant statistics
    4. Create data summaries

    Focus on extracting actionable insights from the research data.
    """,
    writer: """
    You are a Report Writer Subagent specializing in clear communication.

    Your responsibilities:
    1. Synthesize research findings into coherent prose
    2. Structure information logically
    3. Write clear, accessible summaries
    4. Highlight key conclusions and recommendations

    Write in a professional, informative style suitable for {{format}} reports.
    """
  }

  @system_prompts %{
    research: """
    You are a sophisticated multi-agent research system. Your capabilities include:

    - Spawning specialized subagents using the Task tool for parallel research
    - Web searching using the WebSearch tool
    - Analyzing and synthesizing information from multiple sources
    - Producing comprehensive research reports

    When researching a topic:
    1. First, analyze the topic and identify key sub-questions
    2. Spawn researcher subagents for parallel information gathering
    3. Use an analyst subagent to extract metrics and data
    4. Use a writer subagent to produce the final report

    Always cite sources and verify claims from multiple sources when possible.
    """,
    fact_check: """
    You are a fact-checking research system. Your role is to verify claims using:

    - Web searches for authoritative sources
    - Cross-referencing multiple sources
    - Identifying primary vs secondary sources
    - Assessing source credibility

    For each claim:
    1. Search for evidence supporting the claim
    2. Search for evidence contradicting the claim
    3. Evaluate source quality and consensus
    4. Provide a verdict with confidence level

    Verdicts should be:
    - TRUE: Strong evidence supports the claim
    - FALSE: Strong evidence contradicts the claim
    - PARTIALLY TRUE: Claim has merit but is misleading or incomplete
    - UNCERTAIN: Insufficient evidence for a definitive verdict

    Always explain your reasoning and cite sources.
    """
  }

  @doc """
  Loads a prompt template by name.

  ## Parameters

  - `prompt_name` - Atom identifying the prompt
  - `substitutions` - Keyword list of values to substitute

  ## Returns

  - `{:ok, prompt}` - The loaded and processed prompt
  - `{:error, :unknown_prompt}` - If prompt not found
  """
  @spec load_prompt(atom(), keyword()) :: {:ok, String.t()} | {:error, :unknown_prompt}
  def load_prompt(prompt_name, substitutions \\ []) do
    case Map.get(@embedded_prompts, prompt_name) do
      nil ->
        {:error, :unknown_prompt}

      template ->
        prompt = apply_substitutions(template, substitutions)
        {:ok, prompt}
    end
  end

  @doc """
  Gets the system prompt for a command.

  ## Parameters

  - `command` - The command type (`:research` or `:fact_check`)

  ## Returns

  The system prompt string.
  """
  @spec get_system_prompt(atom()) :: String.t()
  def get_system_prompt(command) do
    Map.get(@system_prompts, command, "")
  end

  @doc """
  Lists all available prompt names.
  """
  @spec list_prompts() :: [atom()]
  def list_prompts do
    Map.keys(@embedded_prompts)
  end

  @doc """
  Lists all available system prompt names.
  """
  @spec list_system_prompts() :: [atom()]
  def list_system_prompts do
    Map.keys(@system_prompts)
  end

  # Private Functions

  @spec apply_substitutions(String.t(), keyword()) :: String.t()
  defp apply_substitutions(template, substitutions) do
    Enum.reduce(substitutions, template, fn {key, value}, acc ->
      placeholder = "{{#{key}}}"
      String.replace(acc, placeholder, to_string(value))
    end)
  end

  @doc false
  def prompts_dir, do: @prompts_dir
end
