defmodule ClaudeCodeSDK.Process do
  @moduledoc """
  Handles spawning and communicating with the Claude Code CLI process using erlexec.
  """

  alias ClaudeCodeSDK.{Message, Options}

  @doc """
  Streams messages from Claude Code CLI using erlexec.
  """
  def stream(args, %Options{} = options) do
    Stream.resource(
      fn -> start_claude_process(args, options) end,
      &receive_messages/1,
      &cleanup_process/1
    )
  end

  defp start_claude_process(args, options) do
    # Start erlexec application if not already running
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "Failed to start erlexec application: #{inspect(reason)}"
    end

    # Build the command
    cmd = build_claude_command(args, options)
    
    # Execute with erlexec - use sync mode to capture all output
    case :exec.run(cmd, [:sync, :stdout, :stderr]) do
      {:ok, result} ->
        # Process the synchronous result and convert to streaming format
        %{
          mode: :sync,
          result: result,
          messages: parse_sync_result(result),
          current_index: 0,
          done: false
        }
        
      {:error, reason} ->
        error_msg = %Message{
          type: :result,
          subtype: :error_during_execution,
          data: %{
            error: "Failed to execute claude: #{inspect(reason)}",
            session_id: "error",
            is_error: true
          }
        }
        %{
          mode: :error,
          messages: [error_msg],
          current_index: 0,
          done: false
        }
    end
  end

  defp build_claude_command(args, _options) do
    executable = find_executable()
    
    # Ensure proper flags for JSON output
    final_args = ensure_json_flags(args)
    
    # Build command with proper shell escaping
    quoted_args = Enum.map(final_args, &shell_escape/1)
    Enum.join([executable | quoted_args], " ")
  end
  
  defp shell_escape(arg) do
    # Escape arguments that contain spaces or special characters
    if String.contains?(arg, [" ", "!", "\"", "'", "$", "`", "\\", "|", "&", ";", "(", ")"]) do
      "\"#{String.replace(arg, "\"", "\\\"")}\""
    else
      arg
    end
  end

  defp find_executable do
    case System.find_executable("claude") do
      nil -> raise "Claude CLI not found. Please install with: npm install -g @anthropic-ai/claude-code"
      path -> path
    end
  end

  defp ensure_json_flags(args) do
    cond do
      "--output-format" not in args ->
        args ++ ["--output-format", "stream-json", "--verbose"]
        
      has_stream_json?(args) and "--verbose" not in args ->
        args ++ ["--verbose"]
        
      true ->
        args
    end
  end

  defp has_stream_json?(args) do
    case Enum.find_index(args, & &1 == "--output-format") do
      nil -> false
      idx -> Enum.at(args, idx + 1) == "stream-json"
    end
  end

  defp parse_sync_result(result) do
    stdout_data = get_in(result, [:stdout]) || []
    stderr_data = get_in(result, [:stderr]) || []
    
    # Combine all output
    all_output = stdout_data ++ stderr_data
    
    # Parse JSON messages from the output
    all_output
    |> Enum.join()
    |> String.split("\n")
    |> Enum.filter(& &1 != "")
    |> Enum.map(&parse_json_line/1)
    |> Enum.filter(& &1 != nil)
  end

  defp parse_json_line(line) do
    case Message.from_json(line) do
      {:ok, message} -> message
      {:error, _} -> 
        # If JSON parsing fails, treat as text output
        %Message{
          type: :assistant,
          data: %{
            message: %{"role" => "assistant", "content" => line},
            session_id: "unknown"
          }
        }
    end
  end

  defp receive_messages(%{done: true} = state) do
    {:halt, state}
  end

  defp receive_messages(%{mode: :error, messages: [msg], current_index: 0} = state) do
    {[msg], %{state | current_index: 1, done: true}}
  end

  defp receive_messages(%{mode: :sync, messages: messages, current_index: idx} = state) do
    if idx >= length(messages) do
      {:halt, %{state | done: true}}
    else
      message = Enum.at(messages, idx)
      new_state = %{state | current_index: idx + 1}
      
      # Check if this is the final message
      if Message.final?(message) do
        {[message], %{new_state | done: true}}
      else
        {[message], new_state}
      end
    end
  end

  defp cleanup_process(_state) do
    # erlexec handles cleanup automatically for sync operations
    :ok
  end
end