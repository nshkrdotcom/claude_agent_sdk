#!/usr/bin/env elixir

# Example 3: File Policy Enforcement with LIVE CLI
#
# Demonstrates enforcing file access policies via `pre_tool_use` hooks:
# - allow writes/edits inside a sandbox directory
# - deny writes to sensitive filenames (e.g. `.env`)
# - deny writes outside the sandbox
#
# Run: mix run examples/hooks/file_policy_enforcement.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, ContentExtractor, Message, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias Examples.Support

Support.ensure_live!()
Support.header!("Hooks Example: File Policy Enforcement (live)")

defmodule FilePolicyHooks do
  @moduledoc false

  @table :claude_agent_sdk_examples_file_policy_enforcement
  @forbidden_files [".env", "secrets.yml", "credentials.json"]

  def table_name, do: @table

  def put_allowed_dir!(dir) when is_binary(dir) do
    :ets.insert(@table, {:allowed_dir, dir})
  end

  defp allowed_dir do
    case :ets.lookup(@table, :allowed_dir) do
      [{:allowed_dir, dir}] when is_binary(dir) -> dir
      _ -> "/tmp"
    end
  end

  defp inc(key) when is_atom(key) do
    _ = :ets.update_counter(@table, key, {2, 1}, {key, 0})
    :ok
  end

  def enforce_file_policy(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => tool, "tool_input" => %{"file_path" => path}}
      when tool in ["Write", "Edit"] and is_binary(path) ->
        check_write_policy(tool, path)

      _ ->
        %{}
    end
  end

  defp check_write_policy(tool_name, path) do
    cond do
      Enum.any?(@forbidden_files, &String.ends_with?(path, &1)) ->
        inc(:denied)
        filename = Path.basename(path)
        IO.puts("\n🚫 BLOCKED: Cannot modify #{filename}")

        Output.deny("Cannot modify #{filename}")
        |> Output.with_system_message("🔒 Security policy: Sensitive file")
        |> Output.with_reason("Modification of #{filename} is forbidden by policy")

      not String.starts_with?(path, allowed_dir()) ->
        inc(:denied)
        dir = allowed_dir()
        IO.puts("\n🚫 BLOCKED: Must operate within #{dir}")

        Output.deny("Can only modify files in #{dir}")
        |> Output.with_system_message("🔒 Security policy: Sandbox restriction")
        |> Output.with_reason("File path #{path} is outside allowed directory")

      true ->
        inc(:allowed)
        IO.puts("\n✅ ALLOWED: #{tool_name} #{path}")
        Output.allow("File policy check passed")
    end
  end
end

table = FilePolicyHooks.table_name()

case :ets.whereis(table) do
  :undefined -> :ok
  tid -> :ets.delete(tid)
end

:ets.new(table, [:named_table, :public, :set])

sandbox_dir =
  Path.join(
    System.tmp_dir!(),
    "claude_agent_sdk_file_policy_#{System.unique_integer([:positive])}"
  )

File.mkdir_p!(sandbox_dir)
FilePolicyHooks.put_allowed_dir!(sandbox_dir)

outside_dir =
  Path.join(
    System.tmp_dir!(),
    "claude_agent_sdk_file_policy_outside_#{System.unique_integer([:positive])}"
  )

File.mkdir_p!(outside_dir)

ok_file = Path.join(sandbox_dir, "ok.txt")
env_file = Path.join(sandbox_dir, ".env")
outside_file = Path.join(outside_dir, "outside.txt")

hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&FilePolicyHooks.enforce_file_policy/3])
  ]
}

options = %Options{
  tools: ["Write", "Edit"],
  allowed_tools: ["Write", "Edit"],
  hooks: hooks,
  model: "haiku",
  max_turns: 2,
  permission_mode: :default
}

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

IO.puts("Sandbox directory: #{sandbox_dir}\n")

IO.puts("Test 1: Allowed write within sandbox\n")

messages1 =
  run_prompt.("""
  Use the Write tool to create a file at #{ok_file}.
  Put exactly this content (including the newline): ok
  """)

IO.puts("\nTest 2: Denied write to sensitive filename (.env)\n")

messages2 =
  run_prompt.("""
  Use the Write tool to create a file at #{env_file}.
  Put exactly: SECRET=1
  """)

IO.puts("\nTest 3: Denied write outside sandbox\n")

messages3 =
  run_prompt.("""
  Use the Write tool to create a file at #{outside_file}.
  Put exactly: outside
  """)

for {label, msgs} <- [
      {"allowed write", messages1},
      {"sensitive file", messages2},
      {"outside write", messages3}
    ] do
  case Enum.find(msgs, &(&1.type == :result)) do
    %Message{subtype: :success} ->
      :ok

    %Message{subtype: other} ->
      raise "Run #{label} did not succeed (result subtype: #{inspect(other)})"

    nil ->
      raise "Run #{label} returned no result message."
  end
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
  raise "Expected at least 1 allowed file operation, but allowed=#{allowed}."
end

if denied < 2 do
  raise "Expected at least 2 denied file operations, but denied=#{denied}."
end

case File.read(ok_file) do
  {:ok, contents} ->
    if String.trim_trailing(contents) != "ok" do
      raise "Expected #{ok_file} to contain \"ok\", got: #{inspect(contents)}"
    end

  {:error, reason} ->
    raise "Expected #{ok_file} to exist, but read failed: #{inspect(reason)}"
end

if File.exists?(env_file) do
  raise "Expected #{env_file} to be blocked and not written, but it exists."
end

if File.exists?(outside_file) do
  raise "Expected #{outside_file} to be blocked and not written, but it exists."
end

IO.puts("\n✅ File policy enforcement checks passed (allowed=#{allowed}, denied=#{denied}).")

Client.stop(client)
:ets.delete(table)

IO.puts("\nDone.")
Support.halt_if_runner!()
