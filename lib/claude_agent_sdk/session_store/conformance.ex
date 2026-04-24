defmodule ClaudeAgentSDK.SessionStore.Conformance do
  @moduledoc """
  Shared conformance checks for SessionStore adapters.
  """

  alias ClaudeAgentSDK.SessionStore.Adapter

  @key %{project_key: "proj", session_id: "sess"}

  @spec run((-> term())) :: :ok
  def run(make_store) when is_function(make_store, 0) do
    append_load_order(make_store)
    unknown_key(make_store)
    multiple_append_order(make_store)
    append_empty_noop(make_store)
    subpaths_independent(make_store)
    project_isolation(make_store)
    optional_list_sessions(make_store)
    optional_summaries(make_store)
    optional_delete(make_store)
    optional_subkeys(make_store)
    :ok
  end

  defp append_load_order(make_store) do
    store = make_store.()

    :ok =
      Adapter.append(store, @key, [
        entry(%{"uuid" => "b", "n" => 1}),
        entry(%{"uuid" => "a", "n" => 2})
      ])

    assert_equal(
      [entry(%{"uuid" => "b", "n" => 1}), entry(%{"uuid" => "a", "n" => 2})],
      load!(store, @key)
    )
  end

  defp unknown_key(make_store) do
    store = make_store.()
    assert_equal(nil, load!(store, %{project_key: "proj", session_id: "nope"}))
  end

  defp multiple_append_order(make_store) do
    store = make_store.()
    :ok = Adapter.append(store, @key, [entry(%{"uuid" => "z", "n" => 1})])

    :ok =
      Adapter.append(store, @key, [
        entry(%{"uuid" => "a", "n" => 2}),
        entry(%{"uuid" => "m", "n" => 3})
      ])

    assert_equal(
      [
        entry(%{"uuid" => "z", "n" => 1}),
        entry(%{"uuid" => "a", "n" => 2}),
        entry(%{"uuid" => "m", "n" => 3})
      ],
      load!(store, @key)
    )
  end

  defp append_empty_noop(make_store) do
    store = make_store.()
    :ok = Adapter.append(store, @key, [entry(%{"uuid" => "a"})])
    :ok = Adapter.append(store, @key, [])
    assert_equal([entry(%{"uuid" => "a"})], load!(store, @key))
  end

  defp subpaths_independent(make_store) do
    store = make_store.()
    sub = Map.put(@key, :subpath, "subagents/agent-1")
    :ok = Adapter.append(store, @key, [entry(%{"uuid" => "m"})])
    :ok = Adapter.append(store, sub, [entry(%{"uuid" => "s"})])
    assert_equal([entry(%{"uuid" => "m"})], load!(store, @key))
    assert_equal([entry(%{"uuid" => "s"})], load!(store, sub))
  end

  defp project_isolation(make_store) do
    store = make_store.()
    :ok = Adapter.append(store, %{project_key: "A", session_id: "s1"}, [entry(%{"from" => "A"})])
    :ok = Adapter.append(store, %{project_key: "B", session_id: "s1"}, [entry(%{"from" => "B"})])
    assert_equal([entry(%{"from" => "A"})], load!(store, %{project_key: "A", session_id: "s1"}))
    assert_equal([entry(%{"from" => "B"})], load!(store, %{project_key: "B", session_id: "s1"}))
  end

  defp optional_list_sessions(make_store) do
    store = make_store.()

    if Adapter.supports?(store, :list_sessions) do
      :ok = Adapter.append(store, %{project_key: "proj", session_id: "a"}, [entry(%{"n" => 1})])
      :ok = Adapter.append(store, %{project_key: "proj", session_id: "b"}, [entry(%{"n" => 1})])
      {:ok, sessions} = Adapter.list_sessions(store, "proj")

      assert_equal(
        ["a", "b"],
        sessions
        |> Enum.map(&(Map.get(&1, :session_id) || Map.get(&1, "session_id")))
        |> Enum.sort()
      )
    end
  end

  defp optional_summaries(make_store) do
    store = make_store.()

    if Adapter.supports?(store, :list_session_summaries) do
      :ok =
        Adapter.append(store, %{project_key: "proj", session_id: "summ"}, [
          entry(%{"timestamp" => "2024-01-01T00:00:00Z", "customTitle" => "title"})
        ])

      {:ok, summaries} = Adapter.list_session_summaries(store, "proj")

      assert_true(
        Enum.any?(summaries, &((Map.get(&1, :session_id) || Map.get(&1, "session_id")) == "summ"))
      )
    end
  end

  defp optional_delete(make_store) do
    store = make_store.()

    if Adapter.supports?(store, :delete) do
      sub = Map.put(@key, :subpath, "subagents/agent-1")
      :ok = Adapter.append(store, @key, [entry(%{"n" => 1})])
      :ok = Adapter.append(store, sub, [entry(%{"n" => 1})])
      :ok = Adapter.delete(store, @key)
      assert_equal(nil, load!(store, @key))
      assert_equal(nil, load!(store, sub))
    end
  end

  defp optional_subkeys(make_store) do
    store = make_store.()

    if Adapter.supports?(store, :list_subkeys) do
      :ok =
        Adapter.append(store, Map.put(@key, :subpath, "subagents/agent-1"), [entry(%{"n" => 1})])

      {:ok, subkeys} = Adapter.list_subkeys(store, @key)
      assert_equal(["subagents/agent-1"], subkeys)
    end
  end

  defp load!(store, key) do
    {:ok, entries} = Adapter.load(store, key)
    entries
  end

  defp entry(extra), do: Map.put(extra, "type", "x")

  defp assert_equal(left, right) do
    unless left == right,
      do:
        raise("SessionStore conformance assertion failed: #{inspect(left)} != #{inspect(right)}")
  end

  defp assert_true(value) do
    unless value, do: raise("SessionStore conformance assertion failed")
  end
end
