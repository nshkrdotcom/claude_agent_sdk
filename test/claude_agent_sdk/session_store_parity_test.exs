defmodule ClaudeAgentSDK.SessionStoreParityTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.SessionStore

  alias ClaudeAgentSDK.SessionStore.{
    Adapter,
    Conformance,
    InMemory,
    MirrorBatcher,
    Resume,
    Summary
  }

  @session_id "11111111-1111-4111-8111-111111111111"
  @other_session_id "22222222-2222-4222-8222-222222222222"
  @project_dir "/tmp/claude-agent-sdk-parity-project"

  test "session store option enables CLI transcript mirror flag" do
    store = InMemory.new!()
    assert "--session-mirror" in Options.to_args(%Options{session_store: store})
    refute "--session-mirror" in Options.to_args(%Options{})
  end

  test "in-memory adapter satisfies the shared conformance contracts" do
    assert :ok = Conformance.run(fn -> InMemory.new!() end)
  end

  test "project key and file path helpers match local transcript layout" do
    project_key = SessionStore.project_key_for_directory(@project_dir)
    projects_dir = Path.join(System.tmp_dir!(), "projects-#{System.unique_integer([:positive])}")
    file_path = Path.join([projects_dir, project_key, "#{@session_id}.jsonl"])
    sub_path = Path.join([projects_dir, project_key, @session_id, "subagents", "agent-a.jsonl"])

    assert project_key == Summary.project_key_for_directory(@project_dir)

    assert %{project_key: ^project_key, session_id: @session_id} =
             SessionStore.file_path_to_session_key(file_path, projects_dir)

    assert %{
             project_key: ^project_key,
             session_id: @session_id,
             subpath: "subagents/agent-a"
           } = SessionStore.file_path_to_session_key(sub_path, projects_dir)

    assert is_nil(
             SessionStore.file_path_to_session_key(
               "/elsewhere/#{@session_id}.jsonl",
               projects_dir
             )
           )
  end

  test "store-backed helpers list, mutate, read subagents, and fork sessions" do
    store = InMemory.new!()
    project_key = SessionStore.project_key_for_directory(@project_dir)
    key = %{project_key: project_key, session_id: @session_id}

    assert :ok =
             Adapter.append(store, key, [
               user_entry(@session_id, "u1", "Review this module"),
               assistant_entry(@session_id, "a1", "Looks good")
             ])

    [info] = SessionStore.list_sessions_from_store(store, directory: @project_dir)
    assert info.session_id == @session_id
    assert info.summary == "Review this module"
    assert info.created_at == 1_704_067_200_000

    assert :ok =
             SessionStore.rename_session_via_store(@session_id, "Renamed", store,
               directory: @project_dir
             )

    assert :ok =
             SessionStore.tag_session_via_store(@session_id, " parity ", store,
               directory: @project_dir
             )

    info = SessionStore.get_session_info_from_store(@session_id, store, directory: @project_dir)
    assert info.custom_title == "Renamed"
    assert info.tag == "parity"

    assert [%{type: "user"}, %{type: "assistant"}] =
             SessionStore.get_session_messages_from_store(@session_id, store,
               directory: @project_dir
             )

    subkey = %{
      project_key: project_key,
      session_id: @session_id,
      subpath: "subagents/agent-worker"
    }

    assert :ok = Adapter.append(store, subkey, [user_entry(@session_id, "su1", "Sub task")])

    assert ["worker"] =
             SessionStore.list_subagents_from_store(@session_id, store, directory: @project_dir)

    assert [%{uuid: "su1"}] =
             SessionStore.get_subagent_messages_from_store(@session_id, "worker", store,
               directory: @project_dir
             )

    assert %{source_session_id: @session_id, session_id: new_session_id, file_path: nil} =
             SessionStore.fork_session_via_store(@session_id, store,
               directory: @project_dir,
               new_session_id: @other_session_id,
               title: "Fork"
             )

    assert new_session_id == @other_session_id

    assert [_ | _] =
             SessionStore.get_session_messages_from_store(@other_session_id, store,
               directory: @project_dir
             )

    assert :ok =
             SessionStore.delete_session_via_store(@session_id, store, directory: @project_dir)

    assert [] =
             SessionStore.get_session_messages_from_store(@session_id, store,
               directory: @project_dir
             )

    assert [] =
             SessionStore.list_subagents_from_store(@session_id, store, directory: @project_dir)
  end

  test "mirror batcher stores transcript frames and surfaces append failures as mirror_error" do
    store = InMemory.new!()

    projects_dir =
      Path.join(System.tmp_dir!(), "mirror-projects-#{System.unique_integer([:positive])}")

    project_key = SessionStore.project_key_for_directory(@project_dir)
    file_path = Path.join([projects_dir, project_key, "#{@session_id}.jsonl"])

    {:ok, batcher} = MirrorBatcher.start_link(store, projects_dir)

    assert [] =
             MirrorBatcher.enqueue(batcher, file_path, [user_entry(@session_id, "u1", "Hello")])

    assert [] = MirrorBatcher.flush(batcher)

    assert [%{"uuid" => "u1"}] =
             InMemory.get_entries(store, %{project_key: project_key, session_id: @session_id})

    {:ok, failing} =
      MirrorBatcher.start_link(__MODULE__.FailingStore, projects_dir, send_timeout_ms: 100)

    [error] =
      MirrorBatcher.enqueue(
        failing,
        file_path,
        Enum.map(1..501, &user_entry(@session_id, "u#{&1}", "x"))
      )

    assert error.type == :system
    assert error.subtype == :mirror_error
    assert error.data.error =~ "boom"
  end

  test "resume materialization writes main transcript and subagent files" do
    store = InMemory.new!()
    project_key = SessionStore.project_key_for_directory(@project_dir)

    assert :ok =
             Adapter.append(store, %{project_key: project_key, session_id: @session_id}, [
               user_entry(@session_id, "u1", "Resume me")
             ])

    assert :ok =
             Adapter.append(
               store,
               %{
                 project_key: project_key,
                 session_id: @session_id,
                 subpath: "subagents/agent-worker"
               },
               [
                 %{"type" => "agent_metadata", "agentType" => "worker"},
                 user_entry(@session_id, "su1", "Sub resume")
               ]
             )

    options = %Options{session_store: store, resume: @session_id, cwd: @project_dir}
    assert {:ok, %Resume{} = materialized} = Resume.materialize(options)

    try do
      assert File.exists?(
               Path.join([
                 materialized.config_dir,
                 "projects",
                 project_key,
                 "#{@session_id}.jsonl"
               ])
             )

      assert File.exists?(
               Path.join([
                 materialized.config_dir,
                 "projects",
                 project_key,
                 @session_id,
                 "subagents",
                 "agent-worker.jsonl"
               ])
             )

      assert File.exists?(
               Path.join([
                 materialized.config_dir,
                 "projects",
                 project_key,
                 @session_id,
                 "subagents",
                 "agent-worker.meta.json"
               ])
             )
    after
      Resume.cleanup(materialized)
    end
  end

  test "imports local session and subagent transcripts into a store" do
    store = InMemory.new!()

    projects_dir =
      Path.join(System.tmp_dir!(), "import-projects-#{System.unique_integer([:positive])}")

    project_key = SessionStore.project_key_for_directory(@project_dir)
    project_dir = Path.join(projects_dir, project_key)
    File.mkdir_p!(project_dir)

    File.write!(
      Path.join(project_dir, "#{@session_id}.jsonl"),
      Jason.encode!(user_entry(@session_id, "u1", "Import me")) <> "\n"
    )

    sub_dir = Path.join([project_dir, @session_id, "subagents"])
    File.mkdir_p!(sub_dir)

    File.write!(
      Path.join(sub_dir, "agent-worker.jsonl"),
      Jason.encode!(user_entry(@session_id, "su1", "Import sub")) <> "\n"
    )

    File.write!(
      Path.join(sub_dir, "agent-worker.meta.json"),
      Jason.encode!(%{"agentType" => "worker"})
    )

    assert :ok =
             SessionStore.import_session_to_store(@session_id, store,
               projects_dir: projects_dir,
               directory: @project_dir
             )

    assert [%{"uuid" => "u1"}] =
             InMemory.get_entries(store, %{project_key: project_key, session_id: @session_id})

    assert [%{"uuid" => "su1"}, %{"type" => "agent_metadata"}] =
             InMemory.get_entries(store, %{
               project_key: project_key,
               session_id: @session_id,
               subpath: "subagents/agent-worker"
             })
  end

  defmodule FailingStore do
    def append(_key, _entries), do: {:error, :boom}
    def load(_key), do: nil
  end

  defp user_entry(session_id, uuid, text) do
    %{
      "type" => "user",
      "uuid" => uuid,
      "sessionId" => session_id,
      "timestamp" => "2024-01-01T00:00:00.000Z",
      "cwd" => @project_dir,
      "message" => %{"role" => "user", "content" => text}
    }
  end

  defp assistant_entry(session_id, uuid, text) do
    %{
      "type" => "assistant",
      "uuid" => uuid,
      "sessionId" => session_id,
      "timestamp" => "2024-01-01T00:00:01.000Z",
      "message" => %{"role" => "assistant", "content" => [%{"type" => "text", "text" => text}]}
    }
  end
end
