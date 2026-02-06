defmodule ClaudeAgentSDK.AuthManagerTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.AuthManager

  # Mock storage backend for testing using ETS
  defmodule MockStorage do
    @table :auth_manager_test_storage

    def start_link do
      # Create ETS table if it doesn't exist
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [:named_table, :public, :set])

        _ref ->
          :ok
      end

      {:ok, self()}
    end

    def save(data) do
      :ets.insert(@table, {:token_data, data})
      :ok
    end

    def load do
      case :ets.lookup(@table, :token_data) do
        [{:token_data, data}] -> {:ok, data}
        [] -> {:error, :not_found}
      end
    end

    def clear do
      :ets.delete(@table, :token_data)
      :ok
    end

    def reset do
      # Only reset if table exists
      case :ets.whereis(@table) do
        :undefined ->
          :ok

        _ref ->
          :ets.delete_all_objects(@table)
          :ok
      end
    end
  end

  defmodule InstrumentedStorage do
    @table :auth_manager_test_instrumented_storage

    def start_link do
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [:named_table, :public, :set])

        _ ->
          :ok
      end

      reset()
      {:ok, self()}
    end

    def reset do
      case :ets.whereis(@table) do
        :undefined ->
          :ok

        _ ->
          :ets.delete_all_objects(@table)
          configure([])
      end
    end

    def configure(opts) do
      :ets.insert(@table, {:save_return, Keyword.get(opts, :save_return, :ok)})
      :ets.insert(@table, {:clear_return, Keyword.get(opts, :clear_return, :ok)})
      :ets.insert(@table, {:load_return, Keyword.get(opts, :load_return, :not_found)})
      :ets.insert(@table, {:save_delay_ms, Keyword.get(opts, :save_delay_ms, 0)})
      :ets.insert(@table, {:save_calls, 0})
      :ets.insert(@table, {:clear_calls, 0})
      :ok
    end

    def save(data) do
      increment_counter(:save_calls)
      maybe_delay()

      case lookup(:save_return, :ok) do
        :ok ->
          :ets.insert(@table, {:token_data, data})
          :ok

        {:error, _reason} = error ->
          error
      end
    end

    def load do
      case lookup(:load_return, :not_found) do
        :token_data ->
          case :ets.lookup(@table, :token_data) do
            [{:token_data, data}] -> {:ok, data}
            [] -> {:error, :not_found}
          end

        :not_found ->
          {:error, :not_found}
      end
    end

    def clear do
      increment_counter(:clear_calls)

      case lookup(:clear_return, :ok) do
        :ok ->
          :ets.delete(@table, :token_data)
          :ok

        {:error, _reason} = error ->
          error
      end
    end

    def save_calls, do: lookup(:save_calls, 0)
    def clear_calls, do: lookup(:clear_calls, 0)

    defp maybe_delay do
      case lookup(:save_delay_ms, 0) do
        ms when is_integer(ms) and ms > 0 -> Process.sleep(ms)
        _ -> :ok
      end
    end

    defp increment_counter(key) do
      value = lookup(key, 0)
      :ets.insert(@table, {key, value + 1})
      :ok
    end

    defp lookup(key, default) do
      case :ets.lookup(@table, key) do
        [{^key, value}] -> value
        [] -> default
      end
    end
  end

  defmodule SlowLoadStorage do
    def save(_data), do: :ok
    def clear, do: :ok

    def load do
      Process.sleep(400)
      {:error, :not_found}
    end
  end

  setup do
    # Clean environment before each test
    System.delete_env("ANTHROPIC_API_KEY")
    System.delete_env("CLAUDE_AGENT_OAUTH_TOKEN")
    System.delete_env("CI")

    # Start mock storage (ETS-based, survives restarts)
    MockStorage.start_link()
    MockStorage.reset()
    InstrumentedStorage.start_link()
    InstrumentedStorage.reset()

    # Start AuthManager with mock storage
    start_supervised!({AuthManager, storage_backend: MockStorage})

    on_exit(fn ->
      # Clean up environment
      System.delete_env("ANTHROPIC_API_KEY")
      System.delete_env("CLAUDE_AGENT_OAUTH_TOKEN")
      System.delete_env("CI")

      # Clear mock storage
      MockStorage.reset()
      InstrumentedStorage.reset()
    end)

    :ok
  end

  describe "ensure_authenticated/0" do
    test "returns :ok when ANTHROPIC_API_KEY is set" do
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-test-key")

      assert :ok = AuthManager.ensure_authenticated()
    end

    test "returns :ok when CLAUDE_AGENT_OAUTH_TOKEN is set" do
      System.put_env("CLAUDE_AGENT_OAUTH_TOKEN", "sk-ant-oat01-test-token")

      assert :ok = AuthManager.ensure_authenticated()
    end

    test "returns :ok when valid token exists in storage" do
      # Pre-populate storage with valid token
      MockStorage.save(%{
        token: "sk-ant-oat01-test-token",
        # 1 day from now
        expiry: DateTime.add(DateTime.utc_now(), 86_400, :second),
        provider: :anthropic
      })

      # Restart AuthManager to load from storage
      :ok = stop_supervised(AuthManager)
      {:ok, _pid} = start_supervised({AuthManager, storage_backend: MockStorage})

      assert :ok = AuthManager.ensure_authenticated()
    end

    test "returns error when not authenticated and not interactive" do
      # Simulate non-interactive environment (CI)
      System.put_env("CI", "true")

      assert {:error, :authentication_required} = AuthManager.ensure_authenticated()
    end
  end

  describe "get_token/0" do
    test "returns env var token when ANTHROPIC_API_KEY is set" do
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-test-key-from-env")

      assert {:ok, "sk-ant-test-key-from-env"} = AuthManager.get_token()
    end

    test "prefers CLAUDE_AGENT_OAUTH_TOKEN over ANTHROPIC_API_KEY" do
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-api-key")
      System.put_env("CLAUDE_AGENT_OAUTH_TOKEN", "sk-ant-oat01-oauth-token")

      assert {:ok, "sk-ant-oat01-oauth-token"} = AuthManager.get_token()
    end

    test "returns stored token when available" do
      # Pre-populate storage
      MockStorage.save(%{
        token: "sk-ant-oat01-stored-token",
        expiry: DateTime.add(DateTime.utc_now(), 86_400, :second),
        provider: :anthropic
      })

      # Restart to load from storage
      :ok = stop_supervised(AuthManager)
      {:ok, _pid} = start_supervised({AuthManager, storage_backend: MockStorage})

      assert {:ok, "sk-ant-oat01-stored-token"} = AuthManager.get_token()
    end

    test "returns error when not authenticated" do
      assert {:error, :not_authenticated} = AuthManager.get_token()
    end

    test "returns error when token expired" do
      # Pre-populate storage with expired token
      MockStorage.save(%{
        token: "sk-ant-oat01-expired-token",
        # 1 day ago
        expiry: DateTime.add(DateTime.utc_now(), -86_400, :second),
        provider: :anthropic
      })

      # Restart to load from storage
      :ok = stop_supervised(AuthManager)
      {:ok, _pid} = start_supervised({AuthManager, storage_backend: MockStorage})

      assert {:error, :not_authenticated} = AuthManager.get_token()
    end
  end

  describe "clear_auth/0" do
    test "clears stored authentication" do
      # Setup token
      MockStorage.save(%{
        token: "sk-ant-oat01-test",
        expiry: DateTime.add(DateTime.utc_now(), 86_400, :second),
        provider: :anthropic
      })

      # Restart to load
      :ok = stop_supervised(AuthManager)
      {:ok, _pid} = start_supervised({AuthManager, storage_backend: MockStorage})

      # Verify token exists
      assert {:ok, _token} = AuthManager.get_token()

      # Clear
      :ok = AuthManager.clear_auth()

      # Verify cleared
      assert {:error, :not_authenticated} = AuthManager.get_token()

      # Verify cleared from storage
      assert {:error, :not_found} = MockStorage.load()
    end
  end

  describe "status/0" do
    test "returns authentication status when authenticated via env var" do
      previous_vertex = System.get_env("CLAUDE_AGENT_USE_VERTEX")
      previous_bedrock = System.get_env("CLAUDE_AGENT_USE_BEDROCK")
      previous_anthropic = System.get_env("ANTHROPIC_API_KEY")

      on_exit(fn ->
        restore_env("CLAUDE_AGENT_USE_VERTEX", previous_vertex)
        restore_env("CLAUDE_AGENT_USE_BEDROCK", previous_bedrock)
        restore_env("ANTHROPIC_API_KEY", previous_anthropic)
      end)

      System.delete_env("CLAUDE_AGENT_USE_VERTEX")
      System.delete_env("CLAUDE_AGENT_USE_BEDROCK")
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-test-key")

      status = AuthManager.status()

      assert status.authenticated == true
      assert status.provider == :anthropic
      # Using env var, not stored token
      assert status.token_present == false
    end

    test "returns status with token details" do
      # 7 days
      expiry = DateTime.add(DateTime.utc_now(), 7 * 86_400, :second)

      MockStorage.save(%{
        token: "sk-ant-oat01-test",
        expiry: expiry,
        provider: :anthropic
      })

      # Restart to load
      :ok = stop_supervised(AuthManager)
      {:ok, _pid} = start_supervised({AuthManager, storage_backend: MockStorage})

      status = AuthManager.status()

      assert status.authenticated == true
      assert status.token_present == true
      assert status.expires_at == expiry
      assert is_float(status.time_until_expiry_hours)
      assert status.time_until_expiry_hours > 0
    end

    test "returns not authenticated when no credentials" do
      status = AuthManager.status()

      assert status.authenticated == false
      assert status.token_present == false
    end
  end

  describe "backend failures and async setup behavior" do
    setup do
      previous_bedrock = System.get_env("CLAUDE_AGENT_USE_BEDROCK")
      previous_vertex = System.get_env("CLAUDE_AGENT_USE_VERTEX")
      previous_profile = System.get_env("AWS_PROFILE")

      on_exit(fn ->
        restore_env("CLAUDE_AGENT_USE_BEDROCK", previous_bedrock)
        restore_env("CLAUDE_AGENT_USE_VERTEX", previous_vertex)
        restore_env("AWS_PROFILE", previous_profile)
      end)

      :ok
    end

    test "clear_auth surfaces backend clear failure without crashing manager" do
      :ok = stop_supervised(AuthManager)
      InstrumentedStorage.configure(clear_return: {:error, :clear_failed})
      start_supervised!({AuthManager, storage_backend: InstrumentedStorage})

      assert {:error, :clear_failed} = AuthManager.clear_auth()
      assert Process.alive?(Process.whereis(AuthManager))
    end

    test "setup_token surfaces backend save failure without crashing manager" do
      System.put_env("CLAUDE_AGENT_USE_BEDROCK", "1")
      System.delete_env("CLAUDE_AGENT_USE_VERTEX")
      System.put_env("AWS_PROFILE", "test-profile")

      :ok = stop_supervised(AuthManager)
      InstrumentedStorage.configure(save_return: {:error, :disk_full})
      start_supervised!({AuthManager, storage_backend: InstrumentedStorage})

      assert {:error, :disk_full} = AuthManager.setup_token()
      assert Process.alive?(Process.whereis(AuthManager))
    end

    test "status remains responsive while setup_token is in progress" do
      System.put_env("CLAUDE_AGENT_USE_BEDROCK", "1")
      System.delete_env("CLAUDE_AGENT_USE_VERTEX")
      System.put_env("AWS_PROFILE", "test-profile")

      :ok = stop_supervised(AuthManager)

      InstrumentedStorage.configure(
        save_return: :ok,
        save_delay_ms: 250
      )

      start_supervised!({AuthManager, storage_backend: InstrumentedStorage})

      setup_task = Task.async(fn -> AuthManager.setup_token() end)

      assert_eventually(fn -> InstrumentedStorage.save_calls() == 1 end)

      status_task = Task.async(fn -> AuthManager.status() end)
      status = Task.await(status_task, 100)

      assert is_map(status)
      assert {:ok, "aws-bedrock"} = Task.await(setup_task, 1_000)
    end

    test "concurrent setup_token calls are deduplicated while a setup is running" do
      System.put_env("CLAUDE_AGENT_USE_BEDROCK", "1")
      System.delete_env("CLAUDE_AGENT_USE_VERTEX")
      System.put_env("AWS_PROFILE", "test-profile")

      :ok = stop_supervised(AuthManager)

      InstrumentedStorage.configure(
        save_return: :ok,
        save_delay_ms: 200
      )

      start_supervised!({AuthManager, storage_backend: InstrumentedStorage})

      task_one = Task.async(fn -> AuthManager.setup_token() end)
      assert_eventually(fn -> InstrumentedStorage.save_calls() == 1 end)

      task_two = Task.async(fn -> AuthManager.setup_token() end)

      assert {:ok, "aws-bedrock"} = Task.await(task_one, 1_000)
      assert {:ok, "aws-bedrock"} = Task.await(task_two, 1_000)
      assert InstrumentedStorage.save_calls() == 1
    end

    test "stale refresh messages are ignored after auth is cleared" do
      System.put_env("CLAUDE_AGENT_USE_BEDROCK", "1")
      System.delete_env("CLAUDE_AGENT_USE_VERTEX")
      System.put_env("AWS_PROFILE", "test-profile")

      :ok = stop_supervised(AuthManager)
      InstrumentedStorage.configure(save_return: :ok, clear_return: :ok)
      start_supervised!({AuthManager, storage_backend: InstrumentedStorage})

      assert {:ok, "aws-bedrock"} = AuthManager.setup_token()
      save_calls = InstrumentedStorage.save_calls()
      assert :ok = AuthManager.clear_auth()

      send(AuthManager, :refresh_token)
      Process.sleep(50)

      assert InstrumentedStorage.save_calls() == save_calls
    end
  end

  describe "startup lifecycle" do
    test "start_link does not block on storage load" do
      :ok = stop_supervised(AuthManager)

      start_ms = System.monotonic_time(:millisecond)
      {:ok, pid} = AuthManager.start_link(storage_backend: SlowLoadStorage)
      elapsed_ms = System.monotonic_time(:millisecond) - start_ms

      assert elapsed_ms < 250
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "setup_token/0 (integration)" do
    # Skip by default - requires actual claude CLI
    @describetag :skip
    @describetag :integration
    test "acquires token via claude CLI" do
      # This test requires:
      # 1. claude CLI installed
      # 2. Interactive terminal
      # 3. Claude subscription
      # Should be run manually

      System.delete_env("ANTHROPIC_API_KEY")
      System.delete_env("CI")

      case AuthManager.setup_token() do
        {:ok, token} ->
          # OAuth token format
          assert String.starts_with?(token, "sk-ant-oat01-") or
                   String.starts_with?(token, "sk-ant-api03-")

          # Token format
          assert String.length(token) >= 95

          # Verify token is stored
          {:ok, stored_token} = AuthManager.get_token()
          assert stored_token == token

        {:error, reason} ->
          # Expected in CI or without subscription
          assert is_binary(reason)
      end
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp assert_eventually(fun, attempts \\ 30)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      assert true
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition not met")
end
