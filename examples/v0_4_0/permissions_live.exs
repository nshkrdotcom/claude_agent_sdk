#!/usr/bin/env elixir

# Permissions Live Example
# Demonstrates permission system with REAL Claude CLI usage
#
# Usage:
#   mix run.live examples/v0_4_0/permissions_live.exs

alias ClaudeAgentSDK.{Options, Client, ContentExtractor}
alias ClaudeAgentSDK.Permission.{Context, Result}

IO.puts("\n=== Permissions Live Example ===\n")
IO.puts("⚠️  This will make REAL API calls to Claude\n")

# Define permission callback with logging
permission_log = :ets.new(:perm_log, [:public, :bag])

permission_callback = fn context ->
  timestamp = DateTime.utc_now() |> DateTime.to_string()
  :ets.insert(permission_log, {timestamp, context.tool_name, context.tool_input})

  case {context.tool_name, context.tool_input} do
    {"Bash", %{"command" => cmd}} ->
      # Block dangerous commands
      if String.contains?(cmd, "rm -rf") do
        IO.puts("🚫 BLOCKED dangerous bash: #{cmd}")
        Result.deny("Dangerous rm -rf command not allowed", interrupt: true)
      else
        IO.puts("✅ ALLOWED bash: #{String.slice(cmd, 0..50)}")
        Result.allow()
      end

    {"Write", %{"file_path" => path}} ->
      # Log all writes
      IO.puts("📝 LOGGED write to: #{path}")
      Result.allow()

    tool ->
      IO.puts("✅ ALLOWED: #{tool}")
      Result.allow()
  end
end

# Start client with permissions
options =
  Options.new(
    permission_mode: :default,
    can_use_tool: permission_callback,
    max_turns: 10
  )

{:ok, client} = Client.start_link(options)
IO.puts("✅ Client started with permission controls\n")

# Task: Ask Claude to list files
IO.puts("📤 Asking Claude to list files in current directory...\n")

Client.send_message(
  client,
  "Please list the files in the current directory using bash. Just run 'ls -la' and show me the output."
)

Client.stream_messages(client)
|> Stream.take_while(fn msg -> msg["type"] != "result" end)
|> Stream.each(fn msg ->
  case msg do
    %{"type" => "assistant", "content" => content} when is_list(content) ->
      for block <- content do
        case block do
          %{"type" => "text", "text" => text} ->
            IO.puts("💬 Claude: #{text}")

          %{"type" => "tool_use", "name" => name, "input" => input} ->
            IO.puts("🛠️  Claude using: #{name}(#{inspect(input)})")

          _ ->
            :ok
        end
      end

    _ ->
      :ok
  end
end)
|> Stream.run()

IO.puts("\n✅ Task complete\n")

# Show permission log
IO.puts("📊 Permission Log:")
logs = :ets.tab2list(permission_log) |> Enum.reverse()
IO.puts("Total permission checks: #{length(logs)}\n")

for {timestamp, tool, input} <- logs do
  input_str =
    case input do
      %{"command" => cmd} -> cmd
      %{"file_path" => path} -> path
      other -> inspect(other) |> String.slice(0..50)
    end

  IO.puts("  [#{timestamp}] #{tool}: #{input_str}")
end

:ets.delete(permission_log)

# Demonstrate mode switching
IO.puts("\n🔄 Switching to plan mode (would require user approval)...")
Client.set_permission_mode(client, :plan)
IO.puts("✅ Mode switched to :plan")

Client.stop(client)

IO.puts("\n✅ Permissions Live Example complete!")
IO.puts("\nWhat happened:")
IO.puts("  1. Set up permission callback to log all tool usage")
IO.puts("  2. Claude tried to use bash to list files")
IO.puts("  3. Permission callback was invoked")
IO.puts("  4. Tool usage was logged")
IO.puts("  5. Command was allowed (safe ls command)")
IO.puts("\n💡 Permission callbacks let you audit, control, and modify all tool usage!")
