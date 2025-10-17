defmodule ClaudeAgentSDK.Hooks.RegistryTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Hooks.Registry

  describe "new/0" do
    test "creates empty registry" do
      registry = Registry.new()

      assert %Registry{} = registry
      assert registry.callbacks == %{}
      assert registry.reverse_map == %{}
      assert registry.counter == 0
    end
  end

  describe "register/2" do
    test "registers a new callback" do
      registry = Registry.new()
      callback = fn _, _, _ -> %{} end

      registry = Registry.register(registry, callback)

      assert map_size(registry.callbacks) == 1
      assert map_size(registry.reverse_map) == 1
      assert registry.counter == 1
    end

    test "assigns unique ID to callback" do
      registry = Registry.new()
      callback = fn _, _, _ -> %{} end

      registry = Registry.register(registry, callback)
      id = Map.keys(registry.callbacks) |> List.first()

      assert id == "hook_0"
    end

    test "increments counter for each new callback" do
      registry = Registry.new()
      callback1 = fn _, _, _ -> %{} end
      callback2 = fn _, _, _ -> %{} end
      callback3 = fn _, _, _ -> %{} end

      registry =
        registry
        |> Registry.register(callback1)
        |> Registry.register(callback2)
        |> Registry.register(callback3)

      assert registry.counter == 3
      assert Map.keys(registry.callbacks) == ["hook_0", "hook_1", "hook_2"]
    end

    test "does not register same callback twice" do
      registry = Registry.new()
      callback = fn _, _, _ -> %{} end

      registry =
        registry
        |> Registry.register(callback)
        |> Registry.register(callback)

      # Should still only have one entry
      assert map_size(registry.callbacks) == 1
      assert registry.counter == 1
    end

    test "different callbacks get different IDs" do
      registry = Registry.new()
      callback1 = fn _, _, _ -> %{} end
      callback2 = fn _, _, _ -> %{test: :value} end

      registry =
        registry
        |> Registry.register(callback1)
        |> Registry.register(callback2)

      ids = Map.keys(registry.callbacks)
      assert length(ids) == 2
      assert "hook_0" in ids
      assert "hook_1" in ids
    end
  end

  describe "get_callback/2" do
    test "returns callback for valid ID" do
      registry = Registry.new()
      callback = fn _, _, _ -> %{} end

      registry = Registry.register(registry, callback)
      {:ok, retrieved} = Registry.get_callback(registry, "hook_0")

      assert retrieved == callback
    end

    test "returns error for unknown ID" do
      registry = Registry.new()

      assert Registry.get_callback(registry, "hook_999") == :error
    end

    test "can retrieve multiple callbacks" do
      registry = Registry.new()
      callback1 = fn _, _, _ -> %{a: 1} end
      callback2 = fn _, _, _ -> %{b: 2} end

      registry =
        registry
        |> Registry.register(callback1)
        |> Registry.register(callback2)

      {:ok, retrieved1} = Registry.get_callback(registry, "hook_0")
      {:ok, retrieved2} = Registry.get_callback(registry, "hook_1")

      assert retrieved1 == callback1
      assert retrieved2 == callback2
    end
  end

  describe "get_id/2" do
    test "returns ID for registered callback" do
      registry = Registry.new()
      callback = fn _, _, _ -> %{} end

      registry = Registry.register(registry, callback)
      id = Registry.get_id(registry, callback)

      assert id == "hook_0"
    end

    test "returns nil for unregistered callback" do
      registry = Registry.new()
      callback = fn _, _, _ -> %{} end

      id = Registry.get_id(registry, callback)

      assert id == nil
    end

    test "returns correct ID for specific callback among many" do
      registry = Registry.new()
      callback1 = fn _, _, _ -> %{a: 1} end
      callback2 = fn _, _, _ -> %{b: 2} end
      callback3 = fn _, _, _ -> %{c: 3} end

      registry =
        registry
        |> Registry.register(callback1)
        |> Registry.register(callback2)
        |> Registry.register(callback3)

      assert Registry.get_id(registry, callback1) == "hook_0"
      assert Registry.get_id(registry, callback2) == "hook_1"
      assert Registry.get_id(registry, callback3) == "hook_2"
    end
  end

  describe "bidirectional lookup" do
    test "can lookup ID then callback" do
      registry = Registry.new()
      callback = fn _, _, _ -> %{test: :value} end

      registry = Registry.register(registry, callback)
      id = Registry.get_id(registry, callback)
      {:ok, retrieved} = Registry.get_callback(registry, id)

      assert retrieved == callback
    end

    test "maintains consistency between forward and reverse maps" do
      registry = Registry.new()
      callback1 = fn _, _, _ -> %{} end
      callback2 = fn _, _, _ -> %{} end

      registry =
        registry
        |> Registry.register(callback1)
        |> Registry.register(callback2)

      # Every ID in callbacks should have reverse mapping
      for {id, callback} <- registry.callbacks do
        assert registry.reverse_map[callback] == id
      end

      # Every callback in reverse_map should have forward mapping
      for {callback, id} <- registry.reverse_map do
        assert registry.callbacks[id] == callback
      end
    end
  end

  describe "all_callbacks/1" do
    test "returns empty map for new registry" do
      registry = Registry.new()

      assert Registry.all_callbacks(registry) == %{}
    end

    test "returns all registered callbacks" do
      registry = Registry.new()
      callback1 = fn _, _, _ -> %{} end
      callback2 = fn _, _, _ -> %{} end

      registry =
        registry
        |> Registry.register(callback1)
        |> Registry.register(callback2)

      callbacks = Registry.all_callbacks(registry)

      assert map_size(callbacks) == 2
      assert callbacks["hook_0"] == callback1
      assert callbacks["hook_1"] == callback2
    end
  end

  describe "count/1" do
    test "returns 0 for new registry" do
      registry = Registry.new()

      assert Registry.count(registry) == 0
    end

    test "returns count of registered callbacks" do
      registry = Registry.new()

      registry =
        registry
        |> Registry.register(fn _, _, _ -> %{} end)
        |> Registry.register(fn _, _, _ -> %{} end)
        |> Registry.register(fn _, _, _ -> %{} end)

      assert Registry.count(registry) == 3
    end

    test "count doesn't increase for duplicate registrations" do
      registry = Registry.new()
      callback = fn _, _, _ -> %{} end

      registry =
        registry
        |> Registry.register(callback)
        |> Registry.register(callback)
        |> Registry.register(callback)

      assert Registry.count(registry) == 1
    end
  end
end
