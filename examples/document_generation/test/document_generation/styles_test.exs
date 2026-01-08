defmodule DocumentGeneration.StylesTest do
  @moduledoc """
  Tests for Excel styling utilities.
  """
  use ExUnit.Case, async: true

  alias DocumentGeneration.Styles

  describe "header_style/0" do
    test "returns header style options" do
      style = Styles.header_style()
      assert is_list(style)
      assert Keyword.get(style, :bold) == true
    end
  end

  describe "header_style/1" do
    test "accepts custom color" do
      style = Styles.header_style(color: "#FF0000")
      assert Keyword.get(style, :bg_color) == "#FF0000"
    end

    test "preserves bold with custom options" do
      style = Styles.header_style(font_size: 14)
      assert Keyword.get(style, :bold) == true
      assert Keyword.get(style, :font_size) == 14
    end
  end

  describe "currency_style/0" do
    test "returns currency format options" do
      style = Styles.currency_style()
      assert is_list(style)
      assert Keyword.has_key?(style, :num_format)
    end
  end

  describe "currency_style/1" do
    test "accepts custom currency symbol" do
      style = Styles.currency_style(symbol: "EUR")
      # The format should contain the symbol
      format = Keyword.get(style, :num_format)
      assert String.contains?(format, "EUR")
    end
  end

  describe "percentage_style/0" do
    test "returns percentage format options" do
      style = Styles.percentage_style()
      format = Keyword.get(style, :num_format)
      assert String.contains?(format, "%")
    end
  end

  describe "date_style/0" do
    test "returns date format options" do
      style = Styles.date_style()
      assert is_list(style)
      assert Keyword.has_key?(style, :num_format)
    end
  end

  describe "positive_style/0" do
    test "returns green color style" do
      style = Styles.positive_style()
      color = Keyword.get(style, :font_color)
      # Green typically has high G value
      assert color != nil
    end
  end

  describe "negative_style/0" do
    test "returns red color style" do
      style = Styles.negative_style()
      color = Keyword.get(style, :font_color)
      # Red typically has high R value
      assert color != nil
    end
  end

  describe "total_row_style/0" do
    test "returns total row style with border" do
      style = Styles.total_row_style()
      assert Keyword.get(style, :bold) == true
      # Should have some kind of border indication
      assert is_list(style)
    end
  end

  describe "alternating_row_style/1" do
    test "returns different styles for odd and even rows" do
      style_odd = Styles.alternating_row_style(1)
      style_even = Styles.alternating_row_style(2)

      # The styles should be different
      assert style_odd != style_even
    end

    test "pattern repeats" do
      style_1 = Styles.alternating_row_style(1)
      style_3 = Styles.alternating_row_style(3)
      style_2 = Styles.alternating_row_style(2)
      style_4 = Styles.alternating_row_style(4)

      assert style_1 == style_3
      assert style_2 == style_4
    end
  end

  describe "merge_styles/2" do
    test "merges two style lists" do
      style1 = [bold: true, font_size: 12]
      style2 = [bg_color: "#FFFFFF"]

      merged = Styles.merge_styles(style1, style2)
      assert Keyword.get(merged, :bold) == true
      assert Keyword.get(merged, :font_size) == 12
      assert Keyword.get(merged, :bg_color) == "#FFFFFF"
    end

    test "second style overrides first" do
      style1 = [bold: true, font_size: 12]
      style2 = [bold: false]

      merged = Styles.merge_styles(style1, style2)
      assert Keyword.get(merged, :bold) == false
    end
  end

  describe "column_letters/1" do
    test "converts column number to letter for single letters" do
      assert Styles.column_letters(1) == "A"
      assert Styles.column_letters(26) == "Z"
    end

    test "converts column number to letter for double letters" do
      assert Styles.column_letters(27) == "AA"
      assert Styles.column_letters(28) == "AB"
      assert Styles.column_letters(52) == "AZ"
    end
  end

  describe "column_number/1" do
    test "converts letter to column number for single letters" do
      assert Styles.column_number("A") == 1
      assert Styles.column_number("Z") == 26
    end

    test "converts letter to column number for double letters" do
      assert Styles.column_number("AA") == 27
      assert Styles.column_number("AB") == 28
    end

    test "handles lowercase" do
      assert Styles.column_number("a") == 1
      assert Styles.column_number("aa") == 27
    end
  end

  describe "cell_reference/2" do
    test "creates cell reference from column and row" do
      assert Styles.cell_reference(1, 1) == "A1"
      assert Styles.cell_reference(3, 5) == "C5"
      assert Styles.cell_reference(27, 10) == "AA10"
    end
  end

  describe "parse_cell_reference/1" do
    test "parses cell reference to column and row" do
      assert Styles.parse_cell_reference("A1") == {1, 1}
      assert Styles.parse_cell_reference("C5") == {3, 5}
      assert Styles.parse_cell_reference("AA10") == {27, 10}
    end

    test "handles lowercase" do
      assert Styles.parse_cell_reference("a1") == {1, 1}
    end
  end
end
