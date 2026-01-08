defmodule Mix.Tasks.Research do
  @moduledoc """
  Mix task for the `/research` command.

  Performs comprehensive multi-agent research on a topic.

  ## Usage

      mix research quantum computing applications
      mix research --depth deep artificial intelligence ethics
      mix research --format detailed --depth standard climate change

  ## Options

    * `--depth`, `-d` - Research depth: quick, standard, deep (default: standard)
    * `--format`, `-f` - Output format: summary, detailed, comprehensive (default: summary)
    * `--output-dir`, `-o` - Output directory (default: ./research_output)

  ## Examples

      # Quick research on a topic
      $ mix research --depth quick renewable energy

      # Deep, comprehensive research
      $ mix research --depth deep --format comprehensive machine learning

  ## Output

  Creates files in the output directory:
    - `sessions/<session_id>/notes_*.md` - Research notes
    - `sessions/<session_id>/report_*.md` - Final report
    - `sessions/<session_id>/transcript.json` - Session transcript
  """

  use Mix.Task

  alias ResearchAgent.Commands.Research

  @shortdoc "Perform multi-agent research on a topic"

  @switches [
    depth: :string,
    format: :string,
    output_dir: :string
  ]

  @aliases [
    d: :depth,
    f: :format,
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

      # Build args list with options
      cmd_args =
        []
        |> add_if_present("--depth", opts[:depth])
        |> add_if_present("--format", opts[:format])
        |> Kernel.++(remaining)

      case Research.execute(cmd_args, output_dir: output_dir) do
        :ok ->
          Mix.shell().info("\nResearch complete!")

        {:error, reason} ->
          Mix.shell().error("Research failed: #{inspect(reason)}")
      end
    end
  end

  defp add_if_present(args, _flag, nil), do: args
  defp add_if_present(args, flag, value), do: args ++ [flag, value]
end
