#!/usr/bin/env elixir

# Direct port test to debug the issue
IO.puts("Testing Port communication...")

# Find claude executable
claude_path = System.find_executable("claude")
IO.puts("Claude path: #{claude_path}")

# Build the command
args = ["--print", "--output-format", "stream-json", "--verbose", "Hi"]
IO.puts("Args: #{inspect(args)}")

# Create port with minimal options
IO.puts("\nOpening port...")
port = Port.open({:spawn_executable, claude_path}, [
  :binary,
  :exit_status,
  :stderr_to_stdout,
  args: args
])

IO.puts("Port opened: #{inspect(port)}")

# Ports can't be monitored directly, we'll use timeout instead

# Receive all messages
IO.puts("\nWaiting for messages...")
receive_all = fn receive_all, count ->
  receive do
    {^port, {:data, data}} ->
      IO.puts("\n[#{count}] DATA: #{inspect(data)}")
      IO.puts("STRING: #{data}")
      receive_all.(receive_all, count + 1)
      
    {^port, {:exit_status, status}} ->
      IO.puts("\n[#{count}] EXIT STATUS: #{status}")
      
    
    msg ->
      IO.puts("\n[#{count}] OTHER: #{inspect(msg)}")
      receive_all.(receive_all, count + 1)
  after
    10_000 ->
      IO.puts("\n[#{count}] TIMEOUT after 10 seconds")
      
      # Check if port is still alive
      port_info = Port.info(port)
      IO.puts("Port info: #{inspect(port_info)}")
      
      # Try to close it
      if port_info do
        Port.close(port)
        IO.puts("Port closed")
      end
  end
end

receive_all.(receive_all, 1)