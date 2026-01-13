#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{CLI, Client, ContentExtractor, Options}
alias ClaudeAgentSDK.Message
alias Examples.Support

defmodule FileCheckpointingLive do
  def run do
    Support.ensure_live!()
    Support.header!("File Checkpointing Example (live)")

    demo_dir =
      Path.join(
        System.tmp_dir!(),
        "claude_agent_sdk_checkpointing_demo_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(demo_dir)
    IO.puts("Demo working directory: #{demo_dir}")
    IO.inspect(CLI.find_executable(), label: "Claude CLI (resolved)")
    IO.inspect(CLI.version(), label: "Claude CLI (version)")

    file_path = Path.join(demo_dir, "demo.txt")
    init_git_repo(demo_dir)

    options = %Options{
      cwd: demo_dir,
      enable_file_checkpointing: true,
      extra_args: %{"replay-user-messages" => nil},
      permission_mode: :accept_edits,
      tools: ["Read", "Write", "Edit"],
      allowed_tools: ["Read", "Write", "Edit"],
      model: "haiku",
      max_turns: 3
    }

    {:ok, client} = Client.start_link(options, transport: ClaudeAgentSDK.Transport.Port)

    checkpoint_id =
      run_step(
        client,
        "Create the file at #{file_path} with the single line: one. Use that exact path. Then say done.",
        file_path,
        "one"
      )

    _ =
      run_step(
        client,
        "Replace the file at #{file_path} so it contains the single line: two. Use that exact path. Then say done.",
        file_path,
        "two"
      )

    attempt_rewind(client, checkpoint_id, file_path)

    if Process.alive?(client), do: Client.stop(client)
  end

  defp run_step(client, prompt, file_path, expected_contents) do
    task =
      Task.async(fn ->
        Client.stream_messages(client)
        |> Enum.reduce_while(%{checkpoint_id: nil}, fn message, acc ->
          case message do
            %{type: :user} ->
              candidates = extract_user_message_id_candidates(message)
              Enum.each(candidates, &IO.puts("Captured user_message_id candidate: #{&1}"))

              if acc.checkpoint_id do
                {:cont, acc}
              else
                {:cont, %{acc | checkpoint_id: List.first(candidates)}}
              end

            %{type: :assistant} ->
              text =
                message
                |> ContentExtractor.extract_text()
                |> normalize_display_newlines()

              if text != "", do: IO.puts("Assistant: #{text}")
              {:cont, acc}

            %{type: :result} ->
              {:halt, acc.checkpoint_id}

            _ ->
              {:cont, acc}
          end
        end)
      end)

    Process.sleep(50)
    :ok = Client.query(client, prompt)
    user_message_id = Task.await(task, 180_000)

    print_file(file_path, "demo.txt after step")
    assert_file_contents!(file_path, expected_contents)

    if is_nil(user_message_id) do
      raise "No user_message_id captured for checkpointing."
    end

    user_message_id
  end

  defp extract_user_message_id_candidates(message) do
    [
      Message.user_uuid(message),
      get_in(message.data || %{}, [:uuid]),
      get_in(message.data || %{}, [:message, "id"]),
      get_in(message.raw, ["message", "id"]),
      message.raw["uuid"],
      get_in(message.raw, ["message", "uuid"]),
      message.raw["user_message_id"]
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp attempt_rewind(_client, nil, file_path) do
    raise """
    No user_message_id found in incoming frames.

    The CLI should emit a per-user-message UUID (when `--replay-user-messages` is enabled),
    which the SDK parses into `%ClaudeAgentSDK.Message{type: :user}.data.uuid`.

    Inspect `%ClaudeAgentSDK.Message{type: :user}.raw` while running this example to find the correct ID field
    to pass to Client.rewind_files/2.
    """
  end

  defp attempt_rewind(client, user_message_id, file_path) when is_binary(user_message_id) do
    IO.puts("Rewinding files to user_message_id: #{user_message_id}")
    result = Client.rewind_files(client, user_message_id)
    IO.inspect(result, label: "rewind_files result")

    if result != :ok do
      raise "rewind_files failed: #{inspect(result)}"
    end

    assert_file_missing!(file_path)
  end

  defp print_file(path, label) do
    case File.read(path) do
      {:ok, contents} ->
        IO.puts("#{label}: #{inspect(contents)}")

      {:error, reason} ->
        IO.puts("#{label}: #{inspect(reason)}")
    end
  end

  defp assert_file_contents!(path, expected) do
    case File.read(path) do
      {:ok, contents} ->
        if String.trim(contents) != expected do
          raise "Unexpected file contents at #{path}: #{inspect(contents)}"
        end

      {:error, reason} ->
        raise "Expected file at #{path}, but read failed: #{inspect(reason)}"
    end
  end

  defp assert_file_missing!(path) do
    case File.read(path) do
      {:ok, contents} ->
        raise "Expected file to be missing after rewind, but found: #{inspect(contents)}"

      {:error, _reason} ->
        IO.puts("demo.txt after rewind: :enoent")
    end
  end

  defp normalize_display_newlines(text) when is_binary(text) do
    if String.contains?(text, "\\n") and not String.contains?(text, "\n") do
      String.replace(text, "\\n", "\n")
    else
      text
    end
  end

  defp init_git_repo(dir) do
    if System.find_executable("git") do
      {_, 0} = System.cmd("git", ["init", "--quiet", "--initial-branch=main"], cd: dir)

      {_, 0} =
        System.cmd("git", ["config", "user.email", "claude-agent-sdk@example.com"], cd: dir)

      {_, 0} = System.cmd("git", ["config", "user.name", "Claude Agent SDK"], cd: dir)
      File.write!(Path.join(dir, ".gitignore"), "\n")
      {_, 0} = System.cmd("git", ["add", "."], cd: dir)
      {_, 0} = System.cmd("git", ["commit", "-m", "init", "--quiet"], cd: dir)
    end
  end
end

FileCheckpointingLive.run()
Support.halt_if_runner!()
