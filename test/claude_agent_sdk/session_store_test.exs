defmodule ClaudeAgentSDK.SessionStoreTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.{Message, SessionStore}

  setup do
    storage_dir =
      Path.join(
        System.tmp_dir!(),
        "session_store_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(storage_dir)

    start_supervised!({SessionStore, storage_dir: storage_dir})

    on_exit(fn ->
      File.rm_rf(storage_dir)
    end)

    %{storage_dir: storage_dir}
  end

  test "cleanup_old_sessions does not crash when old sessions exist", %{storage_dir: storage_dir} do
    session_id = "old-session"
    insert_old_session(session_id, storage_dir)

    assert 1 == SessionStore.cleanup_old_sessions(max_age_days: 0)

    assert is_pid(Process.whereis(SessionStore))
    assert Process.alive?(Process.whereis(SessionStore))
  end

  test "list_saved_sessions/1 preserves the explicit SessionStore helper", %{
    storage_dir: storage_dir
  } do
    session_id = "saved-session"
    assert :ok = SessionStore.save_session(session_id, sample_messages(), tags: ["saved"])

    assert {:ok, sessions} = ClaudeAgentSDK.list_saved_sessions(storage_dir: storage_dir)
    assert Enum.any?(sessions, &(&1.session_id == session_id))
  end

  test "periodic cleanup message does not terminate the session store", %{
    storage_dir: storage_dir
  } do
    insert_old_session("periodic-old-session", storage_dir)

    pid = Process.whereis(SessionStore)
    ref = Process.monitor(pid)

    send(pid, :cleanup_check)

    refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 500
  end

  test "cache ETS table is protected", _context do
    state = :sys.get_state(SessionStore)
    assert :ets.info(state.cache, :protection) == :protected
  end

  test "metadata from disk is normalized after restart", %{storage_dir: storage_dir} do
    session_id = "restart-metadata-session"

    assert :ok = SessionStore.save_session(session_id, sample_messages(), tags: ["restart"])

    assert :ok = stop_supervised(SessionStore)

    start_supervised!({SessionStore, storage_dir: storage_dir})

    assert 1 == SessionStore.cleanup_old_sessions(max_age_days: 0)
  end

  test "cache hydration is deferred to continue callback", %{storage_dir: storage_dir} do
    session_id = "deferred-load-session"

    write_legacy_session_file(storage_dir, session_id,
      created_at: DateTime.add(DateTime.utc_now(), -7_200, :second),
      updated_at: DateTime.add(DateTime.utc_now(), -3_600, :second)
    )

    assert :ok = stop_supervised(SessionStore)

    start_supervised!({SessionStore, storage_dir: storage_dir})

    state = :sys.get_state(SessionStore)

    assert is_boolean(Map.get(state, :cache_loaded?))

    assert_eventually(fn ->
      SessionStore.list_sessions()
      |> Enum.any?(fn session -> session.session_id == session_id end)
    end)
  end

  test "save_session rejects traversal session IDs", %{storage_dir: storage_dir} do
    escaped_name = escaped_sibling_name(storage_dir)
    escaped_session_id = "../#{escaped_name}"
    escaped_path = sibling_session_path(storage_dir, escaped_name)

    refute File.exists?(escaped_path)

    assert {:error, :invalid_session_id} =
             SessionStore.save_session(escaped_session_id, sample_messages())

    refute File.exists?(escaped_path)
  end

  test "load_session rejects traversal session IDs", %{storage_dir: storage_dir} do
    escaped_name = escaped_sibling_name(storage_dir)
    escaped_session_id = "../#{escaped_name}"
    escaped_path = sibling_session_path(storage_dir, escaped_name)

    File.write!(
      escaped_path,
      Jason.encode!(%{
        session_id: escaped_session_id,
        messages: [],
        metadata: %{}
      })
    )

    assert {:error, :invalid_session_id} = SessionStore.load_session(escaped_session_id)
    assert File.exists?(escaped_path)
  end

  test "delete_session rejects traversal session IDs", %{storage_dir: storage_dir} do
    escaped_name = escaped_sibling_name(storage_dir)
    escaped_session_id = "../#{escaped_name}"
    escaped_path = sibling_session_path(storage_dir, escaped_name)
    File.write!(escaped_path, "{}")

    assert {:error, :invalid_session_id} = SessionStore.delete_session(escaped_session_id)
    assert File.exists?(escaped_path)
  end

  test "save_session preserves created_at for existing sessions" do
    session_id = "created-at-session"

    assert :ok = SessionStore.save_session(session_id, sample_messages(), tags: ["first"])
    assert {:ok, first_save} = SessionStore.load_session(session_id)

    Process.sleep(5)

    assert :ok =
             SessionStore.save_session(session_id, sample_messages(),
               tags: ["second"],
               description: "updated"
             )

    assert {:ok, second_save} = SessionStore.load_session(session_id)

    assert second_save.metadata.created_at == first_save.metadata.created_at

    assert DateTime.compare(second_save.metadata.updated_at, first_save.metadata.updated_at) ==
             :gt

    assert second_save.metadata.tags == ["second"]
    assert second_save.metadata.description == "updated"
  end

  defp insert_old_session(session_id, storage_dir) do
    write_legacy_session_file(storage_dir, session_id,
      created_at: DateTime.add(DateTime.utc_now(), -7_200, :second),
      updated_at: DateTime.add(DateTime.utc_now(), -3_600, :second)
    )

    assert :ok = stop_supervised(SessionStore)
    start_supervised!({SessionStore, storage_dir: storage_dir})

    assert_eventually(fn ->
      SessionStore.list_sessions()
      |> Enum.any?(fn session -> session.session_id == session_id end)
    end)
  end

  defp write_legacy_session_file(storage_dir, session_id, opts) do
    created_at = Keyword.fetch!(opts, :created_at)
    updated_at = Keyword.fetch!(opts, :updated_at)

    path = Path.join(storage_dir, "#{session_id}.json")

    json =
      Jason.encode!(%{
        session_id: session_id,
        messages: [
          %{
            type: "system",
            subtype: "init",
            data: %{"model" => "test-model", "session_id" => session_id},
            raw: %{}
          }
        ],
        metadata: %{
          session_id: session_id,
          created_at: DateTime.to_iso8601(created_at),
          updated_at: DateTime.to_iso8601(updated_at),
          message_count: 1,
          total_cost: 0.0,
          tags: ["legacy"],
          description: "legacy",
          model: "test-model"
        }
      })

    File.write!(path, json)
  end

  defp sample_messages do
    [
      %Message{type: :system, subtype: :init, data: %{"model" => "test-model"}, raw: %{}},
      %Message{
        type: :result,
        subtype: :success,
        data: %{"total_cost_usd" => 0.01, "session_id" => "restart-metadata-session"},
        raw: %{}
      }
    ]
  end

  defp sibling_session_path(storage_dir, session_id) do
    storage_dir
    |> Path.dirname()
    |> Path.join("#{session_id}.json")
  end

  defp escaped_sibling_name(storage_dir) do
    Path.basename(storage_dir) <> "_escaped"
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      assert true
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition was not met")
end
