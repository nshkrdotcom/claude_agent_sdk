#!/usr/bin/env elixir

# Example: Complete Workflow - All Hooks Together with LIVE CLI
#
# Demonstrates multiple hooks working together to build a secure, audited workflow:
# - `user_prompt_submit` context injection
# - `pre_tool_use` audit logging + security allow/deny
# - `post_tool_use` monitoring
#
# Run: mix run examples/hooks/complete_workflow.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Client, ContentExtractor, Message, Options}
alias ClaudeAgentSDK.Hooks.{Matcher, Output}
alias Examples.Support

Support.ensure_live!()
Support.header!("Hooks Example: Complete Workflow (live)")

defmodule CompleteWorkflowHooks do
  @moduledoc false

  @table :claude_agent_sdk_examples_complete_workflow
  # Use "blocked.sh" pattern (like Python SDK's "./foo.sh") instead of dangerous
  # commands like "rm -rf" because Claude's built-in safety may refuse those
  # before the hook is even invoked.
  @forbidden_patterns ["blocked.sh"]

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

  # PreToolUse: audit log (always allow)
  def audit_log(input, tool_use_id, _context) do
    inc(:pre)
    tool = input["tool_name"]
    IO.puts("\n📝 [AUDIT] tool=#{tool} id=#{tool_use_id}")
    %{}
  end

  # PreToolUse: security validation (allow/deny)
  def security_validation(input, _tool_use_id, _context) do
    case input do
      %{"tool_name" => "Bash", "tool_input" => %{"command" => cmd}} when is_binary(cmd) ->
        if Enum.any?(@forbidden_patterns, &String.contains?(cmd, &1)) do
          inc(:denied)
          IO.puts("\n🚫 SECURITY: Blocked command by policy: #{cmd}")

          Output.deny("Command blocked by security policy")
          |> Output.with_system_message("🔒 Security policy violation")
        else
          inc(:allowed)
          IO.puts("\n✅ SECURITY: Approved bash command")
          Output.allow("Security check passed")
        end

      %{"tool_name" => "Write", "tool_input" => %{"file_path" => path}} when is_binary(path) ->
        if String.starts_with?(path, allowed_dir()) do
          inc(:allowed)
          IO.puts("\n✅ SECURITY: Approved file write: #{path}")
          Output.allow("Sandbox check passed")
        else
          inc(:denied)
          IO.puts("\n🚫 SECURITY: Blocked write outside sandbox: #{path}")

          Output.deny("Must operate within #{allowed_dir()}")
          |> Output.with_system_message("🔒 Sandbox restriction")
        end

      _ ->
        %{}
    end
  end

  # UserPromptSubmit: context injection
  def add_context(_input, _tool_use_id, _context) do
    inc(:context)

    context_text = """
    ## 🔒 Security Context
    - Bash restricted: #{Enum.join(@forbidden_patterns, ", ")}
    - Writes sandboxed to: #{allowed_dir()}
    """

    Output.add_context("UserPromptSubmit", context_text)
  end

  # PostToolUse: monitoring
  def monitor_execution(input, tool_use_id, _context) do
    inc(:post)
    tool = input["tool_name"]
    is_error = get_in(input, ["tool_response", "is_error"]) || false
    status = if is_error, do: "❌", else: "✅"
    IO.puts("\n📊 MONITOR: tool=#{tool} #{status} id=#{tool_use_id}")
    %{}
  end
end

table = CompleteWorkflowHooks.table_name()
sandbox_dir = Support.tmp_dir!("claude_agent_sdk_complete_workflow")
client = nil

try do
  case :ets.whereis(table) do
    :undefined -> :ok
    tid -> :ets.delete(tid)
  end

  :ets.new(table, [:named_table, :public, :set])

  CompleteWorkflowHooks.put_allowed_dir!(sandbox_dir)

  hooks = %{
    pre_tool_use: [
      Matcher.new("*", [
        &CompleteWorkflowHooks.audit_log/3,
        &CompleteWorkflowHooks.security_validation/3
      ])
    ],
    user_prompt_submit: [
      Matcher.new(nil, [&CompleteWorkflowHooks.add_context/3])
    ],
    post_tool_use: [
      Matcher.new("*", [&CompleteWorkflowHooks.monitor_execution/3])
    ]
  }

  # Note: We don't set max_turns here to match Python SDK behavior.
  # With hooks enabled, the conversation needs multiple turns for tool use + response.
  options = %Options{
    tools: ["Bash", "Write"],
    allowed_tools: ["Bash", "Write"],
    hooks: hooks,
    model: "haiku",
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
    Task.await(task, 180_000)
  end

  IO.puts("Sandbox directory: #{sandbox_dir}\n")

  IO.puts("Test 1: Safe bash command\n")

  messages1 =
    run_prompt.(
      "Use the Bash tool to run this exact command: echo 'hello from complete workflow'"
    )

  IO.puts("\nTest 2: Sandboxed file write\n")

  messages2 =
    run_prompt.(
      "Use the Write tool to write exactly 'ok' to #{Path.join(sandbox_dir, "ok.txt")}."
    )

  IO.puts("\nTest 3: Blocked bash command (should be denied by hook)\n")

  messages3 =
    run_prompt.("Use the Bash tool to run this exact command: ./blocked.sh --help")

  for {label, msgs} <- [
        {"safe bash", messages1},
        {"sandbox write", messages2},
        {"blocked bash", messages3}
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

  pre =
    :ets.lookup(table, :pre)
    |> then(fn
      [{:pre, n}] when is_integer(n) -> n
      _ -> 0
    end)

  post =
    :ets.lookup(table, :post)
    |> then(fn
      [{:post, n}] when is_integer(n) -> n
      _ -> 0
    end)

  ctx =
    :ets.lookup(table, :context)
    |> then(fn
      [{:context, n}] when is_integer(n) -> n
      _ -> 0
    end)

  allowed =
    :ets.lookup(table, :allowed)
    |> then(fn
      [{:allowed, n}] when is_integer(n) -> n
      _ -> 0
    end)

  denied =
    :ets.lookup(table, :denied)
    |> then(fn
      [{:denied, n}] when is_integer(n) -> n
      _ -> 0
    end)

  if ctx < 1 do
    raise "Expected user_prompt_submit hook to fire, but context=#{ctx}."
  end

  if pre < 2 do
    raise "Expected pre_tool_use hooks to fire at least twice, but pre=#{pre}."
  end

  if post < 1 do
    raise "Expected post_tool_use hook to fire at least once, but post=#{post}."
  end

  if allowed < 1 or denied < 1 do
    raise "Expected at least one allowed and one denied decision, but allowed=#{allowed} denied=#{denied}."
  end

  IO.puts(
    "\n✅ Complete workflow checks passed (pre=#{pre} post=#{post} ctx=#{ctx} allowed=#{allowed} denied=#{denied})."
  )

  IO.puts("\nDone.")
after
  if is_pid(client) and Process.alive?(client), do: Client.stop(client)

  case :ets.whereis(table) do
    :undefined -> :ok
    tid -> :ets.delete(tid)
  end

  Support.cleanup_tmp_dir(sandbox_dir)
end

Support.halt_if_runner!()
