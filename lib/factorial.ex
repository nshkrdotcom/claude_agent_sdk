defmodule Factorial do
  @moduledoc """
  A simple module for calculating factorials.
  """

  @doc """
  Calculates the factorial of a non-negative integer.

  ## Examples

      iex> Factorial.calculate(0)
      1

      iex> Factorial.calculate(5)
      120
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
