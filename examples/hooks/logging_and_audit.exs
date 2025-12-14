#!/usr/bin/env elixir

# Example 4: Logging and Audit Trail with LIVE CLI
#
# This example demonstrates using hooks to create comprehensive audit logs
# of all tool usage with the actual Claude CLI.
#
# Run: mix run examples/hooks/logging_and_audit.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, ContentExtractor, Message, Options}
alias ClaudeAgentSDK.Hooks.Matcher
alias Examples.Support

Support.ensure_live!()
Support.header!("Hooks Example: Logging and Audit Trail (live)")

defmodule AuditHooks do
  @moduledoc """
  Hooks for comprehensive logging and audit trails.
  """

  @table :claude_agent_sdk_examples_logging_and_audit

  def table_name, do: @table

  @doc """
  PreToolUse hook that logs tool invocations.
  """
  def log_tool_invocation(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_input = input["tool_input"]

    _ = :ets.update_counter(@table, :pre, {2, 1}, {:pre, 0})
    :ets.insert(@table, {{:tool_seen, tool_name}, true})

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # Simulated logging (in real app, write to file or database)
    IO.puts("\n📝 [AUDIT LOG] #{timestamp}")
    IO.puts("   Event: Tool Invocation")
    IO.puts("   Tool: #{tool_name}")
    IO.puts("   ID: #{tool_use_id}")
    IO.puts("   Input: #{inspect(tool_input, limit: :infinity)}")

    # Don't modify behavior, just log
    %{}
  end

  @doc """
  PostToolUse hook that logs tool results.
  """
  def log_tool_result(input, tool_use_id, _context) do
    tool_name = input["tool_name"]
    tool_response = input["tool_response"]

    _ = :ets.update_counter(@table, :post, {2, 1}, {:post, 0})
    :ets.insert(@table, {{:tool_done, tool_name}, true})

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # Determine success/failure
    is_error = get_in(tool_response, ["is_error"]) || false
    status = if is_error, do: "FAILED", else: "SUCCESS"
    status_icon = if is_error, do: "❌", else: "✅"

    IO.puts("\n📝 [AUDIT LOG] #{timestamp}")
    IO.puts("   Event: Tool Completion")
    IO.puts("   Tool: #{tool_name}")
    IO.puts("   Status: #{status_icon} #{status}")
    IO.puts("   ID: #{tool_use_id}")

    %{}
  end
end

table = AuditHooks.table_name()

case :ets.whereis(table) do
  :undefined -> :ok
  tid -> :ets.delete(tid)
end

:ets.new(table, [:named_table, :public, :set])

# Configure hooks for comprehensive logging
hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&AuditHooks.log_tool_invocation/3])
  ],
  post_tool_use: [
    Matcher.new("*", [&AuditHooks.log_tool_result/3])
  ]
}

options = %Options{
  tools: ["Bash", "Read"],
  allowed_tools: ["Bash", "Read"],
  hooks: hooks,
  model: "haiku",
  max_turns: 2,
  permission_mode: :default
}

# Start client with hooks
{:ok, client} = Client.start_link(options)

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

audit_file = Path.join(System.tmp_dir!(), "claude_agent_sdk_audit_demo.txt")
File.write!(audit_file, "hello from hooks audit demo\n")

IO.puts("Running prompts that should trigger tool usage (and therefore hooks)...\n")

messages1 =
  run_prompt.("Use the Bash tool to run this exact command: echo 'Hello from audit example'")

messages2 =
  run_prompt.("Use the Read tool to read #{audit_file} and repeat its contents exactly.")

case Enum.find(messages1, &(&1.type == :result)) do
  %Message{subtype: :success} ->
    :ok

  %Message{subtype: other} ->
    raise "Bash audit run did not succeed (result subtype: #{inspect(other)})"

  nil ->
    raise "Bash audit run returned no result message."
end

case Enum.find(messages2, &(&1.type == :result)) do
  %Message{subtype: :success} ->
    :ok

  %Message{subtype: other} ->
    raise "Read audit run did not succeed (result subtype: #{inspect(other)})"

  nil ->
    raise "Read audit run returned no result message."
end

pre =
  case :ets.lookup(table, :pre) do
    [{:pre, n}] when is_integer(n) -> n
    _ -> 0
  end

post =
  case :ets.lookup(table, :post) do
    [{:post, n}] when is_integer(n) -> n
    _ -> 0
  end

if pre < 1 do
  raise "Expected at least 1 pre_tool_use hook invocation, but saw pre=#{pre}."
end

if post < 1 do
  raise "Expected at least 1 post_tool_use hook invocation, but saw post=#{post}."
end

# Clean up
if Process.alive?(client), do: Client.stop(client)
:ets.delete(table)

IO.puts("\nDone.")
Support.halt_if_runner!()
