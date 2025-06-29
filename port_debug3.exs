#!/usr/bin/env elixir

# Test with use_stdio option
IO.puts("Testing with use_stdio...")

claude_path = System.find_executable("claude")
args = ["--print", "--output-format", "stream-json", "--verbose", "Hi"]

IO.puts("Opening port with use_stdio...")
port = Port.open({:spawn_executable, claude_path}, [
  :binary,
  :exit_status,
  :use_stdio,
  :stderr_to_stdout,
  args: args
])

IO.puts("Port: #{inspect(port)}")

# Give it more time and collect all messages
messages = []
start_time = :os.system_time(:millisecond)

collect_messages = fn collect_messages, msgs ->
  receive do
    {^port, {:data, data}} ->
      elapsed = :os.system_time(:millisecond) - start_time
      IO.puts("\n[#{elapsed}ms] DATA: #{inspect(data, limit: 150)}")
      IO.puts("STRING: #{data}")
      collect_messages.(collect_messages, [data | msgs])
      
    {^port, {:exit_status, status}} ->
      elapsed = :os.system_time(:millisecond) - start_time
      IO.puts("\n[#{elapsed}ms] EXIT: #{status}")
      Enum.reverse([{:exit, status} | msgs])
      
    msg ->
      elapsed = :os.system_time(:millisecond) - start_time
      IO.puts("\n[#{elapsed}ms] OTHER: #{inspect(msg)}")
      collect_messages.(collect_messages, msgs)
  after
    15_000 ->
      elapsed = :os.system_time(:millisecond) - start_time
      IO.puts("\n[#{elapsed}ms] TIMEOUT")
      Enum.reverse(msgs)
  end
end

result = collect_messages.(collect_messages, [])
IO.puts("\nFinal result: #{inspect(result)}")

if Port.info(port), do: Port.close(port)