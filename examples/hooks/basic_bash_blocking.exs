#!/usr/bin/env elixir

# Example: Hook-based Bash Command Blocking with LIVE CLI
#
# This example demonstrates using a PreToolUse hook to block specific
# bash commands before they execute using the actual Claude CLI.
#
# The example shows:
# 1. Allowing a safe command (echo 'Hello from hooks!')
# 2. Blocking a command matching a security policy pattern (./blocked.sh)
#
# Note: We use "blocked.sh" as the pattern (similar to Python SDK's "./foo.sh")
# rather than dangerous commands like "rm -rf" because Claude's built-in safety
# may refuse those commands before the hook is even invoked.
#
# Run: mix run examples/hooks/basic_bash_blocking.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias ClaudeAgentSDK.{ContentExtractor, Message}
alias Examples.Support

Support.ensure_live!()
Support.header!("Hooks Example: Basic Bash Command Blocking (live)")

defmodule SecurityHooks do
  @moduledoc """
  Security hooks for Bash command validation.

  Demonstrates a PreToolUse hook that:
  - Allows safe commands (echo, ls, etc.)
  - Blocks commands matching security policy patterns

  This example uses "blocked.sh" as the blocked pattern (matching the Python
  SDK's hooks example which uses "./foo.sh"). We use this instead of dangerous
  commands like "rm -rf" because Claude's built-in safety may refuse those
  commands before the hook is even invoked.
  """

  @table :claude_agent_sdk_examples_basic_bash_blocking

  def table_name, do: @table

  def put_allowed_dir!(dir) when is_binary(dir) do
    :ets.insert(@table, {:allowed_dir, dir})
  end

  defp allowed_dir do
    case :ets.lookup(@table, :allowed_dir) do
      [{:allowed_dir, dir}] when is_binary(dir) -> dir
      _ -> System.tmp_dir!()
    end
  end

  @doc """
  PreToolUse hook that blocks Bash commands matching security policy patterns.

  Blocks commands containing "blocked.sh" pattern (similar to Python SDK's
  "./foo.sh" pattern). We use this pattern instead of dangerous commands
  because Claude's built-in safety may refuse rm -rf, dd, etc. before the
  hook is even invoked.

  Returns:
  - deny output if blocked pattern found
  - allow output otherwise
  """
  def check_tool_input(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => command}} ->
        # Block any command containing "blocked.sh" - matches Python SDK pattern
        blocked_patterns = ["blocked.sh"]

        if Enum.any?(blocked_patterns, &String.contains?(command, &1)) do
          _ = :ets.update_counter(@table, :denied, {2, 1}, {:denied, 0})

          IO.puts("\n🚫 BLOCKED: Command blocked by security policy!")
          IO.puts("   Command: #{command}\n")

          Output.deny("Command blocked by security policy: #{command}")
          |> Output.with_system_message("🔒 Security policy violation")
          |> Output.with_reason("This command is not allowed by the security policy")
        else
          _ = :ets.update_counter(@table, :allowed, {2, 1}, {:allowed, 0})

          IO.puts("\n✅ ALLOWED: Safe command")
          IO.puts("   Command: #{command}\n")

          Output.allow("Security check passed")
        end

      %{"tool_name" => "Write", "tool_input" => %{"file_path" => path}} when is_binary(path) ->
        if String.starts_with?(path, allowed_dir()) do
          _ = :ets.update_counter(@table, :allowed, {2, 1}, {:allowed, 0})

          IO.puts("\n✅ ALLOWED: Safe write")
          IO.puts("   Path: #{path}\n")

          Output.allow("Security check passed")
        else
          _ = :ets.update_counter(@table, :denied, {2, 1}, {:denied, 0})

          IO.puts("\n🚫 BLOCKED: Write blocked by security policy!")
          IO.puts("   Path: #{path}\n")

          Output.deny("Must operate within #{allowed_dir()}")
          |> Output.with_system_message("🔒 Sandbox restriction")
          |> Output.with_reason("Do not retry this tool call; explain that it is blocked.")
        end

      _ ->
        # Not a tool we inspect here, allow
        %{}
    end
  end
end

table = SecurityHooks.table_name()
ollama_write_dir = Support.tmp_dir!("claude_agent_sdk_basic_bash_blocking")
ollama_safe_path = Path.join(ollama_write_dir, "allowed.txt")

ollama_blocked_path =
  Path.join(
    System.tmp_dir!(),
    "claude_agent_sdk_basic_bash_blocked_#{System.unique_integer([:positive])}.txt"
  )

case :ets.whereis(table) do
  :undefined -> :ok
  tid -> :ets.delete(tid)
end

:ets.new(table, [:named_table, :public, :set])
SecurityHooks.put_allowed_dir!(ollama_write_dir)

# Configure hooks for use with live Client
hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&SecurityHooks.check_tool_input/3])
  ]
}

