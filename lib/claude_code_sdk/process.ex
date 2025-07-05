defmodule ClaudeCodeSDK.Process do
  @moduledoc """
  Handles spawning and communicating with the Claude Code CLI process using erlexec.

  This module manages the lifecycle of Claude CLI subprocess execution:
  - Starting the CLI process with proper arguments
  - Capturing and parsing JSON output from stdout/stderr
  - Converting the output into a stream of `ClaudeCodeSDK.Message` structs
  - Handling errors and cleanup

  The module uses erlexec's synchronous execution mode to capture all output
  at once, then converts it to a lazy stream for consumption.
  """

  alias ClaudeCodeSDK.{Message, Options}

  @doc """
  Streams messages from Claude Code CLI using erlexec.

  ## Parameters

  - `args` - List of command-line arguments for the Claude CLI
  - `options` - Configuration options (see `ClaudeCodeSDK.Options.t/0`)

  ## Returns

  A stream of `ClaudeCodeSDK.Message.t/0` structs.

  ## Examples

      ClaudeCodeSDK.Process.stream(["--print", "Hello"], %ClaudeCodeSDK.Options{})

  """
  @spec stream([String.t()], Options.t(), String.t() | nil) ::
          Enumerable.t(ClaudeCodeSDK.Message.t())
  def stream(args, %Options{} = options, stdin_input \\ nil) do
    # Check if we should use mock
    if use_mock?() do
      ClaudeCodeSDK.Mock.Process.stream(args, options, stdin_input)
    else
      stream_real(args, options, stdin_input)
    end
  end

  defp use_mock? do
    Application.get_env(:claude_code_sdk, :use_mock, false)
  end

  defp stream_real(args, options, stdin_input) do
    Stream.resource(
      fn -> start_claude_process(args, options, stdin_input) end,
      &receive_messages/1,
      &cleanup_process/1
    )
  end

  defp start_claude_process(args, options, stdin_input) do
    # Start erlexec application if not already running
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "Failed to start erlexec application: #{inspect(reason)}"
    end

    # Build the command - for erlexec, stdin is passed as part of the command args, not exec options
    {cmd, _cmd_args} = build_claude_command(args, options, stdin_input)

    # Build exec options with working directory if specified
    exec_options = build_exec_options(options)

    # Execute with erlexec
    case stdin_input do
      nil ->
        # Regular sync execution without stdin
        case :exec.run(cmd, exec_options) do
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
            formatted_error = format_error_message(reason, options)

            error_msg = %Message{
              type: :result,
              subtype: :error_during_execution,
              data: %{
                error: formatted_error,
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

      input when is_binary(input) ->
        # Use erlexec with stdin support
        run_with_stdin_erlexec(cmd, input, exec_options, options)
    end
  end

  defp run_with_stdin_erlexec(cmd, input, exec_options, options) do
    # Add stdin to the exec options and use async execution
    # Remove sync and add monitor for async execution
    base_options = exec_options |> Enum.reject(&(&1 in [:sync, :stdout, :stderr]))
    stdin_exec_options = [:stdin, :stdout, :stderr, :monitor] ++ base_options

    case :exec.run(cmd, stdin_exec_options) do
      {:ok, pid, os_pid} ->
        # Send the input to stdin
        :exec.send(pid, input)
        :exec.send(pid, :eof)

        # Collect output until process exits
        receive_exec_output(pid, os_pid, [], [])

      {:error, reason} ->
        formatted_error = format_error_message(reason, options)

        error_msg = %Message{
          type: :result,
          subtype: :error_during_execution,
          data: %{
            error: formatted_error,
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

  defp receive_exec_output(pid, os_pid, stdout_acc, stderr_acc) do
    receive do
      {:stdout, ^os_pid, data} ->
        # Check for challenge URL in the output
        combined_output = [data | stdout_acc] |> Enum.reverse() |> Enum.join()
        if challenge_url = detect_challenge_url(combined_output) do
          # Challenge URL detected - dump it and terminate
          IO.puts("\n🔐 Challenge URL detected:")
          IO.puts("#{challenge_url}")
          IO.puts("\nTerminating process...")
          
          # Stop the process
          :exec.stop(pid)
          
          # Return a special error message indicating challenge URL was detected
          error_msg = %Message{
            type: :result,
            subtype: :authentication_required,
            data: %{
              error: "Authentication challenge detected",
              challenge_url: challenge_url,
              session_id: "auth_challenge",
              is_error: true
            }
          }

          %{
            mode: :error,
            messages: [error_msg],
            current_index: 0,
            done: false
          }
        else
          receive_exec_output(pid, os_pid, [data | stdout_acc], stderr_acc)
        end

      {:stderr, ^os_pid, data} ->
        # Also check stderr for challenge URL
        combined_output = [data | stderr_acc] |> Enum.reverse() |> Enum.join()
        if challenge_url = detect_challenge_url(combined_output) do
          # Challenge URL detected - dump it and terminate
          IO.puts("\n🔐 Challenge URL detected:")
          IO.puts("#{challenge_url}")
          IO.puts("\nTerminating process...")
          
          # Stop the process
          :exec.stop(pid)
          
          # Return a special error message indicating challenge URL was detected
          error_msg = %Message{
            type: :result,
            subtype: :authentication_required,
            data: %{
              error: "Authentication challenge detected",
              challenge_url: challenge_url,
              session_id: "auth_challenge",
              is_error: true
            }
          }

          %{
            mode: :error,
            messages: [error_msg],
            current_index: 0,
            done: false
          }
        else
          receive_exec_output(pid, os_pid, stdout_acc, [data | stderr_acc])
        end

      {:DOWN, ^os_pid, :process, ^pid, _exit_status} ->
        # Process completed, parse the accumulated output
        stdout_output = stdout_acc |> Enum.reverse() |> Enum.join()
        stderr_output = stderr_acc |> Enum.reverse() |> Enum.join()

        stdout_lines = if stdout_output == "", do: [], else: [stdout_output]
        stderr_lines = if stderr_output == "", do: [], else: [stderr_output]

        result = %{stdout: stdout_lines, stderr: stderr_lines}

        %{
          mode: :sync,
          result: result,
          messages: parse_sync_result(result),
          current_index: 0,
          done: false
        }
    after
      30_000 ->
        # Timeout after 30 seconds
        :exec.stop(pid)

        error_msg = %Message{
          type: :result,
          subtype: :error_during_execution,
          data: %{
            error: "Command timed out after 30 seconds",
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

  defp build_claude_command(args, _options, _stdin_input) do
    executable = find_executable()

    # Ensure proper flags for JSON output
    final_args = ensure_json_flags(args)

    # Always return the command string format - erlexec handles both cases
    quoted_args = Enum.map(final_args, &shell_escape/1)
    {Enum.join([executable | quoted_args], " "), []}
  end

  defp build_exec_options(options) do
    base_options = [:sync, :stdout, :stderr]

    case options.cwd do
      nil ->
        base_options

      cwd ->
        # Ensure the directory exists
        unless File.dir?(cwd) do
          File.mkdir_p!(cwd)
        end

        [{:cd, cwd} | base_options]
    end
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
      nil ->
        raise "Claude CLI not found. Please install with: npm install -g @anthropic-ai/claude-code"

      path ->
        path
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
    case Enum.find_index(args, &(&1 == "--output-format")) do
      nil -> false
      idx -> Enum.at(args, idx + 1) == "stream-json"
    end
  end

  defp parse_sync_result(result) do
    stdout_data = get_in(result, [:stdout]) || []
    stderr_data = get_in(result, [:stderr]) || []

    # Combine all output
    all_output = stdout_data ++ stderr_data
    combined_text = Enum.join(all_output)

    # First check for challenge URL
    if challenge_url = detect_challenge_url(combined_text) do
      # Challenge URL detected - dump it and return special message
      IO.puts("\n🔐 Challenge URL detected:")
      IO.puts("#{challenge_url}")
      IO.puts("\nTerminating process...")
      
      [%Message{
        type: :result,
        subtype: :authentication_required,
        data: %{
          error: "Authentication challenge detected",
          challenge_url: challenge_url,
          session_id: "auth_challenge",
          is_error: true
        }
      }]
    else
      # Parse JSON messages from the output
      combined_text
      |> String.split("\n")
      |> Enum.filter(&(&1 != ""))
      |> Enum.map(&parse_json_line/1)
      |> Enum.filter(&(&1 != nil))
    end
  end

  defp parse_json_line(line) do
    # First try to parse as a Claude CLI result object
    case ClaudeCodeSDK.JSON.decode(line) do
      {:ok, %{"type" => "result", "result" => result, "session_id" => session_id}} ->
        # This is a Claude CLI result format
        %Message{
          type: :assistant,
          data: %{
            message: %{"role" => "assistant", "content" => result},
            session_id: session_id
          }
        }

      {:ok, json_obj} when is_map(json_obj) ->
        # Try to parse as a regular message
        case Message.from_json(line) do
          {:ok, message} -> message
          {:error, _} -> handle_fallback_parsing(line, json_obj)
        end

      {:ok, _other} ->
        # JSON parsed but not a map (like a number or string)
        handle_fallback_parsing(line, nil)

      {:error, _} ->
        # JSON parsing failed completely
        handle_fallback_parsing(line, nil)
    end
  end

  defp handle_fallback_parsing(line, _json_obj) do
    # If JSON parsing fails or doesn't match expected format, treat as text output
    %Message{
      type: :assistant,
      data: %{
        message: %{"role" => "assistant", "content" => line},
        session_id: "unknown"
      }
    }
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

  defp format_error_message(reason, options) do
    cwd_info = if options.cwd, do: " (cwd: #{options.cwd})", else: ""

    case reason do
      [exit_status: status, stdout: stdout_data] when is_list(stdout_data) ->
        # Extract and format JSON from stdout
        json_output = Enum.join(stdout_data, "")
        formatted_json = format_json_output(json_output)
        "Failed to execute claude#{cwd_info} (exit status: #{status}):\n#{formatted_json}"

      [exit_status: status, stdout: stdout_data, stderr: stderr_data]
      when is_list(stdout_data) ->
        # Extract and format JSON from stdout
        json_output = Enum.join(stdout_data, "")
        formatted_json = format_json_output(json_output)
        stderr_text = if is_list(stderr_data), do: Enum.join(stderr_data, ""), else: ""
        error_details = if stderr_text != "", do: "\nstderr: #{stderr_text}", else: ""

        "Failed to execute claude#{cwd_info} (exit status: #{status}):\n#{formatted_json}#{error_details}"

      [exit_status: status] ->
        "Failed to execute claude#{cwd_info} (exit status: #{status})"

      other ->
        "Failed to execute claude#{cwd_info}: #{inspect(other)}"
    end
  end

  defp format_json_output(json_string) do
    json_string
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.map_join("\n", &format_single_json_line/1)
  end

  defp format_single_json_line(line) do
    # Try to parse and pretty print the JSON
    case ClaudeCodeSDK.JSON.decode(line) do
      {:ok, _parsed} ->
        # Since we don't have a pretty print encoder, just return the line
        line
      {:error, _} ->
        # If parsing fails, return the original line
        line
    end
  end

  @doc false
  # Detects challenge URLs in CLI output
  # Common patterns:
  # - "Please visit: https://console.anthropic.com/..."
  # - "Open this URL in your browser: https://..."
  # - "Visit https://console.anthropic.com/challenge/..."
  # - URLs containing "challenge", "auth", "login", or "verify"
  defp detect_challenge_url(output) do
    # Define patterns to look for
    patterns = [
      # Direct URL patterns with common auth/challenge keywords
      ~r/https:\/\/[^\s]*(?:challenge|auth|login|verify|oauth|signin|authenticate)[^\s]*/i,
      # Console URLs that might be auth-related
      ~r/https:\/\/console\.anthropic\.com\/[^\s]+/i,
      # URLs preceded by common prompts
      ~r/(?:visit|open|go to|navigate to|click|access)[\s:]+?(https:\/\/[^\s]+)/i,
      # Any URL in a line containing auth-related keywords
      ~r/(?:authenticate|login|sign in|verify|challenge).*?(https:\/\/[^\s]+)/i,
      # URLs in JSON that might be auth URLs
      ~r/"(?:url|challenge_url|auth_url|login_url)"[\s:]+?"(https:\/\/[^\s"]+)"/i
    ]

    # Try each pattern
    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, output) do
        [full_match | _captures] ->
          # Extract just the URL part if it's embedded in a larger match
          url = extract_url_from_match(full_match)
          if valid_challenge_url?(url), do: url, else: nil
        nil ->
          nil
      end
    end)
  end

  # Extract clean URL from a regex match
  defp extract_url_from_match(match) do
    # If the match contains an URL starting with https://, extract it
    case Regex.run(~r/https:\/\/[^\s"'>\]]+/, match) do
      [url] -> url
      _ -> match
    end
  end

  # Validate that the URL looks like an authentication challenge URL
  defp valid_challenge_url?(url) do
    String.starts_with?(url, "https://") and
      (String.contains?(url, "anthropic.com") or
       String.contains?(url, "challenge") or
       String.contains?(url, "auth") or
       String.contains?(url, "login") or
       String.contains?(url, "verify") or
       String.contains?(url, "oauth"))
  end
end
