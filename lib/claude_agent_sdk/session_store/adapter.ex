defmodule ClaudeAgentSDK.SessionStore.Adapter do
  @moduledoc """
  Duck-typed SessionStore adapter contract and dispatcher.

  Adapters are ordinary structs or modules. Struct adapters implement
  `append(store, key, entries)` and `load(store, key)`. Module-only adapters may
  implement `append(key, entries)` and `load(key)`. Optional methods are probed
  before use.
  """

  alias ClaudeAgentSDK.SessionStore.Key

  @type entry :: %{optional(String.t() | atom()) => term()}
  @type list_entry :: %{session_id: String.t(), mtime: integer()}
  @type summary_entry :: %{session_id: String.t(), mtime: integer(), data: map()}

  @callback append(term(), Key.t(), [entry()]) :: :ok | {:error, term()}
  @callback load(term(), Key.t()) :: {:ok, [entry()] | nil} | [entry()] | nil | {:error, term()}
  @callback list_sessions(term(), String.t()) ::
              {:ok, [list_entry()]} | [list_entry()] | {:error, term()}
  @callback list_session_summaries(term(), String.t()) ::
              {:ok, [summary_entry()]} | [summary_entry()] | {:error, term()}
  @callback delete(term(), Key.t()) :: :ok | {:error, term()}
  @callback list_subkeys(term(), Key.t()) :: {:ok, [String.t()]} | [String.t()] | {:error, term()}

  @optional_callbacks list_sessions: 2,
                      list_session_summaries: 2,
                      delete: 2,
                      list_subkeys: 2

  @doc false
  @spec append(term(), Key.input(), [entry()]) :: :ok | {:error, term()}
  def append(store, key, entries) when is_list(entries) do
    store
    |> call_required(:append, [Key.new!(key), entries])
    |> normalize_ok()
  end

  @doc false
  @spec load(term(), Key.input()) :: {:ok, [entry()] | nil} | {:error, term()}
  def load(store, key) do
    store
    |> call_required(:load, [Key.new!(key)])
    |> normalize_value()
  end

  @doc false
  @spec list_sessions(term(), String.t()) :: {:ok, [list_entry()]} | {:error, term()}
  def list_sessions(store, project_key) when is_binary(project_key) do
    call_optional(store, :list_sessions, [project_key], :not_implemented)
  end

  @doc false
  @spec list_session_summaries(term(), String.t()) :: {:ok, [summary_entry()]} | {:error, term()}
  def list_session_summaries(store, project_key) when is_binary(project_key) do
    call_optional(store, :list_session_summaries, [project_key], :not_implemented)
  end

  @doc false
  @spec delete(term(), Key.input()) :: :ok | {:error, term()}
  def delete(store, key) do
    if supports?(store, :delete) do
      store
      |> call_optional(:delete, [Key.new!(key)], :not_implemented)
      |> normalize_ok()
    else
      :ok
    end
  end

  @doc false
  @spec list_subkeys(term(), Key.input()) :: {:ok, [String.t()]} | {:error, term()}
  def list_subkeys(store, key) do
    call_optional(store, :list_subkeys, [Key.new!(key)], :not_implemented)
  end

  @doc false
  @spec supports?(term(), atom()) :: boolean()
  def supports?(store, function) when is_atom(function) do
    cond do
      is_atom(store) ->
        function_exported?(store, function, module_arity(function))

      is_map(store) and is_atom(Map.get(store, :__struct__)) ->
        function_exported?(store.__struct__, function, struct_arity(function))

      true ->
        false
    end
  end

  defp call_required(store, function, args) do
    case dispatch(store, function, args) do
      {:ok, result} ->
        result

      :error ->
        raise ArgumentError,
              "SessionStore adapter #{inspect(store)} does not implement #{function}/#{length(args)}"
    end
  end

  defp call_optional(store, function, args, fallback) do
    case dispatch(store, function, args) do
      {:ok, result} -> normalize_value(result)
      :error -> {:error, fallback}
    end
  end

  defp dispatch(store, function, args) when is_atom(store) do
    if function_exported?(store, function, length(args)) do
      {:ok, apply(store, function, args)}
    else
      :error
    end
  end

  defp dispatch(%module{} = store, function, args) do
    if function_exported?(module, function, length(args) + 1) do
      {:ok, apply(module, function, [store | args])}
    else
      :error
    end
  end

  defp dispatch(_store, _function, _args), do: :error

  defp normalize_ok(:ok), do: :ok
  defp normalize_ok({:ok, _value}), do: :ok
  defp normalize_ok({:error, _reason} = error), do: error
  defp normalize_ok(other), do: {:error, {:unexpected_session_store_result, other}}

  defp normalize_value({:ok, value}), do: {:ok, value}
  defp normalize_value({:error, _reason} = error), do: error
  defp normalize_value(value), do: {:ok, value}

  defp module_arity(:append), do: 2
  defp module_arity(:load), do: 1
  defp module_arity(:list_sessions), do: 1
  defp module_arity(:list_session_summaries), do: 1
  defp module_arity(:delete), do: 1
  defp module_arity(:list_subkeys), do: 1

  defp struct_arity(:append), do: 3
  defp struct_arity(:load), do: 2
  defp struct_arity(:list_sessions), do: 2
  defp struct_arity(:list_session_summaries), do: 2
  defp struct_arity(:delete), do: 2
  defp struct_arity(:list_subkeys), do: 2
end
