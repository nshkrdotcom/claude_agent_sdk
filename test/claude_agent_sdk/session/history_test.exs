defmodule ClaudeAgentSDK.Session.HistoryTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK
  alias ClaudeAgentSDK.Config.Timeouts
  alias ClaudeAgentSDK.Session.History
  alias ClaudeAgentSDK.Session.SessionInfo
  alias ClaudeAgentSDK.Session.SessionMessage
  alias ClaudeAgentSDK.TestEnvHelpers

  @session_uuid "550e8400-e29b-41d4-a716-446655440000"

  setup do
    root = Path.join(System.tmp_dir!(), "claude_history_#{System.unique_integer([:positive])}")
    config_dir = Path.join(root, ".claude")
    projects_dir = Path.join(config_dir, "projects")
    File.mkdir_p!(projects_dir)

    original_config_dir = System.get_env("CLAUDE_CONFIG_DIR")
    System.put_env("CLAUDE_CONFIG_DIR", config_dir)

    on_exit(fn ->
      restore_env("CLAUDE_CONFIG_DIR", original_config_dir)
      File.rm_rf!(root)
    end)

    {:ok, config_dir: config_dir, projects_dir: projects_dir, root: root}
  end

  describe "sanitize_path/1" do
    test "replaces non-alphanumeric characters with hyphens" do
      assert History.sanitize_path("/Users/foo/my-project") == "-Users-foo-my-project"
      assert History.sanitize_path("plugin:name:server") == "plugin-name-server"
    end

    test "truncates long paths and appends a hash suffix" do
      long_path = String.duplicate("/x", 150)
      sanitized = History.sanitize_path(long_path)

      assert String.length(sanitized) > 200
      assert String.starts_with?(sanitized, "-x-x")
      assert String.contains?(String.slice(sanitized, 200..-1//1), "-")
    end
  end

  describe "simple_hash/1" do
    test "matches the JS-compatible hash used by upstream session storage" do
      assert History.simple_hash("") == "0"
      assert History.simple_hash("hello") == "1n1e4y"
      assert History.simple_hash("hello") != History.simple_hash("world")
    end
  end

  describe "list_sessions/1" do
    test "returns empty list when the config dir has no sessions" do
      assert History.list_sessions() == []
    end

    test "reads sessions for a real project path from CLAUDE_CONFIG_DIR", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "my-project") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      {session_id, _path} =
        make_session_file(project_dir,
          first_prompt: "What is 2+2?",
          git_branch: "main",
          cwd: project_path
        )

      sessions = History.list_sessions(directory: project_path, include_worktrees: false)

      assert [
               %SessionInfo{
                 session_id: ^session_id,
                 first_prompt: "What is 2+2?",
                 summary: "What is 2+2?",
                 git_branch: "main",
                 cwd: ^project_path,
                 project_path: ^project_path,
                 custom_title: nil,
                 file_size: file_size,
                 last_modified: last_modified
               }
             ] = sessions

      assert file_size > 0
      assert last_modified > 0
    end

    test "custom_title wins summary and first_prompt", %{config_dir: config_dir, root: root} do
      project_path = Path.join(root, "custom-title") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      make_session_file(project_dir,
        first_prompt: "original question",
        summary: "auto summary",
        custom_title: "My Custom Title"
      )

      assert [%SessionInfo{} = session] =
               History.list_sessions(directory: project_path, include_worktrees: false)

      assert session.summary == "My Custom Title"
      assert session.custom_title == "My Custom Title"
      assert session.first_prompt == "original question"
    end

    test "summary wins first_prompt when no custom title", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "summary") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      make_session_file(project_dir, first_prompt: "question", summary: "better summary")

      assert [%SessionInfo{} = session] =
               History.list_sessions(directory: project_path, include_worktrees: false)

      assert session.summary == "better summary"
      assert session.custom_title == nil
    end

    test "sorts by last_modified descending and returns millisecond timestamps", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "mtime") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      {old_id, old_path} = make_session_file(project_dir, first_prompt: "old")
      {new_id, new_path} = make_session_file(project_dir, first_prompt: "new")
      {mid_id, mid_path} = make_session_file(project_dir, first_prompt: "mid")

      set_mtime!(old_path, 1_000)
      set_mtime!(new_path, 3_000)
      set_mtime!(mid_path, 2_000)

      sessions = History.list_sessions(directory: project_path, include_worktrees: false)

      assert Enum.map(sessions, & &1.session_id) == [new_id, mid_id, old_id]
      assert Enum.map(sessions, & &1.last_modified) == [3_000_000, 2_000_000, 1_000_000]
    end

    test "respects limit", %{config_dir: config_dir, root: root} do
      project_path = Path.join(root, "limit") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      for prompt <- ~w[prompt0 prompt1 prompt2 prompt3 prompt4] do
        make_session_file(project_dir, first_prompt: prompt)
      end

      assert 2 ==
               History.list_sessions(directory: project_path, limit: 2, include_worktrees: false)
               |> length()
    end

    test "supports offset pagination", %{config_dir: config_dir, root: root} do
      project_path = Path.join(root, "offset") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      {old_id, old_path} = make_session_file(project_dir, first_prompt: "old")
      {mid_id, mid_path} = make_session_file(project_dir, first_prompt: "mid")
      {new_id, new_path} = make_session_file(project_dir, first_prompt: "new")

      set_mtime!(old_path, 1_000)
      set_mtime!(mid_path, 2_000)
      set_mtime!(new_path, 3_000)

      sessions =
        History.list_sessions(
          directory: project_path,
          limit: 1,
          offset: 1,
          include_worktrees: false
        )

      assert Enum.map(sessions, & &1.session_id) == [mid_id]
      assert old_id != mid_id
      assert new_id != mid_id
    end

    test "includes tag and created_at metadata", %{config_dir: config_dir, root: root} do
      project_path = Path.join(root, "metadata") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)
      session_id = make_uuid(778)
      file_path = Path.join(project_dir, "#{session_id}.jsonl")

      lines = [
        Jason.encode!(%{
          "type" => "user",
          "timestamp" => "2026-01-15T12:30:00Z",
          "message" => %{"content" => "hello"}
        }),
        Jason.encode!(%{"type" => "tag", "tag" => "urgent", "sessionId" => session_id})
      ]

      File.write!(file_path, Enum.join(lines, "\n") <> "\n")

      assert [%SessionInfo{tag: "urgent", created_at: created_at}] =
               History.list_sessions(directory: project_path, include_worktrees: false)

      assert created_at == DateTime.to_unix(~U[2026-01-15 12:30:00Z], :millisecond)
    end

    test "filters sidechain and metadata-only sessions", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "filtered") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      make_session_file(project_dir, first_prompt: "normal")
      make_session_file(project_dir, first_prompt: "sidechain", is_sidechain: true)
      make_session_file(project_dir, first_prompt: "meta only", is_meta_only: true)

      assert [%SessionInfo{first_prompt: "normal"}] =
               History.list_sessions(directory: project_path, include_worktrees: false)
    end

    test "lists all sessions across projects and deduplicates by newest session id", %{
      config_dir: config_dir
    } do
      older_dir = make_project_dir(config_dir, "/path/one")
      newer_dir = make_project_dir(config_dir, "/path/two")
      shared_id = make_uuid(42)

      {_session_id, older_path} =
        make_session_file(older_dir, session_id: shared_id, first_prompt: "older")

      {_session_id, newer_path} =
        make_session_file(newer_dir, session_id: shared_id, first_prompt: "newer")

      set_mtime!(older_path, 1_000)
      set_mtime!(newer_path, 2_000)

      assert [
               %SessionInfo{
                 session_id: ^shared_id,
                 first_prompt: "newer",
                 last_modified: 2_000_000
               }
             ] =
               History.list_sessions()
    end

    test "falls back cwd to the project path and prefers gitBranch from tail", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "cwd-fallback") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      session_id = make_uuid(77)
      file_path = Path.join(project_dir, "#{session_id}.jsonl")

      lines = [
        Jason.encode!(%{
          "type" => "user",
          "message" => %{"content" => "hello"},
          "gitBranch" => "old-branch"
        }),
        Jason.encode!(%{"type" => "summary", "gitBranch" => "new-branch"})
      ]

      File.write!(file_path, Enum.join(lines, "\n") <> "\n")

      assert [%SessionInfo{} = session] =
               History.list_sessions(directory: project_path, include_worktrees: false)

      assert session.cwd == project_path
      assert session.project_path == project_path
      assert session.git_branch == "new-branch"
    end

    test "include_worktrees scans git worktree session directories and deduplicates", %{
      config_dir: config_dir,
      root: root
    } do
      repo = Path.join(root, "repo") |> Path.expand()
      worktree = Path.join(root, "repo-worktree") |> Path.expand()
      setup_git_worktree!(repo, worktree)

      main_dir = make_project_dir(config_dir, repo)
      worktree_dir = make_project_dir(config_dir, worktree)
      shared_id = make_uuid(99)

      {_sid, main_path} = make_session_file(main_dir, session_id: shared_id, first_prompt: "main")

      {_sid, worktree_path} =
        make_session_file(worktree_dir, session_id: shared_id, first_prompt: "worktree")

      set_mtime!(main_path, 1_000)
      set_mtime!(worktree_path, 3_000)

      sessions = History.list_sessions(directory: repo, include_worktrees: true)

      assert [%SessionInfo{session_id: ^shared_id, first_prompt: "worktree"}] = sessions
    end

    test "include_worktrees falls back to the main project when git probing times out", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "git-timeout") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      {session_id, _path} = make_session_file(project_dir, first_prompt: "main")

      fake_bin = Path.join(root, "fake-bin")
      fake_git = Path.join(fake_bin, "git")
      File.mkdir_p!(fake_bin)
      File.write!(fake_git, "#!/bin/sh\nsleep 1\n")
      File.chmod!(fake_git, 0o755)

      path = prepend_path(fake_bin)

      TestEnvHelpers.with_system_and_app_env(
        :claude_agent_sdk,
        [{"PATH", path}],
        [{Timeouts, [session_git_worktree_ms: 100]}],
        fn ->
          assert [%SessionInfo{session_id: ^session_id, first_prompt: "main"}] =
                   History.list_sessions(directory: project_path, include_worktrees: true)
        end
      )
    end
  end

  describe "get_session_messages/2" do
    test "returns empty list for invalid or missing session ids" do
      assert History.get_session_messages("not-a-uuid") == []
      assert History.get_session_messages(@session_uuid) == []
    end

    test "builds the canonical conversation chain and returns visible session messages", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "messages") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      u1 = make_uuid(1)
      a1 = make_uuid(2)
      u2 = make_uuid(3)
      a2 = make_uuid(4)

      entries = [
        make_transcript_entry("user", u1, nil, @session_uuid, "hello"),
        make_transcript_entry("assistant", a1, u1, @session_uuid, "hi!"),
        make_transcript_entry("user", u2, a1, @session_uuid, "thanks"),
        make_transcript_entry("assistant", a2, u2, @session_uuid, "welcome")
      ]

      write_transcript!(project_dir, @session_uuid, entries)

      messages = History.get_session_messages(@session_uuid, directory: project_path)

      assert [
               %SessionMessage{
                 type: "user",
                 uuid: ^u1,
                 session_id: @session_uuid,
                 message: %{"role" => "user", "content" => "hello"},
                 parent_tool_use_id: nil
               },
               %SessionMessage{type: "assistant", uuid: ^a1},
               %SessionMessage{type: "user", uuid: ^u2},
               %SessionMessage{type: "assistant", uuid: ^a2}
             ] = messages
    end

    test "filters meta and non-user-assistant entries but walks through them in the chain", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "filtered-chain") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      u1 = make_uuid(10)
      meta = make_uuid(11)
      progress = make_uuid(12)
      a1 = make_uuid(13)

      entries = [
        make_transcript_entry("user", u1, nil, @session_uuid, "hello"),
        make_transcript_entry("user", meta, u1, @session_uuid, "meta", isMeta: true),
        make_transcript_entry("progress", progress, meta, @session_uuid, nil),
        make_transcript_entry("assistant", a1, progress, @session_uuid, "hi")
      ]

      messages =
        project_dir
        |> write_transcript!(@session_uuid, entries)
        |> then(fn _ ->
          History.get_session_messages(@session_uuid, directory: project_path)
        end)

      assert Enum.map(messages, & &1.uuid) == [u1, a1]
      assert Enum.all?(messages, &(&1.type in ["user", "assistant"]))
    end

    test "keeps compact summaries, prefers the main leaf, and supports pagination", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "pagination") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      uuids = Enum.map(1..6, &make_uuid/1)

      entries =
        uuids
        |> Enum.with_index()
        |> Enum.map(fn {uuid, index} ->
          parent = if index == 0, do: nil, else: Enum.at(uuids, index - 1)
          type = if rem(index, 2) == 0, do: "user", else: "assistant"

          extras = if index == 0, do: [isCompactSummary: true], else: []
          make_transcript_entry(type, uuid, parent, @session_uuid, "m#{index}", extras)
        end)

      side_leaf = make_uuid(100)

      entries =
        entries ++
          [
            make_transcript_entry("assistant", side_leaf, hd(uuids), @session_uuid, "side",
              isSidechain: true
            )
          ]

      write_transcript!(project_dir, @session_uuid, entries)

      all_messages = History.get_session_messages(@session_uuid, directory: project_path)

      paged_messages =
        History.get_session_messages(@session_uuid, directory: project_path, limit: 2, offset: 2)

      assert Enum.map(all_messages, & &1.uuid) == uuids
      assert Enum.map(paged_messages, & &1.uuid) == Enum.slice(uuids, 2, 2)

      assert length(
               History.get_session_messages(@session_uuid, directory: project_path, limit: 0)
             ) == 6

      assert History.get_session_messages(@session_uuid, directory: project_path, offset: 100) ==
               []
    end

    test "returns empty when parentUuid links are cyclic", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "cycles") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      u1 = make_uuid(201)
      a1 = make_uuid(202)

      entries = [
        make_transcript_entry("user", u1, a1, @session_uuid, "hi"),
        make_transcript_entry("assistant", a1, u1, @session_uuid, "hello")
      ]

      write_transcript!(project_dir, @session_uuid, entries)

      assert History.get_session_messages(@session_uuid, directory: project_path) == []
    end

    test "searches all projects when no directory is given", %{config_dir: config_dir} do
      project_dir = make_project_dir(config_dir, "/path/two")

      u1 = make_uuid(301)
      a1 = make_uuid(302)

      write_transcript!(project_dir, @session_uuid, [
        make_transcript_entry("user", u1, nil, @session_uuid, "hi"),
        make_transcript_entry("assistant", a1, u1, @session_uuid, "hello")
      ])

      assert [%SessionMessage{uuid: ^u1}, %SessionMessage{uuid: ^a1}] =
               History.get_session_messages(@session_uuid)
    end
  end

  describe "session info and mutations" do
    test "get_session_info returns one session or nil", %{config_dir: config_dir, root: root} do
      project_path = Path.join(root, "info") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      {session_id, _path} = make_session_file(project_dir, first_prompt: "lookup")

      assert %SessionInfo{session_id: ^session_id, summary: "lookup"} =
               History.get_session_info(session_id, directory: project_path)

      assert History.get_session_info("not-a-uuid", directory: project_path) == nil
      assert History.get_session_info(make_uuid(999), directory: project_path) == nil
    end

    test "rename_session and tag_session append compact entries and last values win", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "mutations") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)
      {session_id, file_path} = make_session_file(project_dir, first_prompt: "original")

      assert :ok = History.rename_session(session_id, "  New Title  ", directory: project_path)

      assert :ok =
               History.tag_session(session_id, "  clean\u200btag\ufeff  ",
                 directory: project_path
               )

      lines = file_path |> File.read!() |> String.split("\n", trim: true)

      assert Jason.decode!(Enum.at(lines, -2)) == %{
               "type" => "custom-title",
               "customTitle" => "New Title",
               "sessionId" => session_id
             }

      assert Jason.decode!(List.last(lines)) == %{
               "type" => "tag",
               "tag" => "cleantag",
               "sessionId" => session_id
             }

      assert %SessionInfo{summary: "New Title", custom_title: "New Title", tag: "cleantag"} =
               History.get_session_info(session_id, directory: project_path)
    end

    test "delete_session removes transcript and subagent directory", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "delete") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)
      {session_id, file_path} = make_session_file(project_dir, first_prompt: "delete me")
      subagent_dir = Path.join(project_dir, session_id)
      File.mkdir_p!(subagent_dir)
      File.write!(Path.join(subagent_dir, "agent-x.jsonl"), "{}\n")

      assert :ok = History.delete_session(session_id, directory: project_path)

      refute File.exists?(file_path)
      refute File.exists?(subagent_dir)
    end

    test "fork_session remaps ids and creates a titled session", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "fork") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      u1 = make_uuid(701)
      a1 = make_uuid(702)
      u2 = make_uuid(703)

      write_transcript!(project_dir, @session_uuid, [
        make_transcript_entry("user", u1, nil, @session_uuid, "hello"),
        make_transcript_entry("assistant", a1, u1, @session_uuid, "hi"),
        make_transcript_entry("user", u2, a1, @session_uuid, "again")
      ])

      result =
        History.fork_session(@session_uuid,
          directory: project_path,
          up_to_message_id: a1,
          title: "My Fork"
        )

      assert result.source_session_id == @session_uuid
      assert result.session_id != @session_uuid
      assert File.exists?(result.file_path)

      fork_messages = History.get_session_messages(result.session_id, directory: project_path)
      assert length(fork_messages) == 2
      refute Enum.any?(fork_messages, &(&1.uuid in [u1, a1, u2]))

      assert %SessionInfo{custom_title: "My Fork"} =
               History.get_session_info(result.session_id, directory: project_path)
    end
  end

  describe "subagent helpers" do
    test "lists subagents recursively and reads subagent messages", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "subagents") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)
      make_session_file(project_dir, session_id: @session_uuid, first_prompt: "main")

      subagents_dir = Path.join([project_dir, @session_uuid, "subagents"])
      nested_dir = Path.join([subagents_dir, "workflows", "run-1"])
      File.mkdir_p!(nested_dir)
      File.write!(Path.join(subagents_dir, "other.jsonl"), "{}\n")
      File.write!(Path.join(subagents_dir, "agent-top.jsonl"), "{}\n")

      u1 = make_uuid(801)
      a1 = make_uuid(802)

      write_transcript!(nested_dir, "agent-deep", [
        make_transcript_entry("user", u1, nil, @session_uuid, "task"),
        make_transcript_entry("assistant", a1, u1, @session_uuid, "done")
      ])

      assert History.list_subagents(@session_uuid, directory: project_path) == ["deep", "top"]

      assert [%SessionMessage{uuid: ^u1}, %SessionMessage{uuid: ^a1}] =
               History.get_subagent_messages(@session_uuid, "deep", directory: project_path)
    end
  end

  describe "top-level parity helpers" do
    test "ClaudeAgentSDK.list_sessions/1 and get_session_messages/2 delegate to CLI history", %{
      config_dir: config_dir,
      root: root
    } do
      project_path = Path.join(root, "top-level") |> Path.expand()
      File.mkdir_p!(project_path)
      project_dir = make_project_dir(config_dir, project_path)

      make_session_file(project_dir, session_id: @session_uuid, first_prompt: "hello")

      write_transcript!(project_dir, @session_uuid, [
        make_transcript_entry("user", make_uuid(401), nil, @session_uuid, "hello")
      ])

      assert [%SessionInfo{session_id: @session_uuid}] =
               ClaudeAgentSDK.list_sessions(directory: project_path, include_worktrees: false)

      assert [%SessionMessage{session_id: @session_uuid}] =
               ClaudeAgentSDK.get_session_messages(@session_uuid, directory: project_path)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp make_project_dir(config_dir, project_path) do
    sanitized_dir = History.sanitize_path(project_path)
    project_dir = Path.join([config_dir, "projects", sanitized_dir])
    File.mkdir_p!(project_dir)
    project_dir
  end

  defp make_session_file(project_dir, opts) do
    session_id = Keyword.get(opts, :session_id, make_uuid(System.unique_integer([:positive])))
    file_path = Path.join(project_dir, "#{session_id}.jsonl")

    first_prompt = Keyword.get(opts, :first_prompt, "Hello Claude")
    summary = Keyword.get(opts, :summary)
    custom_title = Keyword.get(opts, :custom_title)
    git_branch = Keyword.get(opts, :git_branch)
    cwd = Keyword.get(opts, :cwd)
    is_sidechain = Keyword.get(opts, :is_sidechain, false)
    is_meta_only = Keyword.get(opts, :is_meta_only, false)

    first_entry =
      %{
        "type" => "user",
        "message" => %{"role" => "user", "content" => first_prompt}
      }
      |> maybe_put("cwd", cwd)
      |> maybe_put("gitBranch", git_branch)
      |> maybe_put_if("isSidechain", is_sidechain)
      |> maybe_put_if("isMeta", is_meta_only)

    tail_entry =
      %{"type" => "summary"}
      |> maybe_put("summary", summary)
      |> maybe_put("customTitle", custom_title)
      |> maybe_put("gitBranch", git_branch)

    content =
      [
        Jason.encode!(first_entry),
        Jason.encode!(%{
          "type" => "assistant",
          "message" => %{"role" => "assistant", "content" => "Hi there!"}
        }),
        Jason.encode!(tail_entry)
      ]
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    File.write!(file_path, content)

    {session_id, file_path}
  end

  defp make_transcript_entry(type, uuid, parent_uuid, session_id, content, extras \\ []) do
    entry = %{
      "type" => type,
      "uuid" => uuid,
      "parentUuid" => parent_uuid,
      "sessionId" => session_id
    }

    entry =
      if is_nil(content) do
        entry
      else
        role = if type in ["user", "assistant"], do: type, else: "user"
        Map.put(entry, "message", %{"role" => role, "content" => content})
      end

    Enum.into(extras, entry, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp write_transcript!(project_dir, session_id, entries) do
    path = Path.join(project_dir, "#{session_id}.jsonl")
    content = Enum.map_join(entries, "\n", &Jason.encode!/1) <> "\n"
    File.write!(path, content)
    path
  end

  defp set_mtime!(path, posix_seconds) do
    datetime =
      posix_seconds
      |> round()
      |> DateTime.from_unix!()
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()

    File.touch!(path, datetime)
  end

  defp setup_git_worktree!(repo, worktree) do
    File.mkdir_p!(repo)
    run_git!(repo, ["init"])
    run_git!(repo, ["config", "user.email", "sdk@example.com"])
    run_git!(repo, ["config", "user.name", "SDK Test"])
    File.write!(Path.join(repo, "README.md"), "history test\n")
    run_git!(repo, ["add", "README.md"])
    run_git!(repo, ["commit", "-m", "initial"])
    run_git!(repo, ["worktree", "add", "-b", "feature", worktree])
  end

  defp run_git!(cwd, args) do
    case System.cmd("git", ["-c", "commit.gpgsign=false" | args],
           cd: cwd,
           env: git_test_env(cwd),
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, status} ->
        flunk("git #{Enum.join(args, " ")} failed with status #{status}: #{output}")
    end
  end

  defp git_test_env(cwd) do
    global_config_path = Path.join(cwd, ".git-test-global-config")
    File.write!(global_config_path, "")

    [
      {"GIT_CONFIG_NOSYSTEM", "1"},
      {"GIT_CONFIG_GLOBAL", global_config_path},
      {"GIT_TERMINAL_PROMPT", "0"}
    ]
  end

  defp prepend_path(path) do
    case System.get_env("PATH") do
      nil -> path
      current -> path <> path_separator() <> current
    end
  end

  defp path_separator do
    case :os.type() do
      {:win32, _} -> ";"
      _ -> ":"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_if(map, _key, false), do: map
  defp maybe_put_if(map, key, true), do: Map.put(map, key, true)

  defp make_uuid(integer) when is_integer(integer) do
    tail =
      integer
      |> Integer.to_string()
      |> String.pad_leading(12, "0")
      |> String.slice(-12, 12)

    "00000000-0000-0000-0000-#{tail}"
  end
end
