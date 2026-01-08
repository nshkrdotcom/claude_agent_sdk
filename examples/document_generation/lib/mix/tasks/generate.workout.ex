defmodule Mix.Tasks.Generate.Workout do
  @moduledoc """
  Generate a workout log Excel spreadsheet using Claude AI.

  ## Usage

      # From natural language description
      mix generate.workout "Create a weekly workout plan for weight loss"

      # With output file
      mix generate.workout "Log my runs this week" --output workout.xlsx

      # Interactive mode
      mix generate.workout --interactive

  ## Options

    * `--output`, `-o` - Output file path (default: output/workout.xlsx)
    * `--interactive`, `-i` - Start an interactive session with Claude
    * `--model`, `-m` - Claude model to use (default: haiku)

  ## Examples

      $ mix generate.workout "Create a 5-day gym routine with cardio and strength training"

      $ mix generate.workout "Track: Monday running 30min, Tuesday weights 45min"

      $ mix generate.workout --interactive

  """
  use Mix.Task

  # Dialyzer can't trace through complex streaming patterns in ClaudeIntegration
  @dialyzer {:nowarn_function, run_with_claude: 3}

  alias DocumentGeneration.ClaudeIntegration

  @shortdoc "Generate a workout log Excel spreadsheet"

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

    output = Keyword.get(opts, :output, "output/workout.xlsx")
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
    Mix.shell().info("Using Claude AI to generate workout log...")
    Mix.shell().info("Prompt: #{prompt}\n")

    shell = Mix.shell()

    case ClaudeIntegration.generate_with_streaming(
           prompt,
           type: :workout_log,
           model: model,
           output_path: output,
           on_progress: fn msg -> shell.info(msg) end
         ) do
      {:ok, _workbook} ->
        Mix.shell().info("\nWorkout log saved to: #{output}")

      {:error, reason} ->
        Mix.shell().error("Failed to generate workout log: #{inspect(reason)}")
    end
  end

  defp run_interactive(output, _model) do
    Mix.shell().info("""
    Starting interactive workout log creation session...

    Commands:
      /done - Finish and generate document
      /help - Show available commands

    Describe your workout requirements:
    """)

    ClaudeIntegration.interactive_session(:workout_log, fn
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
        Mix.shell().info("Workout log saved to: #{output}")
        Mix.shell().info("Open with Excel or LibreOffice Calc to view.")

      {:error, reason} ->
        Mix.shell().error("Failed to save file: #{inspect(reason)}")
    end
  end
end
