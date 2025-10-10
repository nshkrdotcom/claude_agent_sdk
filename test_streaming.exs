#!/usr/bin/env elixir

# Live test script for bidirectional streaming
# Tests TRUE character-by-character streaming with --include-partial-messages

Application.put_env(:claude_code_sdk, :use_mock, false)

alias ClaudeCodeSDK.Streaming

IO.puts("🔄 Testing Bidirectional Streaming (LIVE API)")
IO.puts("=" |> String.duplicate(60))
IO.puts("")
IO.puts("This tests TRUE character-by-character streaming.")
IO.puts("You should see text appear word-by-word as Claude types.")
IO.puts("")
IO.puts("⚠️  This will make a LIVE API call and incur costs.")
IO.puts("")
IO.write("Press Enter to continue (or Ctrl+C to cancel)... ")
IO.gets("")

IO.puts("")
IO.puts("🚀 Starting streaming session...")

case Streaming.start_session(%ClaudeCodeSDK.Options{max_turns: 1}) do
  {:ok, session} ->
    IO.puts("✅ Session started!")

    # Check session ID
    case Streaming.get_session_id(session) do
      {:ok, session_id} ->
        IO.puts("   Session ID: #{session_id}")

      {:error, :no_session_id} ->
        IO.puts("   ⏳ Session ID will be available after first message")
    end

    IO.puts("")
    IO.puts("📤 Sending message: 'Count from 1 to 10'")
    IO.puts("📥 Streaming response:")
    IO.puts("")
    IO.write("Claude: ")

    # Collect statistics
    start_time = System.monotonic_time(:millisecond)

    stats = %{
      total_events: 0,
      text_deltas: 0,
      total_chars: 0,
      first_char_time: nil,
      last_char_time: nil
    }

    try do
      final_stats =
        Streaming.send_message(session, "Count from 1 to 10")
        |> Enum.reduce(stats, fn event, acc ->
          now = System.monotonic_time(:millisecond)

          case event do
            %{type: :text_delta, text: text} ->
              # Display immediately (typewriter effect!)
              IO.write(text)

              first_time = acc.first_char_time || now

              %{
                acc
                | total_events: acc.total_events + 1,
                  text_deltas: acc.text_deltas + 1,
                  total_chars: acc.total_chars + String.length(text),
                  first_char_time: first_time,
                  last_char_time: now
              }

            %{type: :message_start} ->
              %{acc | total_events: acc.total_events + 1}

            %{type: :message_stop} ->
              %{acc | total_events: acc.total_events + 1}

            %{type: :error, error: reason} ->
              IO.puts("")
              IO.puts("")
              IO.puts("❌ Error: #{inspect(reason)}")
              %{acc | total_events: acc.total_events + 1}

            _other ->
              %{acc | total_events: acc.total_events + 1}
          end
        end)

      end_time = System.monotonic_time(:millisecond)

      IO.puts("")
      IO.puts("")
      IO.puts("📊 Statistics:")
      IO.puts("   Total events: #{final_stats.total_events}")
      IO.puts("   Text delta events: #{final_stats.text_deltas}")
      IO.puts("   Total characters: #{final_stats.total_chars}")
      IO.puts("   Total duration: #{end_time - start_time}ms")

      if final_stats.first_char_time && final_stats.last_char_time do
        streaming_duration = final_stats.last_char_time - final_stats.first_char_time
        IO.puts("   Streaming duration: #{streaming_duration}ms")
        IO.puts("   Time to first char: #{final_stats.first_char_time - start_time}ms")

        if final_stats.total_chars > 0 && streaming_duration > 0 do
          chars_per_sec = final_stats.total_chars / (streaming_duration / 1000)
          IO.puts("   Streaming rate: #{Float.round(chars_per_sec, 1)} chars/sec")
        end
      end

      IO.puts("")

      if final_stats.text_deltas > 1 do
        IO.puts("✅ STREAMING WORKING! Got #{final_stats.text_deltas} partial chunks")
        IO.puts("   (If you only got 1 chunk, streaming might not be enabled)")
      else
        IO.puts("⚠️  Only got #{final_stats.text_deltas} text delta(s)")
        IO.puts("   This might indicate streaming is not working properly.")
      end

      # Test multi-turn conversation
      IO.puts("")
      IO.puts("🔄 Testing multi-turn conversation...")
      IO.write("Claude: ")

      Streaming.send_message(session, "What did I just ask you to do?")
      |> Stream.each(fn
        %{type: :text_delta, text: text} -> IO.write(text)
        %{type: :message_stop} -> IO.puts("")
        # Ignore other events
        _ -> :ok
      end)
      |> Stream.run()

      # Close session
      :ok = Streaming.close_session(session)
      IO.puts("")
      IO.puts("✅ Session closed cleanly")
      IO.puts("")
      IO.puts("=" |> String.duplicate(60))
      IO.puts("🎉 Test complete! Bidirectional streaming is working.")
    rescue
      e ->
        IO.puts("")
        IO.puts("")
        IO.puts("❌ Test failed: #{Exception.message(e)}")
        IO.puts("")
        IO.puts(Exception.format_stacktrace(__STACKTRACE__))

        # Try to close session
        try do
          Streaming.close_session(session)
        catch
          _, _ -> :ok
        end

        System.halt(1)
    end

  {:error, reason} ->
    IO.puts("❌ Failed to start session: #{inspect(reason)}")
    IO.puts("")
    IO.puts("Possible causes:")
    IO.puts("  - Claude CLI not installed (run: npm install -g @anthropic-ai/claude-code)")
    IO.puts("  - Not authenticated (run: claude login)")
    IO.puts("  - Subprocess spawn failed")
    IO.puts("")
    System.halt(1)
end
