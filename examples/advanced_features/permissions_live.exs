#!/usr/bin/env elixir
# Permissions Example (LIVE)
# NOTE: Permission callbacks are currently disabled in this example due to CLI
# builds that do not emit can_use_tool callbacks. This script now verifies Write
# tool execution only.
#
# IMPORTANT: Streaming mode is still used to exercise tool execution.
#
# Run: mix run examples/advanced_features/permissions_live.exs

Code.require_file(Path.expand("../support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{Streaming, Options}
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

IO.puts("NOTE: Permission callbacks are disabled in this example.")
IO.puts("Reason: some CLI builds do not emit can_use_tool callbacks.\n")

# Create options with permissions - use streaming mode for control protocol
# IMPORTANT: Include Write in allowed_tools so the CLI exposes the tool. Use
# :default to keep built-in tool execution in the CLI.
options = %Options{
  model: "haiku",
  max_turns: 3,
  tools: ["Write"],
  allowed_tools: ["Write"]
}

wait_for_file = fn path, attempts, delay_ms ->
  Enum.reduce_while(1..attempts, {:error, :not_found}, fn _idx, _acc ->
    case File.stat(path) do
      {:ok, _} ->
        {:halt, :ok}

      {:error, _} ->
        Process.sleep(delay_ms)
        {:cont, {:error, :not_found}}
    end
  end)
end

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

session_type =
  case session do
    {:control_client, _pid} -> :control_client
    _pid when is_pid(session) -> :streaming_session
  end

session_label =
  case session_type do
    :control_client -> "control client mode"
    :streaming_session -> "CLI streaming mode"
  end

exit_code =
  try do
    IO.puts("✓ Session started (#{session_label})\n")
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
      case session_type do
        :control_client ->
          raise "No Write tool_use_start observed in stream."

        :streaming_session ->
          IO.puts("⚠️  No Write tool_use_start observed in stream.")
      end
    end

    case wait_for_file.(target_file, 15, 200) do
      :ok -> :ok
      {:error, :not_found} -> :error
    end
    |> case do
      :ok -> File.read(target_file)
      :error -> {:error, :not_found}
    end
    |> case do
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

    IO.puts("\nPermissions Live Example complete!")
    IO.puts("\nWhat happened:")
    IO.puts("  1. Started streaming session (#{session_label})")
    IO.puts("  2. Asked Claude to write a file")
    IO.puts("  3. Observed Write tool use in stream")
    IO.puts("  4. Verified file contents")
    0
  rescue
    error ->
      message = Exception.message(error) |> String.trim_trailing()
      IO.puts("\nERROR:\n#{message}")
      1
  after
    Streaming.close_session(session)
  end

Support.halt_if_runner!(exit_code)

if exit_code != 0 do
  System.halt(exit_code)
end
