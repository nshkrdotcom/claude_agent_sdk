defmodule ResearchAgent.Commands.Research do
  @moduledoc """
  Implements the `/research <topic>` command.

  The Research command orchestrates a multi-agent research workflow:
  1. Lead Agent analyzes the topic and creates a research plan
  2. Researcher subagents gather information in parallel
  3. Data Analyst extracts metrics and insights
  4. Report Writer produces the final output

  ## Usage

      /research quantum computing applications
      /research --depth deep artificial intelligence ethics
      /research --format detailed climate change impacts

  ## Options

  - `--depth` - Research depth: `quick`, `standard`, `deep` (default: standard)
  - `--format` - Output format: `summary`, `detailed`, `comprehensive` (default: summary)

  ## Output

  Creates files in the session output directory:
  - Research notes for each sub-topic
  - Final research report
  - Structured data with findings
  """

  alias ClaudeAgentSDK.Options
  alias ResearchAgent.{Coordinator, PromptLoader}

  @typedoc "Parsed research arguments"
  @type parsed_args :: %{
          topic: String.t(),
          depth: :quick | :standard | :deep,
          format: :summary | :detailed | :comprehensive
        }

  @doc """
  Parses command arguments into a structured format.

  ## Returns

  - `{:ok, parsed_args}` - Successfully parsed arguments
  - `{:error, :no_topic}` - No topic provided
  """
  @spec parse_args([String.t()]) :: {:ok, parsed_args()} | {:error, :no_topic}
  def parse_args([]), do: {:error, :no_topic}

  def parse_args(args) do
    {opts, topic_parts, _} =
      OptionParser.parse(args,
        strict: [depth: :string, format: :string],
        aliases: [d: :depth, f: :format]
      )

    if topic_parts == [] do
      {:error, :no_topic}
    else
      topic = Enum.join(topic_parts, " ")

      depth =
        case Keyword.get(opts, :depth, "standard") do
          "quick" -> :quick
          "deep" -> :deep
          _ -> :standard
        end

      format =
        case Keyword.get(opts, :format, "summary") do
          "detailed" -> :detailed
          "comprehensive" -> :comprehensive
          _ -> :summary
        end

      {:ok, %{topic: topic, depth: depth, format: format}}
    end
  end

  @doc """
  Builds Claude SDK options for the research command.

  Sets up:
  - Model selection
  - Allowed tools (Task, WebSearch, Read, etc.)
  - Hooks for subagent tracking
  - System prompt

  ## Parameters

  - `parsed` - Parsed arguments from `parse_args/1`
  - `output_dir` - Directory for output files
  """
  @spec build_options(parsed_args(), String.t()) :: Options.t()
  def build_options(parsed, output_dir) do
    # Start coordinator for this research session
    {:ok, coordinator} = Coordinator.start_link(output_dir: output_dir)
    hooks = Coordinator.get_hooks(coordinator)

    %Options{
      model: select_model(parsed.depth),
      max_turns: max_turns_for_depth(parsed.depth),
      system_prompt: PromptLoader.get_system_prompt(:research),
      allowed_tools: [
        "Task",
        "WebSearch",
        "Read",
        "Glob",
        "Grep",
        "Write"
      ],
      permission_mode: :accept_edits,
      hooks: hooks
    }
  end

  @doc """
  Builds the research prompt from parsed arguments.
  """
  @spec build_prompt(parsed_args()) :: String.t()
  def build_prompt(parsed) do
    depth_instruction = depth_instructions(parsed.depth)
    format_instruction = format_instructions(parsed.format)

    """
    Research Topic: #{parsed.topic}

    #{depth_instruction}

    #{format_instruction}

    Please begin by:
    1. Analyzing the topic and identifying 3-5 key sub-questions to investigate
    2. Spawning researcher subagents (using the Task tool) to gather information on each sub-question
    3. Once research is complete, use an analyst subagent to extract key metrics and data
    4. Finally, use a writer subagent to produce a comprehensive report

    Start your research now.
    """
  end

  @doc """
  Executes the research command.

  This is the main entry point when the command is invoked.
  """
  @spec execute([String.t()], keyword()) :: :ok | {:error, :no_topic}
  def execute(args, opts \\ []) do
    output_dir = Keyword.get(opts, :output_dir, "./research_output")

    case parse_args(args) do
      {:ok, parsed} ->
        IO.puts("Starting research on: #{parsed.topic}")
        IO.puts("Depth: #{parsed.depth}, Format: #{parsed.format}")

        options = build_options(parsed, output_dir)
        prompt = build_prompt(parsed)

        # Execute the research
        messages =
          ClaudeAgentSDK.query(prompt, options)
          |> Enum.to_list()

        # Extract and display results
        display_results(messages)

        :ok

      {:error, :no_topic} ->
        IO.puts("Error: Please provide a research topic")
        IO.puts("Usage: /research <topic>")
        {:error, :no_topic}
    end
  end

  # Private Functions

  defp select_model(:quick), do: "haiku"
  defp select_model(:standard), do: "haiku"
  defp select_model(:deep), do: "haiku"

  defp max_turns_for_depth(:quick), do: 20
  defp max_turns_for_depth(:standard), do: 50
  defp max_turns_for_depth(:deep), do: 100

  defp depth_instructions(:quick) do
    """
    Perform a quick research overview:
    - Focus on the most important aspects only
    - Use 1-2 researcher subagents
    - Produce a brief summary
    """
  end

  defp depth_instructions(:standard) do
    """
    Perform standard research:
    - Cover major aspects of the topic
    - Use 2-3 researcher subagents for parallel research
    - Include data analysis
    - Produce a balanced report
    """
  end

  defp depth_instructions(:deep) do
    """
    Perform comprehensive, in-depth research:
    - Investigate all significant aspects of the topic
    - Use 3-5 researcher subagents for thorough coverage
    - Include detailed data analysis and metrics
    - Cross-reference multiple sources
    - Produce a comprehensive report with citations
    """
  end

  defp format_instructions(:summary) do
    "Output Format: Produce a concise summary (2-3 paragraphs) highlighting key findings."
  end

  defp format_instructions(:detailed) do
    """
    Output Format: Produce a detailed report with:
    - Executive summary
    - Main findings (organized by topic)
    - Data and metrics section
    - Conclusions
    """
  end

  defp format_instructions(:comprehensive) do
    """
    Output Format: Produce a comprehensive research report with:
    - Executive summary
    - Introduction and background
    - Detailed findings (organized by sub-topic)
    - Data analysis and metrics
    - Discussion of implications
    - Conclusions and recommendations
    - Sources and citations
    """
  end

  defp display_results(messages) do
    # Extract final assistant response
    assistant_messages =
      messages
      |> Enum.filter(&(&1.type == :assistant))

    if assistant_messages != [] do
      IO.puts("\n" <> String.duplicate("=", 60))
      IO.puts("RESEARCH RESULTS")
      IO.puts(String.duplicate("=", 60) <> "\n")

      last_message = List.last(assistant_messages)
      text = ClaudeAgentSDK.ContentExtractor.extract_text(last_message)
      IO.puts(text)
    end

    # Show result status
    case Enum.find(messages, &(&1.type == :result)) do
      %{subtype: :success} ->
        IO.puts("\n[Research completed successfully]")

      %{subtype: status} ->
        IO.puts("\n[Research completed with status: #{status}]")

      nil ->
        IO.puts("\n[No result message received]")
    end
  end
end
