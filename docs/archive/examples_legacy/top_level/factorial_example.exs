# Simple example demonstrating factorial calculation

defmodule Factorial do
  @moduledoc """
  A simple module for calculating factorials.
  """

  def calculate(n) when is_integer(n) and n >= 0 do
    do_calculate(n, 1)
  end

  def calculate(n) when is_integer(n) and n < 0 do
    raise ArgumentError, "Cannot calculate factorial of negative number"
  end

  def calculate(_) do
    raise ArgumentError, "Input must be an integer"
  end

  defp do_calculate(0, acc), do: acc
  defp do_calculate(n, acc), do: do_calculate(n - 1, n * acc)
end

# Examples of calculating factorials
IO.puts("Factorial examples:")
IO.puts("0! = #{Factorial.calculate(0)}")
IO.puts("1! = #{Factorial.calculate(1)}")
IO.puts("5! = #{Factorial.calculate(5)}")
IO.puts("10! = #{Factorial.calculate(10)}")

# Example with error handling
try do
  Factorial.calculate(-1)
rescue
  ArgumentError -> IO.puts("Error: Cannot calculate factorial of negative number")
end

try do
  Factorial.calculate("not a number")
rescue
  ArgumentError -> IO.puts("Error: Input must be an integer")
end
