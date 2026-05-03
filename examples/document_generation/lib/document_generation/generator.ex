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

  alias ClaudeAgentSDK.StringScan
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

        first_line
        |> strip_title_prefix()
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
    spec
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_budget_line/1)
    |> case do
      [] -> extract_simple_budget_categories(spec)
      categories -> categories
    end
  end

  defp extract_simple_budget_categories(spec) do
    spec
    |> String.split(["\n", ","], trim: true)
    |> Enum.flat_map(&parse_simple_budget_segment/1)
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
        workout_metric?(line) or bullet_line?(line)
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
      |> strip_bullet()
      |> strip_known_date()
      |> String.split([",", " ", "\t"], trim: true)
      |> Enum.at(0, "Unknown")
      |> String.trim()

    # Extract duration
    duration = extract_metric(line, ["min", "minutes"])

    # Extract calories
    calories = extract_metric(line, ["cal", "calories"])

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
    case first_iso_date(line) do
      {:ok, date_str} ->
        parse_iso_date(date_str)

      :error ->
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
    case first_month_day(line) do
      {:ok, month_str, day_str} ->
        build_date_from_month_day(month_str, day_str)

      :error ->
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
    StringScan.grouped_number(num)
  end

  defp strip_title_prefix(value) do
    case String.split(value, " ", parts: 2, trim: true) do
      [first, rest] ->
        prefix = first |> String.trim_trailing(":") |> String.downcase()

        if prefix in ["budget", "workout", "report", "log"] do
          rest
          |> String.trim_leading()
          |> strip_optional_for()
          |> String.trim_leading(":")
        else
          value
        end

      _ ->
        value
    end
  end

  defp strip_optional_for(value) do
    if String.starts_with?(String.downcase(value), "for ") do
      String.slice(value, 4, String.length(value) - 4)
    else
      value
    end
  end

  defp parse_budget_line(line) do
    line
    |> strip_bullet()
    |> parse_budget_segment_with_colon()
  end

  defp parse_budget_segment_with_colon(segment) do
    case String.split(segment, ":", parts: 2) do
      [name, amounts] ->
        budget = first_number(amounts)
        actual = number_after_word(amounts, "actual") || second_number(amounts) || budget

        if budget > 0 do
          [%{name: String.trim(name), budget: budget, actual: actual}]
        else
          []
        end

      _ ->
        []
    end
  end

  defp parse_simple_budget_segment(segment) do
    segment = strip_bullet(segment)

    case first_number_with_prefix(segment) do
      {:ok, name, amount} ->
        [%{name: normalize_category_name(name), budget: amount, actual: amount}]

      :error ->
        []
    end
  end

  defp normalize_category_name(""), do: "Unknown"
  defp normalize_category_name(name), do: String.trim(name)

  defp workout_metric?(line), do: extract_metric(line, ["min", "minutes", "cal", "calories"]) > 0

  defp bullet_line?(line) do
    line
    |> String.trim_leading()
    |> String.starts_with?(["-", "*"])
  end

  defp strip_bullet(line) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, ["-", "*"]) do
      trimmed
      |> String.slice(1, String.length(trimmed) - 1)
      |> String.trim_leading()
    else
      trimmed
    end
  end

  defp strip_known_date(line) do
    line
    |> strip_iso_date_prefix()
    |> strip_month_day_prefix()
    |> trim_leading_chars([",", ":", " "])
  end

  defp strip_iso_date_prefix(line) do
    case first_iso_date(line) do
      {:ok, date} ->
        String.replace_prefix(line, date, "")

      :error ->
        line
    end
  end

  defp strip_month_day_prefix(line) do
    case first_month_day(line) do
      {:ok, month, day} ->
        line
        |> String.split(" ", trim: true)
        |> drop_leading_month_day(month, day)
        |> Enum.join(" ")

      :error ->
        line
    end
  end

  defp drop_leading_month_day([month, day | rest], expected_month, expected_day) do
    month_token = month |> String.trim_trailing(",") |> String.downcase() |> String.slice(0, 3)
    day_token = trim_trailing_chars(day, [",", ":"])

    if month_token == String.downcase(expected_month) and day_token == expected_day do
      rest
    else
      [month, day | rest]
    end
  end

  defp drop_leading_month_day(tokens, _month, _day), do: tokens

  defp extract_metric(line, units) do
    tokens = measurement_tokens(line)

    tokens
    |> Enum.with_index()
    |> Enum.find_value(0, fn {token, index} ->
      case Integer.parse(token) do
        {number, unit} ->
          cond do
            unit in units ->
              number

            unit == "" ->
              next = Enum.at(tokens, index + 1, "")
              if next in units, do: number, else: nil

            true ->
              nil
          end

        _ ->
          nil
      end
    end)
  end

  defp measurement_tokens(line) do
    line
    |> String.downcase()
    |> String.split([" ", ",", ":", "\t"], trim: true)
    |> Enum.map(&String.trim(&1, "."))
  end

  defp first_iso_date(line) do
    line
    |> String.split([" ", ",", ":", "\t"], trim: true)
    |> Enum.find_value(:error, fn token ->
      candidate = String.slice(token, 0, 10)

      case Date.from_iso8601(candidate) do
        {:ok, _date} -> {:ok, candidate}
        _ -> nil
      end
    end)
  end

  defp first_month_day(line) do
    tokens = String.split(line, [" ", ",", ":"], trim: true)

    tokens
    |> Enum.with_index()
    |> Enum.find_value(:error, fn {token, index} ->
      month = token |> String.downcase() |> String.slice(0, 3)
      next = Enum.at(tokens, index + 1, "")

      if Map.has_key?(@month_map, month) and integer_string?(next) do
        {:ok, month, next}
      else
        nil
      end
    end)
  end

  defp first_number(text) do
    case first_number_with_prefix(text) do
      {:ok, _prefix, number} -> number
      :error -> 0
    end
  end

  defp second_number(text) do
    case text |> numeric_segments() |> Enum.at(1) do
      {number, _offset} -> number
      nil -> nil
    end
  end

  defp number_after_word(text, word) do
    tokens = String.split(text, [" ", ",", ":"], trim: true)

    tokens
    |> Enum.with_index()
    |> Enum.find_value(fn {token, index} ->
      if String.downcase(token) == word do
        tokens
        |> Enum.drop(index + 1)
        |> Enum.find_value(&parse_number_token/1)
      end
    end)
  end

  defp first_number_with_prefix(text) do
    case numeric_segments(text) do
      [{number, offset} | _rest] ->
        name = text |> binary_part(0, offset) |> String.trim() |> String.trim_trailing("$")
        {:ok, name, number}

      [] ->
        :error
    end
  end

  defp numeric_segments(text), do: do_numeric_segments(text, 0, [])

  defp do_numeric_segments("", _offset, acc), do: Enum.reverse(acc)

  defp do_numeric_segments(<<char::binary-size(1), rest::binary>>, offset, acc) do
    if digit?(char) do
      {raw, remaining} = take_number(<<char::binary-size(1), rest::binary>>)
      number = parse_number(raw)
      next_offset = offset + byte_size(raw)
      do_numeric_segments(remaining, next_offset, [{number, offset} | acc])
    else
      do_numeric_segments(rest, offset + 1, acc)
    end
  end

  defp take_number(text), do: do_take_number(text, "")

  defp do_take_number(<<char::binary-size(1), rest::binary>>, acc) do
    if digit_or_comma?(char) do
      do_take_number(rest, acc <> char)
    else
      {acc, rest}
    end
  end

  defp do_take_number("", acc), do: {acc, ""}

  defp parse_number_token(token) do
    cleaned =
      token
      |> String.trim_leading("$")
      |> trim_trailing_chars([".", ","])

    case Integer.parse(String.replace(cleaned, ",", "")) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer_string?(value), do: parse_number_token(value) != nil

  defp trim_leading_chars(value, chars) do
    value
    |> String.graphemes()
    |> Enum.drop_while(&(&1 in chars))
    |> Enum.join()
  end

  defp trim_trailing_chars(value, chars) do
    value
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 in chars))
    |> Enum.reverse()
    |> Enum.join()
  end

  defp digit?(<<char::utf8>>), do: char >= ?0 and char <= ?9
  defp digit?(_char), do: false

  defp digit_or_comma?(<<char::utf8>>), do: digit?(<<char::utf8>>) or char == ?,
  defp digit_or_comma?(_char), do: false
end
