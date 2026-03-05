defmodule ClaudeAgentSDK.Session.HistoryTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Session.History
  alias ClaudeAgentSDK.Session.SessionInfo

  @session_uuid "550e8400-e29b-41d4-a716-446655440000"

  setup do
    # Create a temp directory structure mimicking ~/.claude/projects/<sanitized>/
    tmp_dir = System.tmp_dir!() |> Path.join("claude_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "sanitize_path/1" do
    test "replaces non-alphanumeric chars with hyphens" do
      assert History.sanitize_path("/home/user/project") == "-home-user-project"
    end

    test "truncates long paths and appends hash" do
      long_path = String.duplicate("a", 250)
      sanitized = History.sanitize_path(long_path)
      assert String.length(sanitized) <= 210
      assert sanitized =~ ~r/-[a-z0-9]+$/
    end

    test "short paths are not truncated" do
      assert History.sanitize_path("short") == "short"
    end
  end

  describe "simple_hash/1" do
    test "produces consistent hash" do
      assert History.simple_hash("test") == History.simple_hash("test")
    end

    test "produces different hashes for different inputs" do
      refute History.simple_hash("foo") == History.simple_hash("bar")
    end

    test "returns base36 string" do
      hash = History.simple_hash("/home/user/my-project")
      assert hash =~ ~r/^[0-9a-z]+$/
    end
  end

  describe "list_sessions/1" do
    test "returns empty list when no sessions exist", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-nonexistent-project")
      File.mkdir_p!(project_dir)

      assert History.list_sessions(directory: nil, projects_dir: tmp_dir) == []
    end

    test "reads session metadata from JSONL files", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-home-user-project")
      File.mkdir_p!(project_dir)

      session_file = Path.join(project_dir, "#{@session_uuid}.jsonl")

      content =
        [
          Jason.encode!(%{
            "type" => "user",
            "uuid" => "uuid-1",
            "sessionId" => @session_uuid,
            "message" => %{"role" => "user", "content" => "Hello world"}
          }),
          Jason.encode!(%{
            "type" => "assistant",
            "uuid" => "uuid-2",
            "parentUuid" => "uuid-1",
            "sessionId" => @session_uuid,
            "message" => %{"role" => "assistant", "content" => "Hi there"}
          })
        ]
        |> Enum.join("\n")

      File.write!(session_file, content)

      sessions = History.list_sessions(directory: nil, projects_dir: tmp_dir)
      assert length(sessions) == 1

      session = hd(sessions)
      assert %SessionInfo{} = session
      assert session.session_id == @session_uuid
      assert session.first_prompt == "Hello world"
      assert session.file_size > 0
      assert session.last_modified > 0
    end

    test "skips sidechain sessions", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-home-user-project2")
      File.mkdir_p!(project_dir)

      session_file = Path.join(project_dir, "#{@session_uuid}.jsonl")

      content =
        Jason.encode!(%{
          "type" => "user",
          "uuid" => "uuid-1",
          "sessionId" => @session_uuid,
          "isSidechain" => true,
          "message" => %{"role" => "user", "content" => "sidechain"}
        })

      File.write!(session_file, content)

      sessions = History.list_sessions(directory: nil, projects_dir: tmp_dir)
      assert sessions == []
    end

    test "sorts by last_modified descending", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-sorted-test")
      File.mkdir_p!(project_dir)

      uuid1 = "00000000-0000-0000-0000-000000000001"
      uuid2 = "00000000-0000-0000-0000-000000000002"

      File.write!(
        Path.join(project_dir, "#{uuid1}.jsonl"),
        Jason.encode!(%{
          "type" => "user",
          "uuid" => "u1",
          "sessionId" => uuid1,
          "message" => %{"role" => "user", "content" => "First session"}
        })
      )

      # File.stat mtime has 1-second resolution; ensure different mtime
      Process.sleep(1100)

      File.write!(
        Path.join(project_dir, "#{uuid2}.jsonl"),
        Jason.encode!(%{
          "type" => "user",
          "uuid" => "u2",
          "sessionId" => uuid2,
          "message" => %{"role" => "user", "content" => "Second session"}
        })
      )

      sessions = History.list_sessions(directory: nil, projects_dir: tmp_dir)
      assert length(sessions) == 2
      assert hd(sessions).session_id == uuid2
    end

    test "respects limit option", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-limit-test")
      File.mkdir_p!(project_dir)

      for i <- 1..3 do
        uuid = "00000000-0000-0000-0000-00000000000#{i}"

        File.write!(
          Path.join(project_dir, "#{uuid}.jsonl"),
          Jason.encode!(%{
            "type" => "user",
            "uuid" => "u#{i}",
            "sessionId" => uuid,
            "message" => %{"role" => "user", "content" => "Session #{i}"}
          })
        )
      end

      sessions = History.list_sessions(directory: nil, projects_dir: tmp_dir, limit: 2)
      assert length(sessions) == 2
    end

    test "extracts custom_title from tail", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-title-test")
      File.mkdir_p!(project_dir)

      session_file = Path.join(project_dir, "#{@session_uuid}.jsonl")

      content =
        [
          Jason.encode!(%{
            "type" => "user",
            "uuid" => "u1",
            "sessionId" => @session_uuid,
            "message" => %{"role" => "user", "content" => "Initial prompt"}
          }),
          Jason.encode!(%{
            "type" => "assistant",
            "uuid" => "u2",
            "parentUuid" => "u1",
            "sessionId" => @session_uuid,
            "message" => %{"role" => "assistant", "content" => "Response"},
            "customTitle" => "My Custom Title"
          })
        ]
        |> Enum.join("\n")

      File.write!(session_file, content)

      sessions = History.list_sessions(directory: nil, projects_dir: tmp_dir)
      session = hd(sessions)
      assert session.custom_title == "My Custom Title"
      assert session.summary == "My Custom Title"
    end
  end

  describe "get_session_messages/2" do
    test "returns messages from a session file", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-messages-test")
      File.mkdir_p!(project_dir)

      session_file = Path.join(project_dir, "#{@session_uuid}.jsonl")

      content =
        [
          Jason.encode!(%{
            "type" => "user",
            "uuid" => "uuid-1",
            "sessionId" => @session_uuid,
            "message" => %{"role" => "user", "content" => "Hello"}
          }),
          Jason.encode!(%{
            "type" => "assistant",
            "uuid" => "uuid-2",
            "parentUuid" => "uuid-1",
            "sessionId" => @session_uuid,
            "message" => %{"role" => "assistant", "content" => "Hi there"}
          })
        ]
        |> Enum.join("\n")

      File.write!(session_file, content)

      messages =
        History.get_session_messages(@session_uuid, projects_dir: tmp_dir)

      assert length(messages) == 2
      assert hd(messages).type == "user"
      assert List.last(messages).type == "assistant"
    end

    test "returns empty list for invalid UUID" do
      messages = History.get_session_messages("not-a-uuid")
      assert messages == []
    end

    test "returns empty list for nonexistent session" do
      messages = History.get_session_messages(@session_uuid, projects_dir: "/nonexistent")
      assert messages == []
    end

    test "supports limit and offset", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-pagination-test")
      File.mkdir_p!(project_dir)

      session_file = Path.join(project_dir, "#{@session_uuid}.jsonl")

      entries =
        for i <- 1..6 do
          type = if rem(i, 2) == 1, do: "user", else: "assistant"
          parent = if i > 1, do: "uuid-#{i - 1}", else: nil

          entry = %{
            "type" => type,
            "uuid" => "uuid-#{i}",
            "sessionId" => @session_uuid,
            "message" => %{"role" => type, "content" => "Message #{i}"}
          }

          entry = if parent, do: Map.put(entry, "parentUuid", parent), else: entry
          Jason.encode!(entry)
        end

      File.write!(session_file, Enum.join(entries, "\n"))

      all = History.get_session_messages(@session_uuid, projects_dir: tmp_dir)
      assert length(all) == 6

      page =
        History.get_session_messages(@session_uuid, projects_dir: tmp_dir, limit: 2, offset: 2)

      assert length(page) == 2
    end

    test "filters out isMeta and isSidechain messages", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "-filter-test")
      File.mkdir_p!(project_dir)

      session_file = Path.join(project_dir, "#{@session_uuid}.jsonl")

      content =
        [
          Jason.encode!(%{
            "type" => "user",
            "uuid" => "uuid-1",
            "sessionId" => @session_uuid,
            "message" => %{"role" => "user", "content" => "Visible"}
          }),
          Jason.encode!(%{
            "type" => "user",
            "uuid" => "uuid-2",
            "parentUuid" => "uuid-1",
            "sessionId" => @session_uuid,
            "isMeta" => true,
            "message" => %{"role" => "user", "content" => "Meta message"}
          }),
          Jason.encode!(%{
            "type" => "assistant",
            "uuid" => "uuid-3",
            "parentUuid" => "uuid-1",
            "sessionId" => @session_uuid,
            "message" => %{"role" => "assistant", "content" => "Visible response"}
          })
        ]
        |> Enum.join("\n")

      File.write!(session_file, content)

      messages = History.get_session_messages(@session_uuid, projects_dir: tmp_dir)
      assert length(messages) == 2
      assert Enum.all?(messages, fn m -> m.type in ["user", "assistant"] end)
    end
  end
end
