#!/usr/bin/env elixir

# test_timeout.exs - Simple script to test Claude Agent SDK timeout

Mix.install([
  {:claude_agent_sdk, path: "."}
])

alias ClaudeAgentSDK.OptionBuilder

IO.puts("Testing Claude Agent SDK timeout...")
IO.puts("This will ask Claude to do something that takes a while.\n")

options =
  OptionBuilder.with_sonnet()
  |> Map.put(:max_turns, 10)
  # 75 minutes
  |> Map.put(:timeout_ms, 4_500_000)
  |> Map.put(:permission_mode, :accept_edits)

IO.puts("Options configured:")
IO.puts("  - Model: #{options.model}")
IO.puts("  - Max turns: #{options.max_turns}")
IO.puts("  - Timeout: #{options.timeout_ms}ms (#{div(options.timeout_ms, 60_000)} minutes)")
IO.puts("  - Permission mode: #{options.permission_mode}\n")

prompt = """
Please do the following tasks slowly and carefully:

1. Create 50 test files at /tmp/test_1.txt through /tmp/test_50.txt
2. Write "Test file number X" to each file (where X is the file number)
3. Read back every 10th file (test_10.txt, test_20.txt, etc.) to verify
4. Create a summary file at /tmp/test_summary.txt listing all 50 files
5. Read the summary file back

Take your time with each step. This is a timeout test to verify the SDK handles long-running tasks correctly.
"""

IO.puts("Sending prompt to Claude...")
IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

try do
  ClaudeAgentSDK.query(prompt, options)
  |> Enum.each(fn message ->
    case message.type do
      :assistant ->
        content =
          case message do
            %{data: %{message: %{"content" => content}}} when is_list(content) -> content
            %{raw: %{"message" => %{"content" => content}}} when is_list(content) -> content
            _ -> []
          end

        if is_list(content) do
          Enum.each(content, fn block ->
            case Map.get(block, "type") do
              "text" ->
                text = Map.get(block, "text", "")
                if text != "", do: IO.puts("\n#{text}")

              "tool_use" ->
                name = Map.get(block, "name", "unknown")
                IO.puts("\n🔧 Using tool: #{name}")

              _ ->
                :ok
            end
          end)
        end

      :result ->
        if message.subtype == :success do
          IO.puts("\n\n✅ Success!")
        else
          IO.puts("\n\n❌ Error: #{inspect(message.data)}")
        end

      _ ->
        :ok
    end
  end)

  IO.puts("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  IO.puts("✅ Test completed successfully!")
rescue
  e ->
    IO.puts("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("❌ Test failed with error:")
    IO.puts(Exception.format(:error, e, __STACKTRACE__))
end
