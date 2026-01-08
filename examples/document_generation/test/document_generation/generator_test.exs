defmodule DocumentGeneration.GeneratorTest do
  @moduledoc """
  Tests for the Claude-powered document generator.
  """
  use ExUnit.Case, async: true

  alias DocumentGeneration.Generator

  describe "parse_budget_spec/1" do
    test "parses valid budget specification" do
      spec = """
      Budget Tracker for January 2025
      Categories:
      - Housing: $1500 budget
      - Food: $600 budget
      - Transport: $400 budget
      """

      result = Generator.parse_budget_spec(spec)
      assert {:ok, parsed} = result
      assert [_ | _] = parsed.categories
    end

    test "parses budget with actual spending" do
      spec = """
      Monthly Budget Report
      Categories:
      - Housing: $1500 budget, $1450 actual
      - Food: $600 budget, $580 actual
      """

      {:ok, parsed} = Generator.parse_budget_spec(spec)
      [housing | _] = parsed.categories

      assert housing.name == "Housing"
      assert housing.budget == 1500
      assert housing.actual == 1450
    end

    test "returns error for empty spec" do
      result = Generator.parse_budget_spec("")
      assert {:error, _reason} = result
    end
  end

  describe "parse_workout_spec/1" do
    test "parses valid workout specification" do
      spec = """
      Workout Log for Week 1
      Workouts:
      - Jan 1: Running, 30 min, 300 cal
      - Jan 2: Weights, 45 min, 200 cal
      """

      result = Generator.parse_workout_spec(spec)
      assert {:ok, parsed} = result
      assert is_list(parsed.workouts)
    end

    test "handles minimal workout spec" do
      spec = """
      Workout Log
      - Running: 30 min
      """

      {:ok, parsed} = Generator.parse_workout_spec(spec)
      assert [_ | _] = parsed.workouts
    end
  end

  describe "build_system_prompt/1" do
    test "builds prompt for budget tracker" do
      prompt = Generator.build_system_prompt(:budget_tracker)
      assert is_binary(prompt)
      assert String.contains?(prompt, "budget")
    end

    test "builds prompt for workout log" do
      prompt = Generator.build_system_prompt(:workout_log)
      assert is_binary(prompt)
      assert String.contains?(prompt, "workout")
    end

    test "builds prompt for custom document" do
      prompt = Generator.build_system_prompt(:custom)
      assert is_binary(prompt)
    end
  end

  describe "format_categories/1" do
    test "formats categories for display" do
      categories = [
        %{name: "Housing", budget: 1500, actual: 1400},
        %{name: "Food", budget: 600, actual: 650}
      ]

      formatted = Generator.format_categories(categories)
      assert is_binary(formatted)
      assert String.contains?(formatted, "Housing")
      # Numbers are formatted with commas
      assert String.contains?(formatted, "1,500")
    end
  end

  describe "format_workouts/1" do
    test "formats workouts for display" do
      workouts = [
        %{date: ~D[2025-01-01], exercise: "Running", duration: 30, calories: 300}
      ]

      formatted = Generator.format_workouts(workouts)
      assert is_binary(formatted)
      assert String.contains?(formatted, "Running")
    end
  end
end
