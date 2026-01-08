defmodule Mix.Tasks.Generate.Budget do
  @moduledoc """
  Generate a budget tracker Excel spreadsheet using Claude AI.

  ## Usage

      # From natural language description
      mix generate.budget "Create a monthly budget with Housing $1500, Food $600, Transport $400"

      # With output file
      mix generate.budget "Budget for college student" --output budget.xlsx

      # Interactive mode
      mix generate.budget --interactive

  ## Options

    * `--output`, `-o` - Output file path (default: output/budget.xlsx)
    * `--interactive`, `-i` - Start an interactive session with Claude
    * `--model`, `-m` - Claude model to use (default: haiku)

  ## Examples

      $ mix generate.budget "Create a monthly budget: Rent $1200, Utilities $200, Food $400"

      $ mix generate.budget "Make a budget tracker for a family of 4 with $5000 monthly income"

      $ mix generate.budget --interactive

  """
  use Mix.Task

  # Dialyzer can't trace through complex streaming patterns in ClaudeIntegration
  @dialyzer {:nowarn_function, run_with_claude: 3}

  alias DocumentGeneration.ClaudeIntegration

  @shortdoc "Generate a budget tracker Excel spreadsheet"

  @switches [
    output: :string,
    interactive: :boolean,
    model: :string
  ]

  @aliases [
    o: :output,
    i: :interactive,
    m: :model
  ]

  @impl Mix.Task
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:elixlsx)
    Application.ensure_all_started(:claude_agent_sdk)

    {opts, remaining, _invalid} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    output = Keyword.get(opts, :output, "output/budget.xlsx")
    model = Keyword.get(opts, :model, "haiku")
    interactive = Keyword.get(opts, :interactive, false)

    cond do
      interactive ->
        run_interactive(output, model)

      remaining != [] ->
        prompt = Enum.join(remaining, " ")
        run_with_claude(prompt, output, model)

      true ->
        Mix.shell().info(@moduledoc)
    end
  end

  defp run_with_claude(prompt, output, model) do
    Mix.shell().info("Using Claude AI to generate budget tracker...")
    Mix.shell().info("Prompt: #{prompt}\n")

    shell = Mix.shell()

    case ClaudeIntegration.generate_with_streaming(
           prompt,
           type: :budget_tracker,
           model: model,
           output_path: output,
           on_progress: fn msg -> shell.info(msg) end
         ) do
      {:ok, _workbook} ->
        Mix.shell().info("\nBudget tracker saved to: #{output}")

      {:error, reason} ->
        Mix.shell().error("Failed to generate budget: #{inspect(reason)}")
    end
  end

  defp run_interactive(output, _model) do
    Mix.shell().info("""
    Starting interactive budget creation session...

    Commands:
      /done - Finish and generate document
      /help - Show available commands

    Describe your budget requirements:
    """)

    ClaudeIntegration.interactive_session(:budget_tracker, fn
      :prompt ->
        IO.gets("You: ") |> String.trim()

      {:response, text} ->
        Mix.shell().info("Claude: #{text}\n")

      {:document, workbook} ->
        save_and_report(workbook, output)
    end)
  end

  defp save_and_report(workbook, output) do
    case DocumentGeneration.save(workbook, output) do
      :ok ->
        Mix.shell().info("Budget tracker saved to: #{output}")
        Mix.shell().info("Open with Excel or LibreOffice Calc to view.")

      {:error, reason} ->
        Mix.shell().error("Failed to save file: #{inspect(reason)}")
    end
  end
end
