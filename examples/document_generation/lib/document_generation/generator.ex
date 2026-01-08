defmodule DocumentGeneration.Generator do
  @moduledoc """
  AI-powered document generation using Claude Agent SDK.

  This module provides functions to generate Excel documents by leveraging
  Claude to interpret natural language specifications and convert them into
  structured data for document creation.

  ## Example

      # Generate a budget tracker from natural language
      spec = "Create a monthly budget with Housing $1500, Food $600, Transport $400"
      {:ok, workbook} = Generator.generate_budget(spec)

      # Generate a workout log
      workouts_spec = "Log workouts: Jan 1 Running 30min 300cal, Jan 2 Weights 45min"
      {:ok, workbook} = Generator.generate_workout_log(workouts_spec)
  """

  alias DocumentGeneration.Excel

  @typedoc "Budget category structure"
  @type budget_category :: %{
          name: String.t(),
          budget: number(),
          actual: number()
        }

  @typedoc "Workout entry structure"
  @type workout_entry :: %{
          date: Date.t(),
          exercise: String.t(),
          duration: non_neg_integer(),
          calories: non_neg_integer()
        }

  @typedoc "Parsed budget specification"
  @type budget_spec :: %{
          title: String.t(),
          categories: [budget_category()]
        }

  @typedoc "Parsed workout specification"
  @type workout_spec :: %{
          title: String.t(),
          workouts: [workout_entry()]
        }

  @doc """
  Parses a natural language budget specification into structured data.

  ## Example

      spec = \"\"\"
      Budget for January 2025
      Categories:
      - Housing: $1500 budget, $1450 actual
      - Food: $600 budget
      \"\"\"

      {:ok, %{categories: [%{name: "Housing", budget: 1500, actual: 1450}, ...]}} =
        Generator.parse_budget_spec(spec)
  """
  @spec parse_budget_spec(String.t()) :: {:ok, budget_spec()} | {:error, term()}
  def parse_budget_spec(spec) when is_binary(spec) do
    spec = String.trim(spec)

    if spec == "" do
      {:error, :empty_specification}
    else
      categories = extract_budget_categories(spec)

      if categories == [] do
        {:error, :no_categories_found}
      else
        {:ok,
         %{
           title: extract_title(spec, "Budget Tracker"),
           categories: categories
         }}
      end
    end
  end

  @doc """
  Parses a natural language workout specification into structured data.

  ## Example

      spec = \"\"\"
      Workout Log for Week 1
      - Jan 1: Running, 30 min, 300 cal
      - Jan 2: Weights, 45 min, 200 cal
      \"\"\"

      {:ok, %{workouts: [%{exercise: "Running", duration: 30, ...}, ...]}} =
        Generator.parse_workout_spec(spec)
  """
  @spec parse_workout_spec(String.t()) :: {:ok, workout_spec()} | {:error, term()}
  def parse_workout_spec(spec) when is_binary(spec) do
    spec = String.trim(spec)

    if spec == "" do
      {:error, :empty_specification}
    else
      workouts = extract_workouts(spec)

      {:ok,
       %{
         title: extract_title(spec, "Workout Log"),
         workouts: workouts
       }}
    end
  end

  @doc """
  Builds a system prompt for the specified document type.

  ## Document Types

    * `:budget_tracker` - Prompts for budget/financial tracking
    * `:workout_log` - Prompts for fitness/workout logging
    * `:custom` - Generic document generation prompt

  ## Example

      prompt = Generator.build_system_prompt(:budget_tracker)
  """
  @spec build_system_prompt(atom()) :: String.t()
  def build_system_prompt(:budget_tracker) do
    """
    You are an expert at creating budget tracking spreadsheets.
    Parse the user's budget requirements and extract:
    - Budget categories (name, budgeted amount, actual spending if provided)
    - Any notes or special requirements

    Format your response as structured data that can be used to generate an Excel file.
    Include suggestions for improving budget organization if appropriate.
    """
  end

  def build_system_prompt(:workout_log) do
    """
    You are an expert at creating workout tracking spreadsheets.
    Parse the user's workout data and extract:
    - Workout entries (date, exercise type, duration, calories burned)
    - Any fitness goals or targets mentioned

    Format your response as structured data that can be used to generate an Excel file.
    Include summary statistics suggestions (totals, averages, trends).
    """
  end

  def build_system_prompt(:custom) do
    """
    You are an expert at creating professional spreadsheets.
    Parse the user's requirements and generate appropriate structured data
    that can be used to create an Excel workbook with proper formatting,
    formulas, and multiple sheets if needed.
    """
  end

  @doc """
  Formats budget categories for display or logging.

  ## Example

      categories = [%{name: "Housing", budget: 1500, actual: 1400}]
      formatted = Generator.format_categories(categories)
      # => "Housing: Budget $1,500 | Actual $1,400 | Variance $100"
  """
  @spec format_categories([budget_category()]) :: String.t()
  def format_categories(categories) when is_list(categories) do
    Enum.map_join(categories, "\n", fn cat ->
      name = Map.get(cat, :name, "Unknown")
      budget = Map.get(cat, :budget, 0)
      actual = Map.get(cat, :actual, 0)
      variance = actual - budget

      variance_str =
        if variance >= 0 do
          "+$#{format_number(variance)}"
        else
          "-$#{format_number(abs(variance))}"
        end

      "#{name}: Budget $#{format_number(budget)} | Actual $#{format_number(actual)} | Variance #{variance_str}"
    end)
  end

  @doc """
  Formats workouts for display or logging.

  ## Example

      workouts = [%{date: ~D[2025-01-01], exercise: "Running", duration: 30, calories: 300}]
      formatted = Generator.format_workouts(workouts)
      # => "2025-01-01: Running - 30 min, 300 cal"
  """
  @spec format_workouts([workout_entry()]) :: String.t()
  def format_workouts(workouts) when is_list(workouts) do
    Enum.map_join(workouts, "\n", fn workout ->
      date = Map.get(workout, :date, Date.utc_today()) |> Date.to_iso8601()
      exercise = Map.get(workout, :exercise, "Unknown")
      duration = Map.get(workout, :duration, 0)
      calories = Map.get(workout, :calories, 0)

      "#{date}: #{exercise} - #{duration} min, #{calories} cal"
    end)
  end

  @doc """
  Generates a budget tracker Excel workbook from a specification.

  This function parses the specification and creates a formatted Excel workbook
  with budget categories, formulas for variance calculations, and professional styling.

  ## Example

      spec = "Monthly budget: Housing $1500, Food $600, Transport $400"
      {:ok, workbook} = Generator.generate_budget(spec)
      Excel.write_to_file(workbook, "budget.xlsx")
  """
  @spec generate_budget(String.t()) :: {:ok, Excel.workbook()} | {:error, term()}
  def generate_budget(spec) when is_binary(spec) do
    case parse_budget_spec(spec) do
      {:ok, %{categories: categories}} ->
        workbook = Excel.budget_tracker(categories)
        {:ok, workbook}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a workout log Excel workbook from a specification.

  ## Example

      spec = "Workouts: Jan 1 Running 30min 300cal, Jan 2 Weights 45min 200cal"
      {:ok, workbook} = Generator.generate_workout_log(spec)
      Excel.write_to_file(workbook, "workouts.xlsx")
  """
  @spec generate_workout_log(String.t()) :: {:ok, Excel.workbook()} | {:error, term()}
  def generate_workout_log(spec) when is_binary(spec) do
    case parse_workout_spec(spec) do
      {:ok, %{workouts: workouts}} ->
        workbook = Excel.workout_log(workouts)
        {:ok, workbook}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Parsing Functions
  # ============================================================================

  defp extract_title(spec, default) do
    # Try to extract title from first line
    case String.split(spec, "\n", parts: 2) do
      [first_line | _] ->
        first_line = String.trim(first_line)

        # Remove common prefixes
        first_line
        |> String.replace(~r/^(Budget|Workout|Report|Log)\s*(for|:)?\s*/i, "")
        |> String.trim()
        |> case do
          "" -> default
          title -> title
        end

      _ ->
        default
    end
  end

  defp extract_budget_categories(spec) do
    # Match patterns like:
    # - Housing: $1500 budget, $1450 actual
    # - Food: $600 budget
    # Housing $1500
    regex =
      ~r/[-*]?\s*(\w+(?:\s+\w+)*)\s*[:]\s*\$?([\d,]+)\s*(?:budget)?(?:,?\s*\$?([\d,]+)\s*(?:actual)?)?/i

    Regex.scan(regex, spec)
    |> Enum.map(fn match ->
      name = Enum.at(match, 1, "Unknown") |> String.trim()
      budget = Enum.at(match, 2, "0") |> parse_number()
      actual = Enum.at(match, 3, nil)

      actual_value =
        if actual && actual != "" do
          parse_number(actual)
        else
          budget
        end

      %{name: name, budget: budget, actual: actual_value}
    end)
    |> case do
      [] -> extract_simple_budget_categories(spec)
      categories -> categories
    end
  end

  defp extract_simple_budget_categories(spec) do
    # Simpler pattern: Category $amount
    regex = ~r/(\w+(?:\s+\w+)*)\s+\$?([\d,]+)/

    Regex.scan(regex, spec)
    |> Enum.map(fn match ->
      name = Enum.at(match, 1, "Unknown") |> String.trim()
      budget = Enum.at(match, 2, "0") |> parse_number()

      %{name: name, budget: budget, actual: budget}
    end)
  end

  defp extract_workouts(spec) do
    # Match patterns like:
    # - Jan 1: Running, 30 min, 300 cal
    # Jan 1 Running 30min 300cal
    lines =
      spec
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(fn line ->
        String.match?(line, ~r/\d+\s*(min|minutes|cal|calories)/i) or
          String.match?(line, ~r/^\s*[-*]/)
      end)

    lines
    |> Enum.map(&parse_workout_line/1)
    |> Enum.filter(& &1)
  end

  defp parse_workout_line(line) do
    # Try to extract date
    date = extract_date(line)

    # Try to extract exercise name (first word after date or dash)
    exercise =
      line
      |> String.replace(~r/^[-*]\s*/, "")
      |> String.replace(
        ~r/\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*\d+[,:]?\s*/i,
        ""
      )
      |> String.replace(~r/\d{4}-\d{2}-\d{2}[,:]?\s*/, "")
      |> String.split(~r/[,\s]+/)
      |> Enum.at(0, "Unknown")
      |> String.trim()

    # Extract duration
    duration =
      case Regex.run(~r/(\d+)\s*(min|minutes)/i, line) do
        [_, num, _] -> parse_number(num)
        _ -> 0
      end

    # Extract calories
    calories =
      case Regex.run(~r/(\d+)\s*(cal|calories)/i, line) do
        [_, num, _] -> parse_number(num)
        _ -> 0
      end

    if exercise != "" and (duration > 0 or calories > 0) do
      %{
        date: date,
        exercise: exercise,
        duration: duration,
        calories: calories
      }
    else
      nil
    end
  end

  defp extract_date(line) do
    # Try ISO format first
    case Regex.run(~r/(\d{4}-\d{2}-\d{2})/, line) do
      [_, date_str] ->
        parse_iso_date(date_str)

      _ ->
        # Try "Jan 1" format
        parse_month_day_date(line)
    end
  end

  defp parse_iso_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  defp parse_month_day_date(line) do
    case Regex.run(~r/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*(\d+)/i, line) do
      [_, month_str, day_str] ->
        build_date_from_month_day(month_str, day_str)

      _ ->
        Date.utc_today()
    end
  end

  defp build_date_from_month_day(month_str, day_str) do
    month = month_to_number(month_str)
    day = parse_number(day_str)
    year = Date.utc_today().year

    case Date.new(year, month, day) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  @month_map %{
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12
  }

  defp month_to_number(month) do
    key =
      month
      |> String.downcase()
      |> String.slice(0, 3)

    Map.get(@month_map, key, 1)
  end

  defp parse_number(str) when is_binary(str) do
    str
    |> String.replace(",", "")
    |> String.trim()
    |> Integer.parse()
    |> case do
      {num, _} -> num
      :error -> 0
    end
  end

  defp parse_number(num) when is_number(num), do: num
  defp parse_number(_), do: 0

  defp format_number(num) when is_number(num) do
    num
    |> round()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
