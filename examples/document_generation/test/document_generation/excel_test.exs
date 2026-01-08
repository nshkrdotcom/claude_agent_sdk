defmodule DocumentGeneration.ExcelTest do
  @moduledoc """
  Tests for the Excel generation module.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias DocumentGeneration.Excel
  alias Elixlsx.{Sheet, Workbook}

  describe "create_workbook/1" do
    test "creates a workbook with the given title" do
      workbook = Excel.create_workbook("Test Workbook")
      assert %Workbook{} = workbook
    end
  end

  describe "add_sheet/2" do
    test "adds a named sheet to the workbook" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data Sheet")

      assert %Workbook{sheets: sheets} = workbook
      assert length(sheets) == 1
      [sheet] = sheets
      assert sheet.name == "Data Sheet"
    end

    test "adds multiple sheets" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Sheet 1")
        |> Excel.add_sheet("Sheet 2")
        |> Excel.add_sheet("Sheet 3")

      assert %Workbook{sheets: sheets} = workbook
      assert length(sheets) == 3
    end
  end

  describe "set_cell/5" do
    test "sets a cell value in the specified sheet" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_cell("Data", "A1", "Hello")

      sheet = get_sheet(workbook, "Data")
      assert sheet != nil
      {_col, _row, value, _opts} = find_cell(sheet, 1, 1)
      assert value == "Hello"
    end

    test "sets cell with styling options" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_cell("Data", "A1", "Bold Text", bold: true)

      sheet = get_sheet(workbook, "Data")
      {_col, _row, _value, opts} = find_cell(sheet, 1, 1)
      assert Keyword.get(opts, :bold) == true
    end

    test "handles numeric values" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_cell("Data", "B2", 42)

      sheet = get_sheet(workbook, "Data")
      {_col, _row, value, _opts} = find_cell(sheet, 2, 2)
      assert value == 42
    end
  end

  describe "set_formula/4" do
    test "sets a formula in the specified cell" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_formula("Data", "C1", "SUM(A1:B1)")

      sheet = get_sheet(workbook, "Data")
      {_col, _row, value, _opts} = find_cell(sheet, 3, 1)
      # Formulas are stored as strings starting with =
      assert value == "=SUM(A1:B1)"
    end
  end

  describe "set_row/4" do
    test "sets an entire row of data" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_row("Data", 1, ["Name", "Age", "City"])

      sheet = get_sheet(workbook, "Data")
      {_col, _row, val1, _} = find_cell(sheet, 1, 1)
      {_col, _row, val2, _} = find_cell(sheet, 2, 1)
      {_col, _row, val3, _} = find_cell(sheet, 3, 1)

      assert val1 == "Name"
      assert val2 == "Age"
      assert val3 == "City"
    end

    test "sets row with styling options" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_row("Data", 1, ["Header 1", "Header 2"], bold: true, bg_color: "#4472C4")

      sheet = get_sheet(workbook, "Data")
      {_col, _row, _value, opts} = find_cell(sheet, 1, 1)
      assert Keyword.get(opts, :bold) == true
      assert Keyword.get(opts, :bg_color) == "#4472C4"
    end
  end

  describe "set_column_width/4" do
    test "sets column width" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_column_width("Data", "A", 25)

      sheet = get_sheet(workbook, "Data")
      # Column widths are stored in col_widths
      assert sheet.col_widths[1] == 25
    end
  end

  describe "set_row_height/4" do
    test "sets row height" do
      workbook =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_row_height("Data", 1, 30)

      sheet = get_sheet(workbook, "Data")
      # Row heights are stored in row_heights
      assert sheet.row_heights[1] == 30
    end
  end

  describe "write_to_file/2" do
    @tag :tmp_dir
    test "writes workbook to file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.xlsx")

      result =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_cell("Data", "A1", "Test Value")
        |> Excel.write_to_file(path)

      assert result == :ok
      assert File.exists?(path)
    end

    test "returns error for invalid path" do
      # Use a path that cannot be created (file as directory)
      # First create a file
      tmp_file = System.tmp_dir!() |> Path.join("test_file_#{:rand.uniform(100_000)}")
      File.write!(tmp_file, "test")

      # Try to write xlsx inside that file (as if it were a directory)
      path = Path.join(tmp_file, "subdir/test.xlsx")

      # Capture stderr to suppress elixlsx Range deprecation warning
      _captured =
        capture_io(:stderr, fn ->
          res =
            Excel.create_workbook("Test")
            |> Excel.add_sheet("Data")
            |> Excel.write_to_file(path)

          send(self(), {:result, res})
        end)

      # Get the actual result from the captured function
      result =
        receive do
          {:result, res} -> res
        after
          1000 -> {:error, :timeout}
        end

      # Clean up
      File.rm(tmp_file)

      assert {:error, _reason} = result
    end
  end

  describe "write_to_binary/1" do
    test "returns binary data" do
      {:ok, {_filename, binary}} =
        Excel.create_workbook("Test")
        |> Excel.add_sheet("Data")
        |> Excel.set_cell("Data", "A1", "Test")
        |> Excel.write_to_binary()

      # XLSX files start with PK signature (ZIP format)
      assert <<0x50, 0x4B, _rest::binary>> = binary
    end
  end

  describe "budget_tracker/1" do
    test "creates a budget tracker workbook" do
      categories = [
        %{name: "Housing", budget: 1500, actual: 1450},
        %{name: "Food", budget: 600, actual: 580},
        %{name: "Transport", budget: 400, actual: 420}
      ]

      workbook = Excel.budget_tracker(categories)

      assert %Workbook{sheets: [_ | _]} = workbook
    end
  end

  describe "workout_log/1" do
    test "creates a workout log workbook" do
      workouts = [
        %{date: ~D[2025-01-01], exercise: "Running", duration: 30, calories: 300},
        %{date: ~D[2025-01-02], exercise: "Weights", duration: 45, calories: 200}
      ]

      workbook = Excel.workout_log(workouts)

      assert %Workbook{sheets: [_ | _]} = workbook
    end
  end

  # Helper functions

  defp get_sheet(%Workbook{sheets: sheets}, name) do
    Enum.find(sheets, fn sheet -> sheet.name == name end)
  end

  defp find_cell(%Sheet{rows: rows}, col, row) do
    rows
    |> Enum.at(row - 1, [])
    |> Enum.at(col - 1, {col, row, nil, []})
    |> normalize_cell(col, row)
  end

  defp normalize_cell({col, row, value, opts}, _col, _row), do: {col, row, value, opts}

  defp normalize_cell(value, col, row) when is_binary(value) or is_number(value),
    do: {col, row, value, []}

  defp normalize_cell([value | opts], col, row), do: {col, row, value, opts}
  defp normalize_cell(nil, col, row), do: {col, row, nil, []}
end
