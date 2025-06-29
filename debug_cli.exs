#!/usr/bin/env elixir

# Direct CLI test to see what's happening
IO.puts("Testing claude CLI directly...")

prompt = "Say hi"
args = ["--print", "--output-format", "stream-json", prompt]

IO.puts("\nCommand: claude #{Enum.join(args, " ")}")
IO.puts("Starting...")

port = Port.open({:spawn_executable, System.find_executable("claude")}, [
  :binary,
  :exit_status,
  :use_stdio,
  :stderr_to_stdout,
  args: args
])

# Read everything the CLI outputs
receive_loop = fn receive_loop ->
  receive do
    {^port, {:data, data}} ->
      IO.puts("\nRAW OUTPUT: #{inspect(data)}")
      IO.puts("AS STRING: #{data}")
      receive_loop.(receive_loop)
      
    {^port, {:exit_status, status}} ->
      IO.puts("\nEXIT STATUS: #{status}")
      
  after
    10_000 ->
      IO.puts("\nTIMEOUT after 10 seconds")
      Port.close(port)
  end
end

receive_loop.(receive_loop)