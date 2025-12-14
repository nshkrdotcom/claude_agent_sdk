#!/usr/bin/env elixir
# Permissions Example (LIVE)
# Demonstrates permission callbacks with real Claude CLI tool use.
#
# Run: mix run examples/advanced_features/permissions_live.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Options, ContentExtractor}
alias ClaudeAgentSDK.Permission.Result
alias Examples.Support

Support.ensure_live!()
Support.header!("Permissions Example (live)")

# We keep all example output under examples/_output so the repo stays clean.
output_dir = Support.output_dir!()
target_file = Path.join(output_dir, "permissions_demo.txt")

IO.puts("Output dir: #{output_dir}")
IO.puts("Target file: #{target_file}\n")

# Define permission callback with logging
permission_log = :ets.new(:perm_log, [:public, :bag])

permission_callback = fn context ->
  timestamp = DateTime.utc_now() |> DateTime.to_string()
  :ets.insert(permission_log, {timestamp, context.tool_name, context.tool_input})

  case {context.tool_name, context.tool_input} do
    {"Write", %{"file_path" => path} = input} ->
      # Keep writes inside our examples output directory. If a different path is
      # requested, rewrite it to `target_file`.
      if String.starts_with?(to_string(path), output_dir) do
        IO.puts("📝 ALLOWED write to: #{path}")
        Result.allow()
      else
        IO.puts("📝 REDIRECTED write: #{path} → #{target_file}")
        Result.allow(updated_input: Map.put(input, "file_path", target_file))
      end

    {tool, _input} ->
      IO.puts("✅ ALLOWED: #{tool}")
      Result.allow()
  end
end

IO.puts("✅ Permission callback configured\n")

try do
  # Create options with permissions
  options =
    Options.new(
      # Use :plan to ensure the CLI issues can_use_tool permission requests.
      permission_mode: :plan,
      can_use_tool: permission_callback,
      model: "haiku",
      max_turns: 2,
      tools: ["Write"],
      allowed_tools: ["Write"]
    )

  # Task: Ask Claude to write a small file
  prompt = """
  Use the Write tool to create a file with the exact path and content below.

  file_path: #{target_file}
  content: hello from permissions example

  After the write completes, reply with exactly: WROTE
  """

  IO.puts("📤 Asking Claude to write a file...\n")
  IO.puts("Prompt: #{prompt}\n")

  # Execute query
  messages =
    ClaudeAgentSDK.query(prompt, options)
    |> Enum.to_list()

  # Extract and display response
  text =
    messages
    |> Enum.filter(&(&1.type == :assistant))
    |> Enum.map(&ContentExtractor.extract_text/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")

  if text != "" do
    IO.puts("💬 Claude's Response:")
    IO.puts("─" |> String.duplicate(60))
    IO.puts(String.slice(text, 0..300))
    if String.length(text) > 300, do: IO.puts("... (truncated)")
    IO.puts("─" |> String.duplicate(60))
  end

  IO.puts("\n✅ Task complete\n")

  case File.read(target_file) do
    {:ok, contents} ->
      preview = contents |> String.trim() |> String.slice(0..120)
      IO.puts("✅ File written: #{target_file}")
      IO.puts("   Content preview: #{inspect(preview)}\n")

    {:error, reason} ->
      raise "Expected file was not written: #{target_file} (#{inspect(reason)})"
  end

  # Show permission log
  IO.puts("📊 Permission Log:")
  logs = :ets.tab2list(permission_log) |> Enum.reverse()
  IO.puts("Total permission checks: #{length(logs)}\n")

  if logs == [] do
    IO.puts("⚠️  No permission requests were observed.")
    IO.puts("    This usually means the CLI did not issue can_use_tool requests.")
    IO.puts("    Verify your CLI supports permission callbacks and try again.\n")
  end

  for {timestamp, tool, input} <- logs do
    input_str =
      case input do
        %{"file_path" => path} -> "file: #{path}"
        other -> inspect(other) |> String.slice(0..40)
      end

    time_short = timestamp |> String.slice(11..18)
    IO.puts("  [#{time_short}] #{tool}: #{input_str}")
  end

  IO.puts("\n✅ Permissions Live Example complete!")
  IO.puts("\nWhat happened:")
  IO.puts("  1. Set up permission callback to log all tool usage")
  IO.puts("  2. Claude used bash to list files")
  IO.puts("  3. Permission callback was invoked for each tool use")
  IO.puts("  4. Tool usage was logged for audit trail")
  IO.puts("  5. Safe commands were allowed, dangerous would be blocked")
  IO.puts("\n💡 Permission callbacks give you:")
  IO.puts("  - Complete audit trail of all tool usage")
  IO.puts("  - Ability to block dangerous operations")
  IO.puts("  - Ability to redirect file paths to safe locations")
  IO.puts("  - Runtime control over what Claude can do")
after
  :ets.delete(permission_log)
end

Support.halt_if_runner!()
