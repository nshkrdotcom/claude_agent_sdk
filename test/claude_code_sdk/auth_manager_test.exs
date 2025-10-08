defmodule ClaudeCodeSDK.AuthManagerTest do
  use ExUnit.Case, async: false

  alias ClaudeCodeSDK.AuthManager

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

  setup do
    # Clean environment before each test
    System.delete_env("ANTHROPIC_API_KEY")
    System.delete_env("CLAUDE_CODE_OAUTH_TOKEN")
    System.delete_env("CI")

    # Start mock storage (ETS-based, survives restarts)
    MockStorage.start_link()
    MockStorage.reset()

    # Start AuthManager with mock storage
    start_supervised!({AuthManager, storage_backend: MockStorage})

    on_exit(fn ->
      # Clean up environment
      System.delete_env("ANTHROPIC_API_KEY")
      System.delete_env("CLAUDE_CODE_OAUTH_TOKEN")
      System.delete_env("CI")

      # Clear mock storage
      MockStorage.reset()
    end)

    :ok
  end

  describe "ensure_authenticated/0" do
    test "returns :ok when ANTHROPIC_API_KEY is set" do
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-test-key")

      assert :ok = AuthManager.ensure_authenticated()
    end

    test "returns :ok when CLAUDE_CODE_OAUTH_TOKEN is set" do
      System.put_env("CLAUDE_CODE_OAUTH_TOKEN", "sk-ant-oat01-test-token")

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

    test "prefers CLAUDE_CODE_OAUTH_TOKEN over ANTHROPIC_API_KEY" do
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-api-key")
      System.put_env("CLAUDE_CODE_OAUTH_TOKEN", "sk-ant-oat01-oauth-token")

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
end
