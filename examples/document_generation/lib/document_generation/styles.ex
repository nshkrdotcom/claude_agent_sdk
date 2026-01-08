defmodule DocumentGeneration.Styles do
  @moduledoc """
  Excel styling utilities for document generation.

  Provides predefined styles for headers, currencies, percentages, and other common
  formatting needs. Also includes utilities for working with Excel cell references.

  ## Example

      alias DocumentGeneration.Styles

      # Apply header style
      Excel.set_cell("Sheet1", "A1", "Title", Styles.header_style())

      # Apply currency formatting
      Excel.set_cell("Sheet1", "B2", 1500, Styles.currency_style())
  """

  @typedoc "Style options for Excel cells"
  @type style_opts :: keyword()

  # Color constants
  @header_blue "#4472C4"
  @header_text_white "#FFFFFF"
  @positive_green "#228B22"
  @negative_red "#DC143C"
  @alt_row_light "#F2F2F2"
  @total_border_color "#000000"

  @doc """
  Returns the default header style with bold text and blue background.

  ## Options

    * `:color` - Background color (default: blue)
    * `:font_color` - Text color (default: white)
    * Any other elixlsx style options

  ## Example

      Styles.header_style()
      #=> [bold: true, bg_color: "#4472C4", font_color: "#FFFFFF"]

      Styles.header_style(color: "#FF0000")
      #=> [bold: true, bg_color: "#FF0000", font_color: "#FFFFFF"]
  """
  @spec header_style(keyword()) :: style_opts()
  def header_style(opts \\ []) do
    bg_color = Keyword.get(opts, :color, @header_blue)
    font_color = Keyword.get(opts, :font_color, @header_text_white)
    extra_opts = Keyword.drop(opts, [:color, :font_color])

    [bold: true, bg_color: bg_color, font_color: font_color]
    |> Keyword.merge(extra_opts)
  end

  @doc """
  Returns currency formatting style.

  ## Options

    * `:symbol` - Currency symbol (default: "$")
    * `:decimals` - Number of decimal places (default: 2)

  ## Example

      Styles.currency_style()
      #=> [num_format: "$#,##0.00"]

      Styles.currency_style(symbol: "EUR", decimals: 0)
      #=> [num_format: "EUR #,##0"]
  """
  @spec currency_style(keyword()) :: style_opts()
  def currency_style(opts \\ []) do
    symbol = Keyword.get(opts, :symbol, "$")
    decimals = Keyword.get(opts, :decimals, 2)

    decimal_format = if decimals > 0, do: "." <> String.duplicate("0", decimals), else: ""
    format = "#{symbol}#,##0#{decimal_format}"

    [num_format: format]
  end

  @doc """
  Returns percentage formatting style.

  ## Options

    * `:decimals` - Number of decimal places (default: 1)

  ## Example

      Styles.percentage_style()
      #=> [num_format: "0.0%"]
  """
  @spec percentage_style(keyword()) :: style_opts()
  def percentage_style(opts \\ []) do
    decimals = Keyword.get(opts, :decimals, 1)
    decimal_format = if decimals > 0, do: "." <> String.duplicate("0", decimals), else: ""

    [num_format: "0#{decimal_format}%"]
  end

  @doc """
  Returns date formatting style.

  ## Options

    * `:format` - Date format string (default: "YYYY-MM-DD")

  ## Example

      Styles.date_style()
      #=> [num_format: "YYYY-MM-DD"]
  """
  @spec date_style(keyword()) :: style_opts()
  def date_style(opts \\ []) do
    format = Keyword.get(opts, :format, "YYYY-MM-DD")
    [num_format: format]
  end

  @doc """
  Returns style for positive values (green text).

  ## Example

      Styles.positive_style()
      #=> [font_color: "#228B22"]
  """
  @spec positive_style() :: style_opts()
  def positive_style do
    [font_color: @positive_green]
  end

  @doc """
  Returns style for negative values (red text).

  ## Example

      Styles.negative_style()
      #=> [font_color: "#DC143C"]
  """
  @spec negative_style() :: style_opts()
  def negative_style do
    [font_color: @negative_red]
  end

  @doc """
  Returns style for total/summary rows with bold text and top border.

  ## Example

      Styles.total_row_style()
      #=> [bold: true, border: [top: [style: :thin, color: "#000000"]]]
  """
  @spec total_row_style() :: style_opts()
  def total_row_style do
    [bold: true, border: [top: [style: :thin, color: @total_border_color]]]
  end

  @doc """
  Returns alternating row style based on row number.

  Even rows get a light gray background, odd rows have no background.

  ## Example

      Styles.alternating_row_style(1)  # Odd row
      #=> []

      Styles.alternating_row_style(2)  # Even row
      #=> [bg_color: "#F2F2F2"]
  """
  @spec alternating_row_style(pos_integer()) :: style_opts()
  def alternating_row_style(row_number) when is_integer(row_number) do
    if rem(row_number, 2) == 0 do
      [bg_color: @alt_row_light]
    else
      []
    end
  end

  @doc """
  Merges two style keyword lists, with the second taking precedence.

  ## Example

      Styles.merge_styles([bold: true, font_size: 12], [bg_color: "#FFF"])
      #=> [bold: true, font_size: 12, bg_color: "#FFF"]
  """
  @spec merge_styles(style_opts(), style_opts()) :: style_opts()
  def merge_styles(base, override) do
    Keyword.merge(base, override)
  end

  @doc """
  Converts a column number (1-based) to Excel column letter(s).

  ## Examples

      Styles.column_letters(1)   #=> "A"
      Styles.column_letters(26)  #=> "Z"
      Styles.column_letters(27)  #=> "AA"
      Styles.column_letters(52)  #=> "AZ"
  """
  @spec column_letters(pos_integer()) :: String.t()
  def column_letters(col) when is_integer(col) and col > 0 do
    do_column_letters(col, "")
  end

  defp do_column_letters(0, acc), do: acc

  defp do_column_letters(col, acc) do
    col_minus_one = col - 1
    letter = <<rem(col_minus_one, 26) + ?A>>
    do_column_letters(div(col_minus_one, 26), letter <> acc)
  end

  @doc """
  Converts Excel column letter(s) to a column number (1-based).

  ## Examples

      Styles.column_number("A")   #=> 1
      Styles.column_number("Z")   #=> 26
      Styles.column_number("AA")  #=> 27
      Styles.column_number("ab")  #=> 28  # Case insensitive
  """
  @spec column_number(String.t()) :: pos_integer()
  def column_number(letters) when is_binary(letters) do
    letters
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc ->
      acc * 26 + (char - ?A + 1)
    end)
  end

  @doc """
  Creates an Excel cell reference from column number and row number.

  ## Examples

      Styles.cell_reference(1, 1)    #=> "A1"
      Styles.cell_reference(3, 5)    #=> "C5"
      Styles.cell_reference(27, 10)  #=> "AA10"
  """
  @spec cell_reference(pos_integer(), pos_integer()) :: String.t()
  def cell_reference(col, row) when is_integer(col) and is_integer(row) do
    column_letters(col) <> Integer.to_string(row)
  end

  @doc """
  Parses an Excel cell reference into column and row numbers.

  ## Examples

      Styles.parse_cell_reference("A1")    #=> {1, 1}
      Styles.parse_cell_reference("C5")    #=> {3, 5}
      Styles.parse_cell_reference("AA10")  #=> {27, 10}
  """
  @spec parse_cell_reference(String.t()) :: {pos_integer(), pos_integer()}
  def parse_cell_reference(ref) when is_binary(ref) do
    ref = String.upcase(ref)
    {letters, digits} = String.split_at(ref, count_letters(ref))
    col = column_number(letters)
    row = String.to_integer(digits)
    {col, row}
  end

  defp count_letters(string) do
    string
    |> String.graphemes()
    |> Enum.take_while(fn char ->
      (char >= "A" and char <= "Z") or (char >= "a" and char <= "z")
    end)
    |> length()
  end
end
