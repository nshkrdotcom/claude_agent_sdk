#!/usr/bin/env elixir

# Example 1: Block Dangerous Bash Commands with LIVE CLI
#
# This example demonstrates using a PreToolUse hook to block dangerous
# bash commands before they execute using the actual Claude CLI.
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
  Security hooks for blocking dangerous commands.
  """

  @table :claude_agent_sdk_examples_basic_bash_blocking

  def table_name, do: @table

  @doc """
  PreToolUse hook that blocks dangerous bash commands.

  Checks for patterns like:
  - rm -rf
  - dd if=
  - mkfs
  - > /dev/

  Returns:
  - deny output if dangerous pattern found
  - allow output otherwise
  """
  def check_bash_command(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => command}} ->
        dangerous_patterns = ["rm -rf", "dd if=", "mkfs", "> /dev/"]

        if Enum.any?(dangerous_patterns, &String.contains?(command, &1)) do
          _ = :ets.update_counter(@table, :denied, {2, 1}, {:denied, 0})

          IO.puts("\n🚫 BLOCKED: Dangerous command detected!")
          IO.puts("   Command: #{command}\n")

          Output.deny("Dangerous command blocked: #{command}")
          |> Output.with_system_message("🔒 Security policy violation")
          |> Output.with_reason("This command could cause data loss or system damage")
        else
          _ = :ets.update_counter(@table, :allowed, {2, 1}, {:allowed, 0})

          IO.puts("\n✅ ALLOWED: Safe command")
          IO.puts("   Command: #{command}\n")

          Output.allow("Security check passed")
        end

      _ ->
        # Not a Bash command, allow
        %{}
    end
  end
end

table = SecurityHooks.table_name()

case :ets.whereis(table) do
  :undefined -> :ok
  tid -> :ets.delete(tid)
end

:ets.new(table, [:named_table, :public, :set])

# Configure hooks for use with live Client
hooks = %{
  pre_tool_use: [
    Matcher.new("Bash", [&SecurityHooks.check_bash_command/3])
  ]
}

options = %Options{
  tools: ["Bash"],
  allowed_tools: ["Bash"],
  hooks: hooks,
  model: "haiku",
  max_turns: 2,
  permission_mode: :default
}

# Start client with hooks
{:ok, client} = Client.start_link(options)

IO.puts("Client started with PreToolUse hook for Bash commands.\n")

run_prompt = fn prompt ->
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

IO.puts("Test 1: safe command (should be allowed)\n")

messages1 =
  run_prompt.("Use the Bash tool to run this exact command: echo 'Hello from hooks!'")

IO.puts("\nTest 2: dangerous command (should be blocked by hook)\n")

messages2 =
  run_prompt.("Use the Bash tool to run this exact command: rm -rf /tmp/this_should_be_blocked")

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

  %Message{subtype: other} ->
    raise "Dangerous command run did not succeed (result subtype: #{inspect(other)})"

  nil ->
    raise "Dangerous command run returned no result message."
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

IO.puts("\nDone.")
Support.halt_if_runner!()
