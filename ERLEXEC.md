# Erlexec Integration for Claude Code SDK

## Overview

After debugging the Port communication issues with the Claude CLI, we've identified that the native Elixir `Port.open/2` approach has limitations with complex subprocess interaction. The **erlexec** library provides a robust, production-grade solution for OS process management in Erlang/OTP systems.

## Why Erlexec?

### Current Issues with Port.open/2
1. **EPIPE Errors**: The Claude CLI gets broken pipe errors when stdio isn't properly configured
2. **Limited Control**: Basic port options don't provide fine-grained process management
3. **No Process Monitoring**: Difficult to properly monitor and cleanup child processes
4. **IO Redirection Issues**: Complex stdout/stderr handling with JSON streaming

### Erlexec Advantages
1. **Robust Process Management**: Battle-tested in production Erlang/Elixir systems
2. **Proper IO Handling**: Built-in support for stdout/stderr redirection to Erlang processes
3. **Process Monitoring**: Native support for process monitoring and linking
4. **Synchronous Execution**: Built-in support for sync execution with captured output
5. **Better Error Handling**: Comprehensive exit status and signal handling
6. **No Broken Pipes**: Proper stdio setup prevents EPIPE errors

## Integration Design

### Dependencies
Add to `mix.exs`:
```elixir
defp deps do
  [
    {:erlexec, "~> 2.0"},
    # Remove {:req, "~> 0.5.0"} - not needed
  ]
end
```

### Architecture Changes

```
ClaudeAgentSDK.query/2
    ↓
ClaudeAgentSDK.Query.run/2
    ↓
ClaudeAgentSDK.Process.stream_erlexec/2  ← NEW
    ↓
:exec.run/2 (erlexec)
    ↓
claude CLI subprocess
```

### New Process Module Design

```elixir
defmodule ClaudeAgentSDK.Process do
  @doc """
  Execute claude CLI using erlexec for robust process management
  """
  def stream_erlexec(args, options) do
    Stream.resource(
      fn -> start_claude_process(args, options) end,
      &receive_messages/1,
      &cleanup_process/1
    )
  end

  defp start_claude_process(args, options) do
    # Start erlexec if not running
    :exec.start_link([])
    
    # Build command
    cmd = build_claude_command(args, options)
    
    # Execute with erlexec
    {:ok, pid, os_pid} = :exec.run(cmd, [
      :sync,           # Wait for completion
      :stdout,         # Capture stdout
      :stderr,         # Capture stderr  
      :monitor         # Monitor process
    ])
    
    %{
      exec_pid: pid,
      os_pid: os_pid,
      buffer: "",
      messages: [],
      done: false
    }
  end
  
  defp build_claude_command(args, _options) do
    executable = System.find_executable("claude") || 
      raise "Claude CLI not found"
    
    # Ensure proper flags for JSON output
    final_args = ensure_json_flags(args)
    
    # Return command as string for shell execution
    [executable | final_args] |> Enum.join(" ")
  end
  
  defp ensure_json_flags(args) do
    if "--output-format" not in args do
      args ++ ["--output-format", "stream-json", "--verbose"]
    else
      # Add --verbose if stream-json is used
      if has_stream_json?(args) and "--verbose" not in args do
        args ++ ["--verbose"]
      else
        args
      end
    end
  end
  
  defp receive_messages(%{done: true} = state) do
    {:halt, state}
  end
  
  defp receive_messages(state) do
    receive do
      # Stdout data from erlexec
      {:stdout, _os_pid, data} ->
        process_stdout_data(data, state)
        
      # Stderr data from erlexec  
      {:stderr, _os_pid, data} ->
        process_stderr_data(data, state)
        
      # Process completed
      {:DOWN, _os_pid, :process, _pid, reason} ->
        handle_process_exit(reason, state)
        
    after
      10_000 ->
        {:halt, %{state | done: true}}
    end
  end
  
  defp process_stdout_data(data, state) do
    # Parse JSON lines from stdout
    lines = String.split(state.buffer <> data, "\n")
    {complete_lines, buffer} = List.pop_at(lines, -1)
    
    messages = 
      complete_lines
      |> Enum.filter(& &1 != "")
      |> Enum.map(&parse_json_message/1)
      |> Enum.filter(&(&1 != nil))
    
    new_state = %{state | 
      buffer: buffer || "",
      messages: state.messages ++ messages
    }
    
    # Check if we have a final result message
    final_msg = Enum.find(messages, &ClaudeAgentSDK.Message.final?/1)
    if final_msg do
      {messages, %{new_state | done: true}}
    else
      {messages, new_state}
    end
  end
  
  defp parse_json_message(line) do
    case ClaudeAgentSDK.Message.from_json(line) do
      {:ok, message} -> message
      {:error, _} -> nil
    end
  end
  
  defp handle_process_exit(:normal, state) do
    # Process completed normally
    {:halt, %{state | done: true}}
  end
  
  defp handle_process_exit(reason, state) do
    # Process failed - create error message
    error_msg = %ClaudeAgentSDK.Message{
      type: :result,
      subtype: :error_during_execution,
      data: %{
        error: "Process failed: #{inspect(reason)}",
        session_id: "error",
        is_error: true
      }
    }
    {[error_msg], %{state | done: true}}
  end
  
  defp cleanup_process(%{exec_pid: pid}) do
    :exec.stop(pid)
  catch
    _ -> :ok
  end
end
```

### Benefits of This Approach

1. **Reliable Execution**: Erlexec handles all the stdio plumbing correctly
2. **Proper Monitoring**: Built-in process monitoring and cleanup
3. **Sync Mode**: Can capture all output at once, then stream it to the user
4. **Error Handling**: Comprehensive exit status and error reporting
5. **Production Ready**: Erlexec is battle-tested in production systems

### Migration Path

1. **Add Erlexec Dependency**: Update mix.exs
2. **Implement New Process Module**: Replace Port-based implementation
3. **Update Tests**: Ensure all tests pass with new implementation
4. **Maintain API Compatibility**: Keep existing ClaudeAgentSDK interface unchanged

### Example Usage After Migration

```elixir
# Same API, better implementation
ClaudeAgentSDK.query("Say hello")
|> Enum.each(fn msg ->
  case msg.type do
    :assistant -> IO.puts(msg.data.message["content"])
    :result -> IO.puts("Done: #{msg.data.session_id}")
    _ -> :ok
  end
end)
```

## Testing Strategy

1. **Unit Tests**: Test message parsing and stream handling
2. **Integration Tests**: Test with actual claude CLI
3. **Error Cases**: Test authentication errors, timeouts, etc.
4. **Performance**: Compare with current Port implementation

## Implementation Steps

1. Add erlexec dependency
2. Implement new Process module with erlexec
3. Update existing modules to use new Process
4. Add comprehensive tests
5. Update documentation
6. Remove old Port-based code

This approach should solve the current EPIPE and timeout issues while providing a more robust foundation for the SDK.