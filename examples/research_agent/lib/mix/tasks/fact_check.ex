defmodule Mix.Tasks.FactCheck do
  @moduledoc """
  Mix task for the `/fact-check` command.

  Verifies claims using web searches and multi-source cross-referencing.

  ## Usage

      mix fact_check The Great Wall of China is visible from space
      mix fact_check --thoroughness high humans only use 10 percent of their brain

  ## Options

    * `--thoroughness`, `-t` - Verification level: quick, standard, high (default: standard)
    * `--output-dir`, `-o` - Output directory (default: ./research_output)

  ## Examples

      # Quick fact check
      $ mix fact_check --thoroughness quick water boils at 100C

      # Thorough verification with parallel research
      $ mix fact_check --thoroughness high the moon affects human behavior

  ## Output

  Provides:
    - Verdict: TRUE, FALSE, PARTIALLY TRUE, or UNCERTAIN
    - Confidence level (0-100%)
    - Sources consulted
    - Detailed explanation

  Also creates transcript files in the output directory.
  """

  use Mix.Task

  alias ResearchAgent.Commands.FactCheck

  @shortdoc "Fact-check a claim using multi-source verification"

  @switches [
    thoroughness: :string,
    output_dir: :string
  ]

  @aliases [
    t: :thoroughness,
    o: :output_dir
  ]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:research_agent)

    {opts, remaining, _invalid} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if remaining == [] do
      Mix.shell().info(@moduledoc)
    else
      output_dir = opts[:output_dir] || "./research_output"

      cmd_args =
        []
        |> add_if_present("--thoroughness", opts[:thoroughness])
        |> Kernel.++(remaining)

      case FactCheck.execute(cmd_args, output_dir: output_dir) do
        :ok ->
          Mix.shell().info("\nFact-check complete!")

        {:error, reason} ->
          Mix.shell().error("Fact-check failed: #{inspect(reason)}")
      end
    end
  end

  defp add_if_present(args, _flag, nil), do: args
  defp add_if_present(args, flag, value), do: args ++ [flag, value]
end
