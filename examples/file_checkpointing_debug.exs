#!/usr/bin/env elixir
# Debug script to investigate file checkpointing ID discovery
#
# Run with: mix run examples/file_checkpointing_debug.exs
#
# KEY FINDING (2025-12-13):
# The CLI 2.0.69 is NOT creating file checkpoints. All rewind attempts fail with
# "No file checkpoint found" even though:
#   - The env var CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING is correctly set to "true"
#   - User messages DO contain a `uuid` field in the raw JSON
#   - The control request format is correct
#
# The Python SDK itself has a bug: it tells users to use msg.uuid but UserMessage
# has no uuid field. The feature appears to be incomplete in both SDKs.

alias ClaudeAgentSDK.{CLI, Client, ContentExtractor, Options}

defmodule FileCheckpointingDebug do
  def run do
    IO.puts("=" |> String.duplicate(60))
    IO.puts("FILE CHECKPOINTING DEBUG SESSION")
    IO.puts("=" |> String.duplicate(60))

    # 1. Verify CLI setup
    verify_cli_setup()

    # 2. Create demo directory with proper git setup
    demo_dir = create_demo_directory()

    # 3. Run the checkpointing test with full debug output
    run_checkpointing_test(demo_dir)
  end

  defp verify_cli_setup do
    IO.puts("\n--- CLI VERIFICATION ---")
    IO.inspect(CLI.find_executable(), label: "CLI executable")
    IO.inspect(CLI.version(), label: "CLI version")

    IO.puts("\nEnvironment variable check:")
    IO.puts("  CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING would be set to 'true'")
  end

  defp create_demo_directory do
    demo_dir =
      Path.join(
        System.tmp_dir!(),
        "claude_checkpoint_debug_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(demo_dir)
    IO.puts("\n--- DEMO DIRECTORY ---")
    IO.puts("Path: #{demo_dir}")

    # Create baseline file BEFORE git init
    baseline_file = Path.join(demo_dir, "demo.txt")
    File.write!(baseline_file, "# baseline content\n")
    IO.puts("Created baseline file: demo.txt")

    # Initialize git repo
    if System.find_executable("git") do
      {_, 0} = System.cmd("git", ["init", "--quiet", "--initial-branch=main"], cd: demo_dir)
      {_, 0} = System.cmd("git", ["config", "user.email", "debug@example.com"], cd: demo_dir)
      {_, 0} = System.cmd("git", ["config", "user.name", "Debug"], cd: demo_dir)
      File.write!(Path.join(demo_dir, ".gitignore"), "")
      {_, 0} = System.cmd("git", ["add", "."], cd: demo_dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "baseline", "--quiet"], cd: demo_dir)
      IO.puts("Git repo initialized with baseline commit")

      {status, 0} = System.cmd("git", ["log", "--oneline", "-1"], cd: demo_dir)
      IO.puts("Initial commit: #{String.trim(status)}")
    else
      IO.puts("WARNING: git not found, checkpointing may not work")
    end

    demo_dir
  end

  defp run_checkpointing_test(demo_dir) do
    IO.puts("\n--- STARTING CLIENT ---")

    options = %Options{
      cwd: demo_dir,
      enable_file_checkpointing: true,
      permission_mode: :accept_edits,
      allowed_tools: ["Read", "Write", "Edit"]
    }

    IO.puts("enable_file_checkpointing: #{options.enable_file_checkpointing}")

    {:ok, client} = Client.start_link(options, transport: ClaudeAgentSDK.Transport.Port)
    IO.puts("Client started successfully")

    file_path = Path.join(demo_dir, "demo.txt")
    collected_uuids = []

    # Step 1: Modify the file
    IO.puts("\n--- STEP 1: CREATE/MODIFY FILE ---")
    uuids_step1 = run_step(client, "Overwrite demo.txt with: step_one", file_path, "Step 1")
    collected_uuids = collected_uuids ++ uuids_step1

    # Step 2: Modify again
    IO.puts("\n--- STEP 2: MODIFY FILE AGAIN ---")
    uuids_step2 = run_step(client, "Overwrite demo.txt with: step_two", file_path, "Step 2")
    collected_uuids = collected_uuids ++ uuids_step2

    IO.puts("\n--- ATTEMPTING REWIND ---")
    IO.puts("Collected #{length(collected_uuids)} UUIDs from user messages")

    # Use the properly parsed uuid from message.data
    case Enum.find(collected_uuids, &(&1 != nil)) do
      nil ->
        IO.puts("ERROR: No UUIDs found in user messages!")

      uuid ->
        IO.puts("Trying rewind with UUID: #{uuid}")
        result = Client.rewind_files(client, uuid)
        IO.inspect(result, label: "Result")

        case result do
          :ok ->
            IO.puts("SUCCESS! File checkpointing worked!")

            case File.read(file_path) do
              {:ok, contents} -> IO.puts("File contents: #{inspect(String.trim(contents))}")
              _ -> :ok
            end

          {:error, msg} when is_binary(msg) ->
            if String.contains?(msg, "No file checkpoint found") do
              IO.puts("")
              IO.puts("=" |> String.duplicate(60))
              IO.puts("DIAGNOSIS: CLI NOT CREATING CHECKPOINTS")
              IO.puts("=" |> String.duplicate(60))
              IO.puts("")
              IO.puts("The CLI received the correct UUID but has no checkpoint for it.")
              IO.puts("This is a CLI-side issue, not an SDK encoding problem.")
              IO.puts("")
              IO.puts("The Python SDK v0.1.15 also has this issue:")
              IO.puts("  - Documentation says to use msg.uuid")
              IO.puts("  - But UserMessage class has NO uuid field")
              IO.puts("  - The feature appears incomplete in Python SDK too")
              IO.puts("")
            end

          _ ->
            :ok
        end
    end

    # Check git state
    IO.puts("\n--- GIT CHECKPOINT INVESTIGATION ---")
    check_git_checkpoints(demo_dir)

    Client.stop(client)
    IO.puts("\n--- DEBUG SESSION COMPLETE ---")
  end

  defp run_step(client, prompt, file_path, label) do
    IO.puts("Prompt: #{prompt}")

    task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Enum.reduce_while([], fn message, uuids ->
          case message do
            %{type: :user, data: %{uuid: uuid}} when is_binary(uuid) ->
              IO.puts("  [#{label}] User message UUID: #{uuid}")
              {:cont, [uuid | uuids]}

            %{type: :user} = msg ->
              # Fallback: check raw if data.uuid not present
              uuid = msg.raw["uuid"]

              if uuid do
                IO.puts("  [#{label}] User message UUID (from raw): #{uuid}")
                {:cont, [uuid | uuids]}
              else
                {:cont, uuids}
              end

            %{type: :assistant} = msg ->
              text = msg |> ContentExtractor.extract_text() |> String.trim()

              if text != "" and not String.starts_with?(text, "[Tool:") do
                IO.puts("  [#{label}] Assistant: #{String.slice(text, 0, 80)}")
              end

              {:cont, uuids}

            %{type: :result} ->
              {:halt, uuids}

            _ ->
              {:cont, uuids}
          end
        end)
      end)

    :ok = Client.send_message(client, prompt)
    uuids = Task.await(task, 300_000)

    case File.read(file_path) do
      {:ok, contents} -> IO.puts("  File after #{label}: #{inspect(String.trim(contents))}")
      _ -> :ok
    end

    Enum.reverse(uuids)
  end

  defp check_git_checkpoints(demo_dir) do
    if System.find_executable("git") do
      {stash, _} = System.cmd("git", ["stash", "list"], cd: demo_dir)
      IO.puts("Git stash: #{if stash == "", do: "(empty)", else: stash}")

      {log, _} = System.cmd("git", ["log", "--oneline", "-3"], cd: demo_dir)
      IO.puts("Git log:\n#{log}")

      {refs, _} = System.cmd("git", ["for-each-ref", "--format=%(refname)"], cd: demo_dir)

      checkpoint_refs =
        refs |> String.split("\n") |> Enum.filter(&String.contains?(&1, "checkpoint"))

      IO.puts(
        "Checkpoint refs: #{if checkpoint_refs == [], do: "none", else: inspect(checkpoint_refs)}"
      )
    end
  end
end

FileCheckpointingDebug.run()
