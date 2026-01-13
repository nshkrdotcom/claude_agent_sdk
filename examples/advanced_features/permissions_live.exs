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

cli_version =
  case ClaudeAgentSDK.CLI.version() do
    {:ok, version} -> version
    _ -> "unknown"
  end

IO.puts("Output dir: #{output_dir}")
IO.puts("Target file: #{target_file}")
IO.puts("Claude CLI version: #{cli_version}\n")

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
# IMPORTANT: Include Write in allowed_tools so the CLI exposes the tool. Use
# :default to keep built-in tool execution in the CLI.
options = %Options{
  permission_mode: :default,
  can_use_tool: permission_callback,
  model: "haiku",
  max_turns: 3,
  tools: ["Write"],
  allowed_tools: ["Write"]
}

# Task: Ask Claude to write a small file
prompt = """
Use the Write tool to create a file with the exact path and content below.

file_path: #{target_file}
content: hello from permissions example
"""

IO.puts("📤 Asking Claude to write a file...\n")
IO.puts("Prompt: #{prompt}\n")

# Use streaming mode - this enables bidirectional control protocol required for
# permission callbacks (matches Python SDK's ClaudeSDKClient pattern)
{:ok, session} = Streaming.start_session(options)

if not match?({:control_client, _pid}, session) do
  raise "Expected control client session, got: #{inspect(session)}"
end

exit_code =
  try do
    IO.puts("✓ Session started (control client mode)\n")
    IO.puts("-" |> String.duplicate(60))

    # Track if we received any text response
    summary =
      Streaming.send_message(session, prompt)
      |> Enum.reduce_while(%{text: "", saw_message_stop: false, saw_write: false}, fn event,
                                                                                      acc ->
        case event do
          %{type: :text_delta, text: text} ->
            IO.write(text)
            {:cont, %{acc | text: acc.text <> text}}

          %{type: :tool_use_start, name: "Write"} ->
            {:cont, %{acc | saw_write: true}}

          %{type: :message_stop} ->
            IO.puts("\n" <> ("-" |> String.duplicate(60)))
            {:halt, %{acc | saw_message_stop: true}}

          %{type: :error, error: error} ->
            raise "Streaming error: #{inspect(error)}"

          _ ->
            {:cont, acc}
        end
      end)

    IO.puts("\n✅ Task complete\n")

    if not summary.saw_message_stop do
      raise "Stream ended without message_stop."
    end

    if not summary.saw_write do
      raise "No Write tool_use_start observed in stream."
    end

    case File.read(target_file) do
      {:ok, contents} ->
        preview = contents |> String.trim() |> String.slice(0..120)
        IO.puts("✅ File written: #{target_file}")
        IO.puts("   Content preview: #{inspect(preview)}\n")

        if String.trim(contents) != "hello from permissions example" do
          raise "Unexpected file contents: #{inspect(contents)}"
        end

      {:error, reason} ->
        raise "File was not written: #{target_file} (#{inspect(reason)})"
    end

    # Show permission log
    IO.puts("📊 Permission Log:")
    logs = :ets.tab2list(permission_log) |> Enum.reverse()
    IO.puts("Total permission checks: #{length(logs)}\n")

    if logs == [] do
      raise """
      No permission requests were observed.
      This indicates the CLI did not emit can_use_tool or hook callbacks for tool usage.
      CLI version: #{cli_version}
      """
    end

    if not Enum.any?(logs, fn {_timestamp, tool, _input} -> tool == "Write" end) do
      raise "Permission log did not include a Write tool request."
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
    IO.puts("  2. Started streaming session (control client mode)")
    IO.puts("  3. Asked Claude to write a file")
    IO.puts("  4. Permission callback was invoked for tool use requests")
    IO.puts("  5. Tool usage was logged for audit trail")
    IO.puts("\n💡 Permission callbacks give you:")
    IO.puts("  - Complete audit trail of all tool usage")
    IO.puts("  - Ability to block dangerous operations")
    IO.puts("  - Ability to redirect file paths to safe locations")
    IO.puts("  - Runtime control over what Claude can do")
    0
  rescue
    error ->
      message = Exception.message(error) |> String.trim_trailing()
      IO.puts("\nERROR:\n#{message}")
      1
  after
    Streaming.close_session(session)
    :ets.delete(permission_log)
  end

Support.halt_if_runner!(exit_code)

if exit_code != 0 do
  System.halt(exit_code)
end
