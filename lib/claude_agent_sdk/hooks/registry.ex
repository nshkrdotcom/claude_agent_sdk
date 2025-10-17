defmodule ClaudeAgentSDK.Hooks.Registry do
  @moduledoc """
  Hook callback registration and ID management.

  Maintains bidirectional mapping between callback functions and unique IDs
  for use with the Claude Code CLI hooks system.

  ## Purpose

  - Assigns unique IDs to callback functions for CLI initialization
  - Enables lookup of callbacks by ID when CLI triggers hooks
  - Provides idempotent registration (re-registering same callback returns same ID)

  ## Usage

  This module is primarily used internally by `ClaudeAgentSDK.Client`, but can
  be used directly for testing hooks or building custom integrations.

      registry = Registry.new()
      callback = fn _input, _id, _ctx -> Output.allow() end

      registry = Registry.register(registry, callback)
      id = Registry.get_id(registry, callback)  # => "hook_0"

      {:ok, ^callback} = Registry.get_callback(registry, id)
  """

  alias ClaudeAgentSDK.Hooks

  @typedoc """
  Registry state containing callback mappings.

  Fields:
  - `callbacks` - Map from ID string to callback function
  - `reverse_map` - Map from callback function to ID string (for quick lookup)
  - `counter` - Next ID number to assign
  """
  @type t :: %__MODULE__{
          callbacks: %{String.t() => Hooks.hook_callback()},
          reverse_map: %{Hooks.hook_callback() => String.t()},
          counter: non_neg_integer()
        }

  defstruct callbacks: %{},
            reverse_map: %{},
            counter: 0

  @doc """
  Creates a new empty registry.

  ## Examples

      iex> registry = Registry.new()
      iex> Registry.count(registry)
      0
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Registers a callback and returns updated registry.

  If the callback is already registered, returns the existing registry
  without modification (idempotent operation).

  ## Parameters

  - `registry` - Current registry state
  - `callback` - Callback function to register (must be 3-arity function)

  ## Returns

  Updated registry with callback registered.

  ## Examples

      registry = Registry.new()
      callback = fn _input, _tool_use_id, _context -> %{} end

      registry = Registry.register(registry, callback)
      Registry.get_id(registry, callback)
      # => "hook_0"

      # Registering again is idempotent
      registry = Registry.register(registry, callback)
      Registry.count(registry)
      # => 1
  """
  @spec register(t(), Hooks.hook_callback()) :: t()
  def register(%__MODULE__{} = registry, callback) when is_function(callback, 3) do
    case Map.get(registry.reverse_map, callback) do
      nil ->
        # New callback - assign ID and add to both maps
        id = "hook_#{registry.counter}"

        %{
          registry
          | callbacks: Map.put(registry.callbacks, id, callback),
            reverse_map: Map.put(registry.reverse_map, callback, id),
            counter: registry.counter + 1
        }

      _existing_id ->
        # Already registered - return unchanged
        registry
    end
  end

  @doc """
  Gets callback function by ID.

  ## Parameters

  - `registry` - Registry to query
  - `id` - Callback ID string (e.g., "hook_0")

  ## Returns

  - `{:ok, callback}` if ID found
  - `:error` if ID not found

  ## Examples

      registry = Registry.new()
      callback = fn _, _, _ -> %{} end
      registry = Registry.register(registry, callback)

      {:ok, retrieved} = Registry.get_callback(registry, "hook_0")
      retrieved == callback
      # => true

      Registry.get_callback(registry, "hook_999")
      # => :error
  """
  @spec get_callback(t(), String.t()) :: {:ok, Hooks.hook_callback()} | :error
  def get_callback(%__MODULE__{} = registry, id) when is_binary(id) do
    case Map.get(registry.callbacks, id) do
      nil -> :error
      callback -> {:ok, callback}
    end
  end

  @doc """
  Gets ID for a callback function.

  ## Parameters

  - `registry` - Registry to query
  - `callback` - Callback function to look up

  ## Returns

  - ID string if callback registered
  - `nil` if callback not found

  ## Examples

      registry = Registry.new()
      callback = fn _, _, _ -> %{} end
      registry = Registry.register(registry, callback)

      Registry.get_id(registry, callback)
      # => "hook_0"

      other_callback = fn _, _, _ -> %{other: :callback} end
      Registry.get_id(registry, other_callback)
      # => nil
  """
  @spec get_id(t(), Hooks.hook_callback()) :: String.t() | nil
  def get_id(%__MODULE__{} = registry, callback) when is_function(callback, 3) do
    Map.get(registry.reverse_map, callback)
  end

  @doc """
  Returns all registered callbacks.

  ## Parameters

  - `registry` - Registry to query

  ## Returns

  Map from ID string to callback function.

  ## Examples

      registry = Registry.new()
      registry = Registry.register(registry, fn _, _, _ -> %{} end)

      Registry.all_callbacks(registry)
      # => %{"hook_0" => #Function<...>}
  """
  @spec all_callbacks(t()) :: %{String.t() => Hooks.hook_callback()}
  def all_callbacks(%__MODULE__{} = registry) do
    registry.callbacks
  end

  @doc """
  Returns count of registered callbacks.

  ## Parameters

  - `registry` - Registry to query

  ## Returns

  Non-negative integer count.

  ## Examples

      registry = Registry.new()
      Registry.count(registry)
      # => 0

      registry = Registry.register(registry, fn _, _, _ -> %{} end)
      Registry.count(registry)
      # => 1
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{} = registry) do
    map_size(registry.callbacks)
  end
end
