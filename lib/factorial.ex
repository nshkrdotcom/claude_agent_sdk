defmodule Factorial do
  @moduledoc """
  A module for calculating factorial of non-negative integers.
  
  The factorial of n (denoted as n!) is the product of all positive integers less than or equal to n.
  """

  @doc """
  Calculates the factorial of a non-negative integer.

  ## Parameters
    - n: A non-negative integer

  ## Returns
    The factorial of n

  ## Examples
      iex> Factorial.calculate(0)
      1
      
      iex> Factorial.calculate(5)
      120
      
      iex> Factorial.calculate(10)
      3628800

  ## Raises
    ArgumentError - if n is negative or not an integer
  """
  @spec calculate(non_neg_integer()) :: pos_integer()
  def calculate(n) when is_integer(n) and n >= 0 do
    do_calculate(n)
  end

  def calculate(n) when is_integer(n) and n < 0 do
    raise ArgumentError, "Factorial is not defined for negative numbers"
  end

  def calculate(_) do
    raise ArgumentError, "Input must be a non-negative integer"
  end

  # Private helper function using tail recursion for efficiency
  defp do_calculate(n, acc \\ 1)
  defp do_calculate(0, acc), do: acc
  defp do_calculate(n, acc), do: do_calculate(n - 1, n * acc)
end