# Note: We don't set max_turns here to match Python SDK behavior.
# With hooks enabled, the conversation needs multiple turns:
# 1. Claude responds with tool_use
# 2. Hook is invoked and processes
# 3. Tool executes
# 4. Claude responds to tool result
# Setting max_turns too low (e.g., 2) causes error_max_turns failures.
options = %Options{
  tools: if(Support.ollama_backend?(), do: ["Write"], else: ["Bash"]),
  allowed_tools: if(Support.ollama_backend?(), do: ["Write"], else: ["Bash"]),
  max_turns: if(Support.ollama_backend?(), do: 4, else: nil),
  hooks: hooks,
  model: "haiku",
  permission_mode: :default
}

# Start client with hooks
{:ok, client} = Client.start_link(options)

IO.puts("Client started with PreToolUse hook for Bash commands.\n")

run_prompt =
  if Support.ollama_backend?() do
    fn prompt ->
      :ok = Client.query(client, prompt)
      {:ok, messages} = Client.receive_response(client)

      Enum.each(messages, fn
        %Message{type: :assistant} = msg ->
          text = ContentExtractor.extract_text(msg)
          if is_binary(text) and text != "", do: IO.puts("\nAssistant:\n#{text}\n")

        _ ->
          :ok
      end)

      messages
    end
  else
    fn prompt ->
      task =
        Task.async(fn ->
          Client.stream_messages(client)
          |> Enum.reduce_while([], fn message, acc ->
            acc = [message | acc]

            case message do
              %Message{type: :assistant} = msg ->
                text = ContentExtractor.extract_text(msg)
                if is_binary(text) and text != "", do: IO.puts("\nAssistant:\n#{text}\n")
                {:cont, acc}

              %Message{type: :result} ->
                {:halt, Enum.reverse(acc)}

              _ ->
                {:cont, acc}
            end
          end)
        end)

      Process.sleep(50)
      :ok = Client.send_message(client, prompt)
      Task.await(task, 120_000)
    end
  end

{safe_label, safe_prompt} =
  if Support.ollama_backend?() do
    IO.puts(
      "Ollama variation: using Write allow/deny checks because Bash tool payloads are not reliable.\n"
    )

    {
      "Test 1: safe write (Ollama variation, should be allowed)\n",
      "Use the Write tool to write exactly 'hooks ok' to #{ollama_safe_path}."
    }
  else
    {
      "Test 1: safe command (should be allowed)\n",
      "Use the Bash tool to run this exact command: echo 'Hello from hooks!'"
    }
  end

IO.puts(safe_label)

messages1 =
  run_prompt.(safe_prompt)

{blocked_label, blocked_prompt} =
  if Support.ollama_backend?() do
    {
      "\nTest 2: blocked write (Ollama variation, should be blocked by hook)\n",
      "Use the Write tool to write exactly 'blocked' to #{ollama_blocked_path}."
    }
  else
    {
      "\nTest 2: blocked command (should be blocked by hook)\n",
      "Use the Bash tool to run this exact command: ./blocked.sh --help"
    }
  end

IO.puts(blocked_label)

messages2 =
  run_prompt.(blocked_prompt)

case Enum.find(messages1, &(&1.type == :result)) do
  %Message{subtype: :success} ->
    :ok

  %Message{subtype: other} ->
    raise "Safe command run did not succeed (result subtype: #{inspect(other)})"

  nil ->
    raise "Safe command run returned no result message."
end

case Enum.find(messages2, &(&1.type == :result)) do
  %Message{subtype: :success} ->
    :ok

  %Message{subtype: :error_max_turns} ->
    if Support.ollama_backend?() do
      IO.puts("Note: blocked Ollama variation hit max_turns after repeated denied retries.")
    else
      raise "Blocked command run did not succeed (result subtype: :error_max_turns)"
    end

  %Message{subtype: other} ->
    raise "Blocked command run did not succeed (result subtype: #{inspect(other)})"

  nil ->
    raise "Blocked command run returned no result message."
end

allowed =
  case :ets.lookup(table, :allowed) do
    [{:allowed, n}] when is_integer(n) -> n
    _ -> 0
  end

denied =
  case :ets.lookup(table, :denied) do
    [{:denied, n}] when is_integer(n) -> n
    _ -> 0
  end

if allowed < 1 do
  raise "Expected PreToolUse hook to allow at least one Bash command, but allowed=#{allowed}."
end

if denied < 1 do
  raise "Expected PreToolUse hook to deny at least one Bash command, but denied=#{denied}."
end

# Clean up
if Process.alive?(client), do: Client.stop(client)
:ets.delete(table)
Support.cleanup_tmp_dir(ollama_write_dir)
_ = File.rm(ollama_blocked_path)

IO.puts("\nDone.")
Support.halt_if_runner!()
