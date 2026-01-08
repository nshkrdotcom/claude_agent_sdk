defmodule ResearchAgent.Commands.FactCheck do
  @moduledoc """
  Implements the `/fact-check <claim>` command.

  The FactCheck command verifies claims using:
  1. Web searches for supporting/contradicting evidence
  2. Source credibility assessment
  3. Multi-source cross-referencing

  ## Usage

      /fact-check The Great Wall of China is visible from space
      /fact-check --thoroughness high humans use only 10% of their brain

  ## Options

  - `--thoroughness` - Verification level: `quick`, `standard`, `high` (default: standard)

  ## Output

  - Verdict: TRUE, FALSE, PARTIALLY TRUE, or UNCERTAIN
  - Confidence level (0.0 - 1.0)
  - Supporting/contradicting sources
  - Explanation of findings
  """

  alias ClaudeAgentSDK.Options
  alias ResearchAgent.{Coordinator, PromptLoader}

  @typedoc "Parsed fact-check arguments"
  @type parsed_args :: %{
          claim: String.t(),
          thoroughness: :quick | :standard | :high
        }

  @typedoc "Fact-check result"
  @type result :: %{
          verdict: true | false | :partially_true | :uncertain,
          confidence: float(),
          sources: [String.t()],
          explanation: String.t()
        }

  @doc """
  Parses command arguments into a structured format.

  ## Returns

  - `{:ok, parsed_args}` - Successfully parsed arguments
  - `{:error, :no_claim}` - No claim provided
  """
  @spec parse_args([String.t()]) :: {:ok, parsed_args()} | {:error, :no_claim}
  def parse_args([]), do: {:error, :no_claim}

  def parse_args(args) do
    {opts, claim_parts, _} =
      OptionParser.parse(args,
        strict: [thoroughness: :string],
        aliases: [t: :thoroughness]
      )

    if claim_parts == [] do
      {:error, :no_claim}
    else
      claim = Enum.join(claim_parts, " ")

      thoroughness =
        case Keyword.get(opts, :thoroughness, "standard") do
          "quick" -> :quick
          "high" -> :high
          _ -> :standard
        end

      {:ok, %{claim: claim, thoroughness: thoroughness}}
    end
  end

  @doc """
  Builds Claude SDK options for the fact-check command.
  """
  @spec build_options(parsed_args(), String.t()) :: Options.t()
  def build_options(parsed, output_dir) do
    {:ok, coordinator} = Coordinator.start_link(output_dir: output_dir)
    hooks = Coordinator.get_hooks(coordinator)

    tools =
      case parsed.thoroughness do
        :high -> ["Task", "WebSearch", "Read"]
        _ -> ["WebSearch", "Read"]
      end

    %Options{
      model: select_model(parsed.thoroughness),
      max_turns: max_turns_for_thoroughness(parsed.thoroughness),
      system_prompt: PromptLoader.get_system_prompt(:fact_check),
      allowed_tools: tools,
      permission_mode: :accept_edits,
      hooks: hooks
    }
  end

  @doc """
  Builds the fact-check prompt from parsed arguments.
  """
  @spec build_prompt(parsed_args()) :: String.t()
  def build_prompt(parsed) do
    thoroughness_instruction = thoroughness_instructions(parsed.thoroughness)

    """
    Claim to Verify: "#{parsed.claim}"

    #{thoroughness_instruction}

    Please fact-check this claim by:
    1. Searching for evidence that supports the claim
    2. Searching for evidence that contradicts the claim
    3. Evaluating the credibility and reliability of sources
    4. Determining the consensus among authoritative sources

    Provide your verdict in this format:
    - VERDICT: [TRUE/FALSE/PARTIALLY TRUE/UNCERTAIN]
    - CONFIDENCE: [0.0-1.0]
    - SOURCES: [List credible sources consulted]
    - EXPLANATION: [Detailed explanation of your findings]

    Begin your fact-check now.
    """
  end

  @doc """
  Formats a fact-check result for display.
  """
  @spec format_result(result()) :: String.t()
  def format_result(result) do
    verdict_display =
      case result.verdict do
        true -> "TRUE"
        false -> "FALSE"
        :partially_true -> "PARTIALLY TRUE"
        :uncertain -> "UNCERTAIN"
      end

    confidence_pct = round(result.confidence * 100)

    sources_display =
      if result.sources == [] do
        "No sources found"
      else
        Enum.map_join(result.sources, "\n", &"  - #{&1}")
      end

    """
    =====================================================
    FACT-CHECK RESULT
    =====================================================

    VERDICT: #{verdict_display}
    CONFIDENCE: #{confidence_pct}%

    SOURCES CONSULTED:
    #{sources_display}

    EXPLANATION:
    #{result.explanation}

    =====================================================
    """
  end

  @doc """
  Executes the fact-check command.
  """
  @spec execute([String.t()], keyword()) :: :ok | {:error, :no_claim}
  def execute(args, opts \\ []) do
    output_dir = Keyword.get(opts, :output_dir, "./research_output")

    case parse_args(args) do
      {:ok, parsed} ->
        IO.puts("Fact-checking claim: \"#{parsed.claim}\"")
        IO.puts("Thoroughness: #{parsed.thoroughness}")

        options = build_options(parsed, output_dir)
        prompt = build_prompt(parsed)

        messages =
          ClaudeAgentSDK.query(prompt, options)
          |> Enum.to_list()

        display_results(messages)

        :ok

      {:error, :no_claim} ->
        IO.puts("Error: Please provide a claim to verify")
        IO.puts("Usage: /fact-check <claim>")
        {:error, :no_claim}
    end
  end

  # Private Functions

  defp select_model(:quick), do: "haiku"
  defp select_model(:standard), do: "haiku"
  defp select_model(:high), do: "haiku"

  defp max_turns_for_thoroughness(:quick), do: 10
  defp max_turns_for_thoroughness(:standard), do: 20
  defp max_turns_for_thoroughness(:high), do: 50

  defp thoroughness_instructions(:quick) do
    """
    Quick verification:
    - Perform 1-2 web searches
    - Check the most authoritative sources
    - Provide a rapid assessment
    """
  end

  defp thoroughness_instructions(:standard) do
    """
    Standard verification:
    - Perform 3-5 web searches from different angles
    - Cross-reference at least 3 sources
    - Evaluate source credibility
    - Provide a balanced assessment
    """
  end

  defp thoroughness_instructions(:high) do
    """
    Thorough verification:
    - Perform comprehensive searches (5+ queries)
    - Cross-reference multiple authoritative sources
    - Look for primary sources when possible
    - Consider counter-arguments and edge cases
    - Use subagents for parallel verification if needed
    - Provide detailed analysis with citations
    """
  end

  defp display_results(messages) do
    assistant_messages =
      messages
      |> Enum.filter(&(&1.type == :assistant))

    if assistant_messages != [] do
      IO.puts("\n" <> String.duplicate("=", 60))
      IO.puts("FACT-CHECK RESULTS")
      IO.puts(String.duplicate("=", 60) <> "\n")

      last_message = List.last(assistant_messages)
      text = ClaudeAgentSDK.ContentExtractor.extract_text(last_message)
      IO.puts(text)
    end

    case Enum.find(messages, &(&1.type == :result)) do
      %{subtype: :success} ->
        IO.puts("\n[Fact-check completed successfully]")

      %{subtype: status} ->
        IO.puts("\n[Fact-check completed with status: #{status}]")

      nil ->
        IO.puts("\n[No result message received]")
    end
  end
end
