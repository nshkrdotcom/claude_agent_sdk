defmodule ResearchAgent do
  @moduledoc """
  Multi-agent research coordination example using Claude Agent SDK.

  This application demonstrates how to build a sophisticated research system
  that coordinates multiple specialized agents to perform comprehensive
  research tasks.

  ## Features

  - **Lead Agent** - Coordinates research workflow and spawns subagents
  - **Researcher Subagents** - Gather information via web searches (parallel)
  - **Data Analyst Agent** - Extracts metrics and insights
  - **Report Writer Agent** - Produces final reports

  ## Commands

  - `/research <topic>` - Comprehensive topic research
  - `/fact-check <claim>` - Verify a claim's accuracy

  ## Architecture

  ```
  ResearchAgent (Application)
      |
      +-- ResearchAgent.Coordinator (Supervisor)
      |       |
      |       +-- SubagentTracker (GenServer + ETS)
      |       |
      |       +-- TranscriptLogger (GenServer)
      |
      +-- HookCoordinator
      |       |
      |       +-- Pre-tool hooks (track Task spawns)
      |       |
      |       +-- Post-tool hooks (track completions)
      |
      +-- Commands
              |
              +-- Research (/research)
              |
              +-- FactCheck (/fact-check)
  ```

  ## Example Usage

      # Start a research session
      ResearchAgent.research("quantum computing applications", depth: :deep)

      # Fact-check a claim
      ResearchAgent.fact_check("The Great Wall is visible from space")

  ## Configuration

  Configure the output directory in your config:

      config :research_agent,
        output_dir: "./research_output"
  """

  alias ResearchAgent.Commands.{FactCheck, Research}

  @doc """
  Performs comprehensive research on a topic.

  ## Options

  - `:depth` - Research depth (`:quick`, `:standard`, `:deep`)
  - `:format` - Output format (`:summary`, `:detailed`, `:comprehensive`)
  - `:output_dir` - Directory for output files

  ## Example

      ResearchAgent.research("AI safety", depth: :deep, format: :detailed)
  """
  @spec research(String.t(), keyword()) :: :ok | {:error, :no_topic}
  def research(topic, opts \\ []) do
    depth = Keyword.get(opts, :depth, :standard)
    format = Keyword.get(opts, :format, :summary)
    output_dir = Keyword.get(opts, :output_dir, default_output_dir())

    args =
      []
      |> maybe_add_opt("--depth", Atom.to_string(depth))
      |> maybe_add_opt("--format", Atom.to_string(format))
      |> Kernel.++(String.split(topic))

    Research.execute(args, output_dir: output_dir)
  end

  @doc """
  Verifies a claim for accuracy.

  ## Options

  - `:thoroughness` - Verification level (`:quick`, `:standard`, `:high`)
  - `:output_dir` - Directory for output files

  ## Example

      ResearchAgent.fact_check("Water boils at 100C at sea level", thoroughness: :high)
  """
  @spec fact_check(String.t(), keyword()) :: :ok | {:error, :no_claim}
  def fact_check(claim, opts \\ []) do
    thoroughness = Keyword.get(opts, :thoroughness, :standard)
    output_dir = Keyword.get(opts, :output_dir, default_output_dir())

    args =
      []
      |> maybe_add_opt("--thoroughness", Atom.to_string(thoroughness))
      |> Kernel.++(String.split(claim))

    FactCheck.execute(args, output_dir: output_dir)
  end

  @doc """
  Returns the version of the ResearchAgent application.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:research_agent, :vsn) |> to_string()
  end

  # Private Functions

  defp default_output_dir do
    Application.get_env(:research_agent, :output_dir, "./research_output")
  end

  @spec maybe_add_opt([String.t()], String.t(), String.t()) :: [String.t()]
  defp maybe_add_opt(args, flag, value), do: args ++ [flag, value]
end
