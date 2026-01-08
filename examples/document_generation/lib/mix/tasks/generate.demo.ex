defmodule Mix.Tasks.Generate.Demo do
  @moduledoc """
  Run a demonstration of the document generation capabilities.

  This task generates sample documents to showcase the features of
  the document generation library.

  ## Usage

      mix generate.demo

  ## Options

    * `--output-dir`, `-d` - Output directory (default: output/)
    * `--type`, `-t` - Demo type: budget, workout, or all (default: all)

  ## Examples

      # Run all demos
      $ mix generate.demo

      # Run only budget demo
      $ mix generate.demo --type budget

      # Custom output directory
      $ mix generate.demo -d demo_output/

  """
  use Mix.Task

  alias DocumentGeneration.Excel

  @shortdoc "Run document generation demonstration"

  @switches [
    output_dir: :string,
    type: :string
  ]

  @aliases [
    d: :output_dir,
    t: :type
  ]

  @impl Mix.Task
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:elixlsx)

    {opts, _remaining, _invalid} =
      OptionParser.parse(args, switches: @switches, aliases: @aliases)

    output_dir = Keyword.get(opts, :output_dir, "output")
    demo_type = Keyword.get(opts, :type, "all")

    # Ensure output directory exists
    File.mkdir_p!(output_dir)

    Mix.shell().info("""
    ====================================
    Document Generation Demo
    ====================================
    """)

    case demo_type do
      "budget" ->
        run_budget_demo(output_dir)

      "workout" ->
        run_workout_demo(output_dir)

      "all" ->
        run_budget_demo(output_dir)
        run_workout_demo(output_dir)

      _ ->
        Mix.shell().error("Unknown demo type: #{demo_type}")
        Mix.shell().info("Available types: budget, workout, all")
    end

    Mix.shell().info("""

    ====================================
    Demo Complete!
    ====================================
    Check the #{output_dir}/ directory for generated files.
    """)
  end

  defp run_budget_demo(output_dir) do
    Mix.shell().info("\n--- Budget Tracker Demo ---\n")

    categories = [
      %{name: "Housing", budget: 1500, actual: 1450},
      %{name: "Utilities", budget: 200, actual: 185},
      %{name: "Groceries", budget: 600, actual: 580},
      %{name: "Transportation", budget: 400, actual: 420},
      %{name: "Insurance", budget: 300, actual: 300},
      %{name: "Entertainment", budget: 200, actual: 250},
      %{name: "Dining Out", budget: 150, actual: 180},
      %{name: "Savings", budget: 500, actual: 400}
    ]

    Mix.shell().info("Creating budget tracker with #{length(categories)} categories...")

    workbook = Excel.budget_tracker(categories)
    output_path = Path.join(output_dir, "demo_budget.xlsx")

    case Excel.write_to_file(workbook, output_path) do
      :ok ->
        Mix.shell().info("Budget tracker saved to: #{output_path}")
        display_budget_summary(categories)

      {:error, reason} ->
        Mix.shell().error("Failed to save: #{inspect(reason)}")
    end
  end

  defp run_workout_demo(output_dir) do
    Mix.shell().info("\n--- Workout Log Demo ---\n")

    # Generate workouts for the past week
    today = Date.utc_today()

    workouts = [
      %{date: Date.add(today, -6), exercise: "Running", duration: 30, calories: 300},
      %{date: Date.add(today, -5), exercise: "Weight Training", duration: 45, calories: 200},
      %{date: Date.add(today, -4), exercise: "Swimming", duration: 40, calories: 350},
      %{date: Date.add(today, -3), exercise: "Cycling", duration: 60, calories: 450},
      %{date: Date.add(today, -2), exercise: "Yoga", duration: 50, calories: 150},
      %{date: Date.add(today, -1), exercise: "Running", duration: 35, calories: 330},
      %{date: today, exercise: "HIIT", duration: 25, calories: 280}
    ]

    Mix.shell().info("Creating workout log with #{length(workouts)} entries...")

    workbook = Excel.workout_log(workouts)
    output_path = Path.join(output_dir, "demo_workout.xlsx")

    case Excel.write_to_file(workbook, output_path) do
      :ok ->
        Mix.shell().info("Workout log saved to: #{output_path}")
        display_workout_summary(workouts)

      {:error, reason} ->
        Mix.shell().error("Failed to save: #{inspect(reason)}")
    end
  end

  defp display_budget_summary(categories) do
    total_budget = Enum.reduce(categories, 0, &(&1.budget + &2))
    total_actual = Enum.reduce(categories, 0, &(&1.actual + &2))
    variance = total_actual - total_budget

    Mix.shell().info("""

    Budget Summary:
    ---------------
    Total Budget:  $#{format_number(total_budget)}
    Total Actual:  $#{format_number(total_actual)}
    Variance:      #{if variance >= 0, do: "+", else: ""}$#{format_number(variance)}

    Features demonstrated:
    - Header row with professional styling
    - Currency formatting
    - Variance calculations with formulas
    - Percentage of budget formulas
    - Totals row with SUM formulas
    - Conditional formatting (green/red variance)
    """)
  end

  defp display_workout_summary(workouts) do
    total_duration = Enum.reduce(workouts, 0, &(&1.duration + &2))
    total_calories = Enum.reduce(workouts, 0, &(&1.calories + &2))

    Mix.shell().info("""

    Workout Summary:
    ----------------
    Total Workouts:   #{length(workouts)}
    Total Duration:   #{total_duration} minutes
    Total Calories:   #{format_number(total_calories)}
    Avg Duration:     #{div(total_duration, length(workouts))} minutes
    Avg Calories:     #{div(total_calories, length(workouts))}

    Features demonstrated:
    - Multi-sheet workbook (Workouts + Summary)
    - Date formatting
    - Summary statistics sheet
    - Cross-sheet formulas (=SUM(Workouts!C2:C8))
    - Frozen header row
    """)
  end

  defp format_number(num) when is_number(num) do
    num
    |> round()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
