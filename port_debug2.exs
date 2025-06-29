#!/usr/bin/env elixir

# Test different port configurations
IO.puts("Testing different port options...")

claude_path = System.find_executable("claude")
args = ["--print", "--output-format", "stream-json", "--verbose", "Hi"]

configs = [
  {:binary, :exit_status, :stderr_to_stdout},
  {:binary, :exit_status},
  {:binary, :stderr_to_stdout},
  {:binary}
]

Enum.each(configs, fn config ->
  IO.puts("\n=== Testing config: #{inspect(config)} ===")
  
  port = Port.open({:spawn_executable, claude_path}, [
    config |> Tuple.to_list(),
    args: args
  ] |> List.flatten())
  
  IO.puts("Port: #{inspect(port)}")
  
  receive do
    {^port, {:data, data}} ->
      IO.puts("SUCCESS! Got data: #{inspect(data, limit: 100)}")
      Port.close(port)
      
    {^port, {:exit_status, status}} ->
      IO.puts("Exit status: #{status}")
      
    msg ->
      IO.puts("Other message: #{inspect(msg)}")
  after
    3_000 ->
      IO.puts("Timeout")
      if Port.info(port), do: Port.close(port)
  end
end)