# Simple example of using the Factorial module

# Load the factorial module
Code.require_file("../lib/factorial.ex", __DIR__)

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