defmodule DocumentGeneration.Excel do
  @moduledoc """
  Excel workbook generation using elixlsx.

  Provides a fluent API for creating Excel spreadsheets with multiple sheets,
  formulas, styling, and more.

  ## Example

      alias DocumentGeneration.Excel

      Excel.create_workbook("Monthly Report")
      |> Excel.add_sheet("Summary")
      |> Excel.set_row("Summary", 1, ["Category", "Budget", "Actual", "Variance"], bold: true)
      |> Excel.set_row("Summary", 2, ["Housing", 1500, 1450])
      |> Excel.set_formula("Summary", "D2", "C2-B2")
      |> Excel.write_to_file("report.xlsx")
  """

  alias DocumentGeneration.Styles
  alias Elixlsx.{Sheet, Workbook}

  @typedoc "Excel workbook"
  @type workbook :: %Workbook{}

  @typedoc "Cell value types"
  @type cell_value :: String.t() | number() | boolean() | Date.t() | DateTime.t() | nil

  @doc """
  Creates a new workbook with an optional title.

  The title is used as metadata but does not appear in the workbook itself.

  ## Example

      workbook = Excel.create_workbook("Q1 Report")
  """
  @spec create_workbook(String.t()) :: workbook()
  def create_workbook(_title \\ "Workbook") do
    %Workbook{}
  end

  @doc """
  Adds a new sheet with the given name to the workbook.

  ## Example

      workbook
      |> Excel.add_sheet("Data")
      |> Excel.add_sheet("Summary")
  """
  @spec add_sheet(workbook(), String.t()) :: workbook()
  def add_sheet(%Workbook{sheets: sheets} = workbook, name) when is_binary(name) do
    sheet = Sheet.with_name(name)
    # Directly update sheets list to avoid dialyzer issues with
    # Workbook.append_sheet/2's typespec requiring non-empty sheets
    %{workbook | sheets: sheets ++ [sheet]}
  end

  @doc """
  Sets a cell value in the specified sheet at the given cell reference.

  ## Parameters

    * `workbook` - The workbook to modify
    * `sheet_name` - Name of the sheet
    * `cell_ref` - Cell reference like "A1" or "B2"
    * `value` - The value to set
    * `opts` - Optional styling options

  ## Example

      workbook
      |> Excel.set_cell("Sheet1", "A1", "Hello", bold: true)
      |> Excel.set_cell("Sheet1", "B1", 42)
  """
  @spec set_cell(workbook(), String.t(), String.t(), cell_value(), keyword()) :: workbook()
  def set_cell(%Workbook{} = workbook, sheet_name, cell_ref, value, opts \\ []) do
    update_sheet(workbook, sheet_name, fn sheet ->
      Sheet.set_cell(sheet, cell_ref, value, opts)
    end)
  end

  @doc """
  Sets a formula in the specified cell.

  The formula should not include the leading "=" sign - it will be added automatically.

  ## Example

      workbook
      |> Excel.set_formula("Sheet1", "C1", "SUM(A1:B1)")
      |> Excel.set_formula("Sheet1", "D1", "C1*1.1")
  """
  @spec set_formula(workbook(), String.t(), String.t(), String.t(), keyword()) :: workbook()
  def set_formula(%Workbook{} = workbook, sheet_name, cell_ref, formula, opts \\ []) do
    formula_with_equals =
      if String.starts_with?(formula, "=") do
        formula
      else
        "=" <> formula
      end

    set_cell(workbook, sheet_name, cell_ref, formula_with_equals, opts)
  end

  @doc """
  Sets an entire row of data starting from column A.

  ## Parameters

    * `workbook` - The workbook to modify
    * `sheet_name` - Name of the sheet
    * `row_num` - Row number (1-based)
    * `values` - List of values for the row
    * `opts` - Optional styling options applied to all cells in the row

  ## Example

      workbook
      |> Excel.set_row("Sheet1", 1, ["Name", "Age", "City"], bold: true)
      |> Excel.set_row("Sheet1", 2, ["Alice", 30, "NYC"])
  """
  @spec set_row(workbook(), String.t(), pos_integer(), [cell_value()], keyword()) :: workbook()
  def set_row(%Workbook{} = workbook, sheet_name, row_num, values, opts \\ [])
      when is_integer(row_num) and is_list(values) do
    values
    |> Enum.with_index(1)
    |> Enum.reduce(workbook, fn {value, col}, wb ->
      cell_ref = Styles.cell_reference(col, row_num)
      set_cell(wb, sheet_name, cell_ref, value, opts)
    end)
  end

  @doc """
  Sets the width of a column.

  ## Example

      workbook
      |> Excel.set_column_width("Sheet1", "A", 25)
      |> Excel.set_column_width("Sheet1", "B", 15)
  """
  @spec set_column_width(workbook(), String.t(), String.t(), number()) :: workbook()
  def set_column_width(%Workbook{} = workbook, sheet_name, column, width)
      when is_binary(column) and is_number(width) do
    update_sheet(workbook, sheet_name, fn sheet ->
      Sheet.set_col_width(sheet, column, width)
    end)
  end

  @doc """
  Sets the height of a row.

  ## Example

      workbook
      |> Excel.set_row_height("Sheet1", 1, 30)
  """
  @spec set_row_height(workbook(), String.t(), pos_integer(), number()) :: workbook()
  def set_row_height(%Workbook{} = workbook, sheet_name, row_num, height)
      when is_integer(row_num) and is_number(height) do
    update_sheet(workbook, sheet_name, fn sheet ->
      Sheet.set_row_height(sheet, row_num, height)
    end)
  end

  @doc """
  Freezes panes at the specified row and column.

  Rows above and columns to the left of the specified position will be frozen.

  ## Example

      # Freeze first row
      workbook |> Excel.freeze_panes("Sheet1", 1, 0)

      # Freeze first row and first column
      workbook |> Excel.freeze_panes("Sheet1", 1, 1)
  """
  @spec freeze_panes(workbook(), String.t(), non_neg_integer(), non_neg_integer()) :: workbook()
  def freeze_panes(%Workbook{} = workbook, sheet_name, row, col)
      when is_integer(row) and is_integer(col) do
    update_sheet(workbook, sheet_name, fn sheet ->
      Sheet.set_pane_freeze(sheet, row, col)
    end)
  end

  @doc """
  Writes the workbook to a file.

  ## Example

      workbook
      |> Excel.write_to_file("output/report.xlsx")
  """
  @spec write_to_file(workbook(), String.t()) :: :ok | {:error, term()}
  def write_to_file(%Workbook{} = workbook, path) when is_binary(path) do
    case Elixlsx.write_to(workbook, path) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes the workbook to a binary (in-memory).

  Returns `{:ok, {filename, binary}}` on success.

  ## Example

      {:ok, {_filename, binary}} = workbook |> Excel.write_to_binary()
      File.write!("report.xlsx", binary)
  """
  @spec write_to_binary(workbook()) :: {:ok, {charlist(), binary()}} | {:error, term()}
  def write_to_binary(%Workbook{} = workbook) do
    Elixlsx.write_to_memory(workbook, "workbook.xlsx")
  end

  # ============================================================================
  # Predefined Document Types
  # ============================================================================

  @doc """
  Creates a budget tracker workbook from a list of category data.

  ## Parameters

    * `categories` - List of maps with `:name`, `:budget`, and optionally `:actual` keys

  ## Example

      categories = [
        %{name: "Housing", budget: 1500, actual: 1450},
        %{name: "Food", budget: 600, actual: 580}
      ]

      workbook = Excel.budget_tracker(categories)
  """
  @spec budget_tracker([map()]) :: workbook()
  def budget_tracker(categories) when is_list(categories) do
    create_workbook("Budget Tracker")
    |> add_sheet("Budget")
    |> setup_budget_headers()
    |> add_budget_data(categories)
    |> add_budget_totals(length(categories))
    |> style_budget_sheet(length(categories))
  end

  defp setup_budget_headers(workbook) do
    headers = ["Category", "Budget", "Actual", "Variance", "% of Budget"]

    workbook
    |> set_row("Budget", 1, headers, Styles.header_style())
    |> set_row_height("Budget", 1, 25)
    |> freeze_panes("Budget", 1, 0)
    |> set_column_width("Budget", "A", 20)
    |> set_column_width("Budget", "B", 15)
    |> set_column_width("Budget", "C", 15)
    |> set_column_width("Budget", "D", 15)
    |> set_column_width("Budget", "E", 15)
  end

  defp add_budget_data(workbook, categories) do
    categories
    |> Enum.with_index(2)
    |> Enum.reduce(workbook, fn {cat, row}, wb ->
      name = Map.get(cat, :name, "Unknown")
      budget = Map.get(cat, :budget, 0)
      actual = Map.get(cat, :actual, 0)

      wb
      |> set_cell("Budget", Styles.cell_reference(1, row), name)
      |> set_cell("Budget", Styles.cell_reference(2, row), budget, Styles.currency_style())
      |> set_cell("Budget", Styles.cell_reference(3, row), actual, Styles.currency_style())
      |> set_formula(
        "Budget",
        Styles.cell_reference(4, row),
        "C#{row}-B#{row}",
        variance_style(actual - budget)
      )
      |> set_formula(
        "Budget",
        Styles.cell_reference(5, row),
        "C#{row}/B#{row}",
        Styles.percentage_style()
      )
    end)
  end

  defp add_budget_totals(workbook, category_count) do
    total_row = category_count + 2

    workbook
    |> set_cell("Budget", Styles.cell_reference(1, total_row), "TOTAL", Styles.total_row_style())
    |> set_formula(
      "Budget",
      Styles.cell_reference(2, total_row),
      "SUM(B2:B#{total_row - 1})",
      Styles.merge_styles(Styles.currency_style(), Styles.total_row_style())
    )
    |> set_formula(
      "Budget",
      Styles.cell_reference(3, total_row),
      "SUM(C2:C#{total_row - 1})",
      Styles.merge_styles(Styles.currency_style(), Styles.total_row_style())
    )
    |> set_formula(
      "Budget",
      Styles.cell_reference(4, total_row),
      "SUM(D2:D#{total_row - 1})",
      Styles.merge_styles(Styles.currency_style(), Styles.total_row_style())
    )
    |> set_formula(
      "Budget",
      Styles.cell_reference(5, total_row),
      "C#{total_row}/B#{total_row}",
      Styles.merge_styles(Styles.percentage_style(), Styles.total_row_style())
    )
  end

  defp style_budget_sheet(workbook, category_count) do
    # Apply alternating row styles
    # Note: elixlsx doesn't support modifying existing cell styles easily,
    # so this is a placeholder for more advanced styling
    Enum.reduce(2..(category_count + 1), workbook, fn row, wb ->
      maybe_apply_row_style(wb, row)
    end)
  end

  defp maybe_apply_row_style(workbook, row) do
    style = Styles.alternating_row_style(row)

    if style != [] do
      # In a full implementation, we would merge styles here
      # For now, we just return the workbook unchanged
      workbook
    else
      workbook
    end
  end

  defp variance_style(variance) when variance >= 0,
    do: Styles.merge_styles(Styles.currency_style(), Styles.positive_style())

  defp variance_style(_variance),
    do: Styles.merge_styles(Styles.currency_style(), Styles.negative_style())

  @doc """
  Creates a workout log workbook from a list of workout data.

  ## Parameters

    * `workouts` - List of maps with `:date`, `:exercise`, `:duration`, and optionally `:calories` keys

  ## Example

      workouts = [
        %{date: ~D[2025-01-01], exercise: "Running", duration: 30, calories: 300},
        %{date: ~D[2025-01-02], exercise: "Weights", duration: 45, calories: 200}
      ]

      workbook = Excel.workout_log(workouts)
  """
  @spec workout_log([map()]) :: workbook()
  def workout_log(workouts) when is_list(workouts) do
    create_workbook("Workout Log")
    |> add_sheet("Workouts")
    |> add_sheet("Summary")
    |> setup_workout_headers()
    |> add_workout_data(workouts)
    |> add_workout_summary(length(workouts))
  end

  defp setup_workout_headers(workbook) do
    headers = ["Date", "Exercise", "Duration (min)", "Calories"]

    workbook
    |> set_row("Workouts", 1, headers, Styles.header_style())
    |> set_row_height("Workouts", 1, 25)
    |> freeze_panes("Workouts", 1, 0)
    |> set_column_width("Workouts", "A", 15)
    |> set_column_width("Workouts", "B", 20)
    |> set_column_width("Workouts", "C", 18)
    |> set_column_width("Workouts", "D", 12)
  end

  defp add_workout_data(workbook, workouts) do
    workouts
    |> Enum.with_index(2)
    |> Enum.reduce(workbook, fn {workout, row}, wb ->
      date = Map.get(workout, :date, Date.utc_today())
      exercise = Map.get(workout, :exercise, "Unknown")
      duration = Map.get(workout, :duration, 0)
      calories = Map.get(workout, :calories, 0)

      date_value = format_date(date)

      wb
      |> set_cell("Workouts", Styles.cell_reference(1, row), date_value, Styles.date_style())
      |> set_cell("Workouts", Styles.cell_reference(2, row), exercise)
      |> set_cell("Workouts", Styles.cell_reference(3, row), duration)
      |> set_cell("Workouts", Styles.cell_reference(4, row), calories)
    end)
  end

  defp add_workout_summary(workbook, workout_count) do
    last_row = workout_count + 1

    summary_data = [
      ["Workout Summary", ""],
      ["", ""],
      ["Total Workouts", workout_count],
      ["Total Duration (min)", "=SUM(Workouts!C2:C#{last_row})"],
      ["Total Calories", "=SUM(Workouts!D2:D#{last_row})"],
      ["", ""],
      ["Average Duration", "=AVERAGE(Workouts!C2:C#{last_row})"],
      ["Average Calories", "=AVERAGE(Workouts!D2:D#{last_row})"]
    ]

    workbook
    |> set_row("Summary", 1, ["Workout Summary", ""], Styles.header_style())
    |> set_column_width("Summary", "A", 25)
    |> set_column_width("Summary", "B", 15)
    |> add_summary_rows(summary_data)
  end

  defp add_summary_rows(workbook, rows) do
    rows
    |> Enum.with_index(1)
    |> Enum.reduce(workbook, fn {[label, value], row}, wb ->
      wb
      |> set_cell("Summary", Styles.cell_reference(1, row), label)
      |> set_cell_or_formula("Summary", Styles.cell_reference(2, row), value)
    end)
  end

  defp set_cell_or_formula(workbook, sheet_name, cell_ref, value) when is_binary(value) do
    if String.starts_with?(value, "=") do
      set_formula(workbook, sheet_name, cell_ref, String.slice(value, 1..-1//1))
    else
      set_cell(workbook, sheet_name, cell_ref, value)
    end
  end

  defp set_cell_or_formula(workbook, sheet_name, cell_ref, value) do
    set_cell(workbook, sheet_name, cell_ref, value)
  end

  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(date) when is_binary(date), do: date
  defp format_date(_), do: Date.to_iso8601(Date.utc_today())

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp update_sheet(%Workbook{sheets: sheets} = workbook, sheet_name, update_fn) do
    updated_sheets =
      Enum.map(sheets, fn sheet ->
        if sheet.name == sheet_name do
          update_fn.(sheet)
        else
          sheet
        end
      end)

    %{workbook | sheets: updated_sheets}
  end
end
