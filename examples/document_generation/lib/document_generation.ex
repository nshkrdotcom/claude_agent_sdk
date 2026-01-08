defmodule DocumentGeneration do
  @moduledoc """
  AI-powered document generation using Claude Agent SDK.

  This application demonstrates how to use the Claude Agent SDK to generate
  professional Excel spreadsheets with natural language input. It provides:

  - Budget trackers with automatic variance calculations
  - Workout logs with summary statistics
  - Custom document generation via Claude integration

  ## Quick Start

      # Generate a budget tracker
      {:ok, workbook} = DocumentGeneration.create_budget_tracker([
        %{name: "Housing", budget: 1500, actual: 1450},
        %{name: "Food", budget: 600, actual: 580}
      ])
      DocumentGeneration.save(workbook, "budget.xlsx")

      # Generate a workout log
      {:ok, workbook} = DocumentGeneration.create_workout_log([
        %{date: ~D[2025-01-01], exercise: "Running", duration: 30, calories: 300}
      ])
      DocumentGeneration.save(workbook, "workout.xlsx")

  ## Mix Tasks

  This application provides the following Mix tasks:

      mix generate.budget "Housing $1500, Food $600"
      mix generate.workout "Running 30min 300cal, Weights 45min 200cal"
      mix generate.document --type budget --interactive

  See `mix help generate.budget` for more information.
  """

  alias DocumentGeneration.{Excel, Generator}

  @doc """
  Creates a budget tracker workbook from structured data.

  ## Parameters

    * `categories` - List of budget categories with `:name`, `:budget`, and `:actual` keys

  ## Example

      categories = [
        %{name: "Housing", budget: 1500, actual: 1450},
        %{name: "Food", budget: 600, actual: 580}
      ]

      {:ok, workbook} = DocumentGeneration.create_budget_tracker(categories)
  """
  @spec create_budget_tracker([map()]) :: {:ok, Excel.workbook()}
  def create_budget_tracker(categories) when is_list(categories) do
    workbook = Excel.budget_tracker(categories)
    {:ok, workbook}
  end

  @doc """
  Creates a workout log workbook from structured data.

  ## Parameters

    * `workouts` - List of workout entries with `:date`, `:exercise`, `:duration`, and `:calories` keys

  ## Example

      workouts = [
        %{date: ~D[2025-01-01], exercise: "Running", duration: 30, calories: 300}
      ]

      {:ok, workbook} = DocumentGeneration.create_workout_log(workouts)
  """
  @spec create_workout_log([map()]) :: {:ok, Excel.workbook()}
  def create_workout_log(workouts) when is_list(workouts) do
    workbook = Excel.workout_log(workouts)
    {:ok, workbook}
  end

  @doc """
  Generates a budget tracker from natural language specification.

  Uses parsing to extract budget categories from the specification text.

  ## Example

      spec = "Monthly budget: Housing $1500, Food $600, Transport $400"
      {:ok, workbook} = DocumentGeneration.generate_budget(spec)
  """
  @spec generate_budget(String.t()) :: {:ok, Excel.workbook()} | {:error, term()}
  def generate_budget(spec) when is_binary(spec) do
    Generator.generate_budget(spec)
  end

  @doc """
  Generates a workout log from natural language specification.

  ## Example

      spec = "Workouts: Jan 1 Running 30min 300cal, Jan 2 Weights 45min 200cal"
      {:ok, workbook} = DocumentGeneration.generate_workout_log(spec)
  """
  @spec generate_workout_log(String.t()) :: {:ok, Excel.workbook()} | {:error, term()}
  def generate_workout_log(spec) when is_binary(spec) do
    Generator.generate_workout_log(spec)
  end

  @doc """
  Saves a workbook to a file.

  ## Example

      DocumentGeneration.save(workbook, "output/report.xlsx")
  """
  @spec save(Excel.workbook(), String.t()) :: :ok | {:error, term()}
  def save(workbook, path) when is_binary(path) do
    # Ensure output directory exists
    dir = Path.dirname(path)

    if dir != "." and not File.exists?(dir) do
      File.mkdir_p!(dir)
    end

    Excel.write_to_file(workbook, path)
  end

  @doc """
  Saves a workbook to binary data (in-memory).

  Useful for sending files over HTTP without writing to disk.

  ## Example

      {:ok, {_filename, binary}} = DocumentGeneration.to_binary(workbook)
  """
  @spec to_binary(Excel.workbook()) :: {:ok, {charlist(), binary()}} | {:error, term()}
  def to_binary(workbook) do
    Excel.write_to_binary(workbook)
  end
end
