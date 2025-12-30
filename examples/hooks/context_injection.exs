#!/usr/bin/env elixir

# Example 2: Auto-inject Context with LIVE CLI
#
# This example demonstrates using hooks to automatically inject contextual
# information into conversations with the actual Claude CLI.
#
# Run: mix run examples/hooks/context_injection.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, ContentExtractor, Message, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias Examples.Support

Support.ensure_live!()
Support.header!("Hooks Example: Context Injection (live)")

defmodule ContextHooks do
  @moduledoc """
  Hooks for automatically adding contextual information.
  """

  @table :claude_agent_sdk_examples_context_injection

  def table_name, do: @table

  @doc """
  UserPromptSubmit hook that adds project context.

  Adds information about:
  - Current time
  - Current git branch
  - Working directory
  - Environment
  """
  def add_project_context(_input, _tool_use_id, _context) do
    _ = :ets.update_counter(@table, :injections, {2, 1}, {:injections, 0})

    # Get current time
    current_time = DateTime.utc_now() |> DateTime.to_string()

    # Get environment
    environment = System.get_env("MIX_ENV", "dev")

    context_text = """
    ## 📎 Auto-Injected Project Context

    **Timestamp:** #{current_time}
    **Environment:** #{environment}
    **Working Directory:** #{File.cwd!()}
    """

    IO.puts("\n✅ Context injected into conversation:")
    IO.puts(context_text)

    Output.add_context("UserPromptSubmit", context_text)
  end
end

# Configure hooks
hooks = %{
  user_prompt_submit: [
    Matcher.new(nil, [&ContextHooks.add_project_context/3])
  ]
}

# Note: We don't set max_turns here to match Python SDK behavior.
# Even without tool use, hooks still need proper turn handling.
options = %Options{
  allowed_tools: [],
  hooks: hooks,
  model: "haiku",
  permission_mode: :default
}

table = ContextHooks.table_name()

case :ets.whereis(table) do
  :undefined -> :ok
  tid -> :ets.delete(tid)
end

:ets.new(table, [:named_table, :public, :set])

# Start client with hooks
{:ok, client} = Client.start_link(options)

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
prompt = "What time is it and where am I? Use the injected context and answer in one sentence."
:ok = Client.send_message(client, prompt)
messages = Task.await(task, 60_000)

injections =
  case :ets.lookup(table, :injections) do
    [{:injections, n}] when is_integer(n) -> n
    _ -> 0
  end

if injections < 1 do
  raise "Expected user_prompt_submit hook to fire at least once, but saw #{injections}."
end

assistant_text =
  messages
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.join("\n")

if assistant_text == "" do
  raise "No assistant text returned; expected Claude to respond using injected context."
end

case Enum.find(messages, &(&1.type == :result)) do
  %Message{subtype: :success} -> :ok
  %Message{subtype: other} -> raise "Query did not succeed (result subtype: #{inspect(other)})"
  nil -> raise "No result message returned."
end

# Clean up
if Process.alive?(client), do: Client.stop(client)
:ets.delete(table)

IO.puts("\nDone.")
Support.halt_if_runner!()
