#!/usr/bin/env elixir
# Permissions Example (LIVE)
# Demonstrates permission callbacks with real Claude CLI tool use.
#
# IMPORTANT: Permission callbacks require streaming mode (like Python SDK's ClaudeSDKClient).
# This example uses Streaming.start_session/1 to ensure the control protocol is active.
#
# Run: mix run examples/advanced_features/permissions_live.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Streaming, Options}
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

# Create options with permissions - use streaming mode for control protocol
# IMPORTANT: Do NOT include Write in allowed_tools - otherwise the CLI auto-approves
# without calling the permission callback!
options = %Options{
  permission_mode: :default,
  can_use_tool: permission_callback,
  model: "haiku",
  max_turns: 2,
  tools: ["Write"]
  # NOTE: allowed_tools is intentionally omitted so CLI must ask permission
}

# Task: Ask Claude to write a small file
prompt = """
Use the Write tool to create a file with the exact path and content below.

file_path: #{target_file}
content: hello from permissions example

After the write completes, reply with exactly: WROTE
"""

IO.puts("📤 Asking Claude to write a file...\n")
IO.puts("Prompt: #{prompt}\n")

# Use streaming mode - this enables bidirectional control protocol required for
# permission callbacks (matches Python SDK's ClaudeSDKClient pattern)
{:ok, session} = Streaming.start_session(options)

try do
  IO.puts("✓ Session started (control client mode)\n")
  IO.puts("-" |> String.duplicate(60))

  # Track if we received any text response
  response_text =
    Streaming.send_message(session, prompt)
    |> Enum.reduce_while("", fn event, acc ->
      case event do
        %{type: :text_delta, text: text} ->
          IO.write(text)
          {:cont, acc <> text}

        %{type: :message_stop} ->
          IO.puts("\n" <> ("-" |> String.duplicate(60)))
          {:halt, acc}

        %{type: :error, error: error} ->
          raise "Streaming error: #{inspect(error)}"

        _ ->
          {:cont, acc}
      end
    end)

  IO.puts("\n✅ Task complete\n")

  case File.read(target_file) do
    {:ok, contents} ->
      preview = contents |> String.trim() |> String.slice(0..120)
      IO.puts("✅ File written: #{target_file}")
      IO.puts("   Content preview: #{inspect(preview)}\n")

    {:error, reason} ->
      IO.puts("⚠️  File was not written: #{target_file} (#{inspect(reason)})")
      IO.puts("   This may indicate the CLI did not use the Write tool.\n")
      IO.puts("   Response was: #{String.slice(response_text, 0..200)}\n")
  end

  # Show permission log
  IO.puts("📊 Permission Log:")
  logs = :ets.tab2list(permission_log) |> Enum.reverse()
  IO.puts("Total permission checks: #{length(logs)}\n")

  if logs == [] do
    cli_version =
      case ClaudeAgentSDK.CLI.version() do
        {:ok, v} -> v
        _ -> "unknown"
      end

    IO.puts("⚠️  No permission requests were observed.")
    IO.puts("    CLI version: #{cli_version}")
    IO.puts("    This may indicate the CLI does not support --permission-prompt-tool stdio.")
    IO.puts("    The SDK sends can_use_tool requests via control protocol, but the CLI")
    IO.puts("    must send control_request with subtype 'can_use_tool' for callbacks to work.\n")
  else
    for {timestamp, tool, input} <- logs do
      input_str =
        case input do
          %{"file_path" => path} -> "file: #{path}"
          other -> inspect(other) |> String.slice(0..40)
        end

      time_short = timestamp |> String.slice(11..18)
      IO.puts("  [#{time_short}] #{tool}: #{input_str}")
    end
  end

  IO.puts("\n✅ Permissions Live Example complete!")
  IO.puts("\nWhat happened:")
  IO.puts("  1. Set up permission callback to log all tool usage")
  IO.puts("  2. Started streaming session (control client mode)")
  IO.puts("  3. Asked Claude to write a file")
  IO.puts("  4. Permission callback was invoked for tool use requests")
  IO.puts("  5. Tool usage was logged for audit trail")
  IO.puts("\n💡 Permission callbacks give you:")
  IO.puts("  - Complete audit trail of all tool usage")
  IO.puts("  - Ability to block dangerous operations")
  IO.puts("  - Ability to redirect file paths to safe locations")
  IO.puts("  - Runtime control over what Claude can do")
after
  Streaming.close_session(session)
  :ets.delete(permission_log)
end

Support.halt_if_runner!()
