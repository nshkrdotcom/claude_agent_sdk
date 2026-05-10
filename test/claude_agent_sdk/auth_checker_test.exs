defmodule ClaudeAgentSDK.AuthCheckerTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.AuthChecker

  # Since we're testing system commands, we'll use mocks where possible
  # and test the logic rather than actual CLI calls

  describe "check_auth/0" do
    @tag :live_cli
    test "returns ok when authenticated (skipped in test env)" do
      # This test would need actual CLI or mocking
      # For now, we test the function exists and returns expected format
      result = AuthChecker.check_auth()

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "governed authority auth checks" do
    test "valid governed authority ignores ambient standalone env" do
      previous_api_key = ClaudeAgentSDK.Env.get("ANTHROPIC_API_KEY")
      previous_oauth = ClaudeAgentSDK.Env.get("CLAUDE_AGENT_OAUTH_TOKEN")

      on_exit(fn ->
        restore_env("ANTHROPIC_API_KEY", previous_api_key)
        restore_env("CLAUDE_AGENT_OAUTH_TOKEN", previous_oauth)
      end)

      ClaudeAgentSDK.Env.put("ANTHROPIC_API_KEY", "ambient-api-key")
      ClaudeAgentSDK.Env.put("CLAUDE_AGENT_OAUTH_TOKEN", "ambient-oauth")

      assert {:ok, "Governed authority materialized"} =
               AuthChecker.check_auth(governed_authority: authority())

      assert {:ok, "governed authority credential lease"} =
               AuthChecker.get_api_key_source(governed_authority: authority())

      diagnosis = AuthChecker.diagnose(governed_authority: authority())

      assert diagnosis.status == :ready
      assert diagnosis.api_key_source == "governed authority credential lease"
      assert diagnosis.authority_ref == "authority://claude/auth-checker"
      assert diagnosis.connector_instance_ref == "connector-instance://claude/auth-checker"
      assert diagnosis.connector_binding_ref == "connector-binding://claude/auth-checker"
      assert diagnosis.provider_account_ref == "provider-account://claude/auth-checker"
      assert diagnosis.native_auth_assertion_ref == "native-auth-assertion://claude/auth-checker"
      assert diagnosis.operation_policy_ref == "operation-policy://claude/auth-checker"
      assert diagnosis.env_keys == ["CLAUDE_CONFIG_DIR"]
    end

    test "invalid governed authority does not fall back to env" do
      previous_api_key = ClaudeAgentSDK.Env.get("ANTHROPIC_API_KEY")
      on_exit(fn -> restore_env("ANTHROPIC_API_KEY", previous_api_key) end)
      ClaudeAgentSDK.Env.put("ANTHROPIC_API_KEY", "ambient-api-key")

      assert {:error, message} = AuthChecker.check_auth(governed_authority: [])
      assert String.contains?(message, "Invalid governed authority")

      diagnosis = AuthChecker.diagnose(governed_authority: [])
      assert diagnosis.status == :not_authenticated
      assert diagnosis.api_key_source == nil
    end
  end

  describe "authenticated?/0" do
    @tag :live_cli
    test "returns boolean based on auth status (skipped in test env)" do
      result = AuthChecker.authenticated?()
      assert is_boolean(result)
    end
  end

  describe "check_cli_installation/0" do
    @tag :live_cli
    test "returns expected format (skipped in test env)" do
      result = AuthChecker.check_cli_installation()

      assert match?({:ok, %{path: _, version: _}}, result) or match?({:error, _}, result)
    end

    test "returns the resolved executable path when CLI is discovered outside PATH" do
      with_fake_cli(fn cli_path ->
        assert {:ok, %{path: ^cli_path, version: "1.2.3"}} =
                 AuthChecker.check_cli_installation()
      end)
    end
  end

  describe "diagnose/0" do
    @tag :live_cli
    test "returns comprehensive diagnostic map (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      assert is_map(diagnosis)
      assert Map.has_key?(diagnosis, :cli_installed)
      assert Map.has_key?(diagnosis, :authenticated)
      assert Map.has_key?(diagnosis, :status)
      assert Map.has_key?(diagnosis, :recommendations)

      assert diagnosis.status in [:ready, :not_installed, :not_authenticated, :error]
      assert is_list(diagnosis.recommendations)
    end

    @tag :live_cli
    test "includes CLI info when installed (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.cli_installed do
        assert Map.has_key?(diagnosis, :cli_path)
        assert Map.has_key?(diagnosis, :cli_version)
      else
        assert Map.has_key?(diagnosis, :cli_error)
      end
    end

    @tag :live_cli
    test "includes auth info based on status (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.authenticated do
        assert Map.has_key?(diagnosis, :auth_info)
      else
        assert Map.has_key?(diagnosis, :auth_error) or not diagnosis.cli_installed
      end
    end

    test "reports the resolved executable path and authenticates through it" do
      with_fake_cli(fn cli_path ->
        diagnosis = AuthChecker.diagnose()

        assert diagnosis.cli_installed == true
        assert diagnosis.cli_path == cli_path
        assert diagnosis.cli_version == "1.2.3"
        assert diagnosis.authenticated == true
        assert diagnosis.status == :ready
      end)
    end
  end

  describe "resolved executable probes" do
    test "check_auth succeeds when the discovered CLI is not on PATH" do
      with_fake_cli(fn _cli_path ->
        assert {:ok, "Authenticated"} = AuthChecker.check_auth()
      end)
    end
  end

  describe "ensure_ready!/0" do
    @tag :live_cli
    test "returns :ok or raises error (skipped in test env)" do
      # This will either succeed or raise
      try do
        result = AuthChecker.ensure_ready!()
        assert result == :ok
      rescue
        e in RuntimeError ->
          # Verify error message is helpful
          assert String.contains?(e.message, "Claude CLI") or
                   String.contains?(e.message, "authenticated")
      end
    end
  end

  # Test private helper functions indirectly

  describe "parse_auth_error/1 (indirect)" do
    @tag :live_cli
    test "diagnose provides helpful auth error messages (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis[:auth_error] do
        assert String.contains?(diagnosis.auth_error, "authenticate") or
                 String.contains?(diagnosis.auth_error, "Claude CLI") or
                 String.contains?(diagnosis.auth_error, "failed")
      end
    end
  end

  describe "recommendations" do
    @tag :live_cli
    test "provides install recommendation when CLI not found (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.status == :cli_not_found do
        assert Enum.any?(diagnosis.recommendations, &String.contains?(&1, "npm install"))
      end
    end

    @tag :live_cli
    test "provides login recommendation when not authenticated (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.status == :not_authenticated do
        assert Enum.any?(diagnosis.recommendations, &String.contains?(&1, "claude login"))
      end
    end

    @tag :live_cli
    test "no recommendations when ready (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.status == :ready do
        # When ready, the only recommendation is a positive confirmation message
        assert diagnosis.recommendations == ["Environment is ready for Claude queries"]
      end
    end
  end

  describe "auth_method_available?/1" do
    @tag :live_cli
    test "returns boolean for valid auth methods (skipped - calls CLI)" do
      assert is_boolean(AuthChecker.auth_method_available?(:anthropic))
      assert is_boolean(AuthChecker.auth_method_available?(:bedrock))
      assert is_boolean(AuthChecker.auth_method_available?(:vertex))
    end

    test "returns false for invalid auth methods" do
      assert AuthChecker.auth_method_available?(:invalid) == false
      assert AuthChecker.auth_method_available?(:unknown) == false
      assert AuthChecker.auth_method_available?(nil) == false
    end
  end

  describe "get_api_key_source/0" do
    @tag :live_cli
    test "returns tuple with ok or error (skipped - calls CLI)" do
      result = AuthChecker.get_api_key_source()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "detects environment variable when set" do
      # Mock the environment variable
      ClaudeAgentSDK.Env.put("ANTHROPIC_API_KEY", "test-key")

      try do
        {:ok, source} = AuthChecker.get_api_key_source()
        assert String.contains?(source, "ANTHROPIC_API_KEY")
      after
        ClaudeAgentSDK.Env.delete("ANTHROPIC_API_KEY")
      end
    end

    test "detects bedrock configuration when set" do
      original_api = ClaudeAgentSDK.Env.get("ANTHROPIC_API_KEY")
      ClaudeAgentSDK.Env.delete("ANTHROPIC_API_KEY")
      ClaudeAgentSDK.Env.put("CLAUDE_AGENT_USE_BEDROCK", "1")
      ClaudeAgentSDK.Env.put("AWS_ACCESS_KEY_ID", "test-key")

      try do
        result = AuthChecker.get_api_key_source()

        case result do
          {:ok, source} -> assert String.contains?(source, "AWS")
          # May not have full AWS setup
          {:error, _} -> :ok
        end
      after
        if original_api, do: ClaudeAgentSDK.Env.put("ANTHROPIC_API_KEY", original_api)
        ClaudeAgentSDK.Env.delete("CLAUDE_AGENT_USE_BEDROCK")
        ClaudeAgentSDK.Env.delete("AWS_ACCESS_KEY_ID")
      end
    end

    test "detects vertex configuration when set" do
      original_api = ClaudeAgentSDK.Env.get("ANTHROPIC_API_KEY")
      ClaudeAgentSDK.Env.delete("ANTHROPIC_API_KEY")
      ClaudeAgentSDK.Env.put("CLAUDE_AGENT_USE_VERTEX", "1")
      ClaudeAgentSDK.Env.put("GOOGLE_CLOUD_PROJECT", "test-project")

      try do
        result = AuthChecker.get_api_key_source()

        case result do
          {:ok, source} -> assert String.contains?(source, "Google")
          # May not have full GCP setup
          {:error, _} -> :ok
        end
      after
        if original_api, do: ClaudeAgentSDK.Env.put("ANTHROPIC_API_KEY", original_api)
        ClaudeAgentSDK.Env.delete("CLAUDE_AGENT_USE_VERTEX")
        ClaudeAgentSDK.Env.delete("GOOGLE_CLOUD_PROJECT")
      end
    end
  end

  describe "diagnosis struct validation" do
    @tag :live_cli
    test "diagnosis contains all required fields (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      # Test all required fields exist
      required_fields = [
        :cli_installed,
        :cli_version,
        :cli_path,
        :cli_error,
        :authenticated,
        :auth_method,
        :auth_info,
        :auth_error,
        :api_key_source,
        :status,
        :recommendations,
        :last_checked
      ]

      for field <- required_fields do
        assert Map.has_key?(diagnosis, field), "Missing field: #{field}"
      end

      # Test field types
      assert is_boolean(diagnosis.cli_installed)
      assert is_boolean(diagnosis.authenticated)

      assert diagnosis.status in [
               :ready,
               :cli_not_found,
               :not_authenticated,
               :invalid_credentials,
               :unknown
             ]

      assert is_list(diagnosis.recommendations)
      assert %DateTime{} = diagnosis.last_checked
    end

    @tag :live_cli
    test "diagnosis fields are consistent (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      # If CLI not installed, other fields should reflect this
      if not diagnosis.cli_installed do
        assert diagnosis.status == :cli_not_found
        assert diagnosis.cli_error != nil
        assert diagnosis.authenticated == false
      end

      # If authenticated, should have auth info
      if diagnosis.authenticated do
        assert diagnosis.auth_method != nil
        assert diagnosis.status in [:ready]
      end

      # Status should match overall state
      case diagnosis.status do
        :ready ->
          assert diagnosis.cli_installed == true
          assert diagnosis.authenticated == true

        :cli_not_found ->
          assert diagnosis.cli_installed == false

        :not_authenticated ->
          assert diagnosis.cli_installed == true
          assert diagnosis.authenticated == false
      end
    end
  end

  describe "enhanced multi-provider auth support" do
    @tag :live_cli
    test "supports multiple authentication providers (skipped - calls CLI)" do
      # Test that all expected providers are recognized
      providers = [:anthropic, :bedrock, :vertex]

      for provider <- providers do
        # Should return boolean without error
        result = AuthChecker.auth_method_available?(provider)
        assert is_boolean(result)
      end
    end

    @tag :live_cli
    test "provides provider-specific recommendations (skipped in test env)" do
      # Test with Bedrock environment
      ClaudeAgentSDK.Env.put("CLAUDE_AGENT_USE_BEDROCK", "1")

      try do
        diagnosis = AuthChecker.diagnose()

        if diagnosis.status == :not_authenticated do
          bedrock_rec = Enum.any?(diagnosis.recommendations, &String.contains?(&1, "AWS"))
          assert bedrock_rec, "Should include AWS-specific recommendations"
        end
      after
        ClaudeAgentSDK.Env.delete("CLAUDE_AGENT_USE_BEDROCK")
      end

      # Test with Vertex environment
      ClaudeAgentSDK.Env.put("CLAUDE_AGENT_USE_VERTEX", "1")

      try do
        diagnosis = AuthChecker.diagnose()

        if diagnosis.status == :not_authenticated do
          vertex_rec = Enum.any?(diagnosis.recommendations, &String.contains?(&1, "GCP"))
          assert vertex_rec, "Should include GCP-specific recommendations"
        end
      after
        ClaudeAgentSDK.Env.delete("CLAUDE_AGENT_USE_VERTEX")
      end
    end
  end

  defp with_fake_cli(fun) do
    dir = Path.join(System.tmp_dir!(), "auth_checker_cli_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cli_path = Path.join(dir, "custom-claude")

    File.write!(cli_path, fake_cli_script())
    File.chmod!(cli_path, 0o755)

    previous_cli_bundled = Application.get_env(:claude_agent_sdk, :cli_bundled_path)
    previous_known_locations = Application.get_env(:claude_agent_sdk, :cli_known_locations)
    previous_use_mock = Application.get_env(:claude_agent_sdk, :use_mock)
    previous_api_key = ClaudeAgentSDK.Env.get("ANTHROPIC_API_KEY")
    previous_oauth = ClaudeAgentSDK.Env.get("CLAUDE_AGENT_OAUTH_TOKEN")
    previous_bedrock = ClaudeAgentSDK.Env.get("CLAUDE_AGENT_USE_BEDROCK")
    previous_vertex = ClaudeAgentSDK.Env.get("CLAUDE_AGENT_USE_VERTEX")

    Application.put_env(:claude_agent_sdk, :cli_bundled_path, cli_path)
    Application.put_env(:claude_agent_sdk, :cli_known_locations, [])
    Application.put_env(:claude_agent_sdk, :use_mock, false)
    ClaudeAgentSDK.Env.delete("ANTHROPIC_API_KEY")
    ClaudeAgentSDK.Env.delete("CLAUDE_AGENT_OAUTH_TOKEN")
    ClaudeAgentSDK.Env.delete("CLAUDE_AGENT_USE_BEDROCK")
    ClaudeAgentSDK.Env.delete("CLAUDE_AGENT_USE_VERTEX")

    try do
      fun.(cli_path)
    after
      restore_app_env(:cli_bundled_path, previous_cli_bundled)
      restore_app_env(:cli_known_locations, previous_known_locations)
      restore_app_env(:use_mock, previous_use_mock)
      restore_env("ANTHROPIC_API_KEY", previous_api_key)
      restore_env("CLAUDE_AGENT_OAUTH_TOKEN", previous_oauth)
      restore_env("CLAUDE_AGENT_USE_BEDROCK", previous_bedrock)
      restore_env("CLAUDE_AGENT_USE_VERTEX", previous_vertex)
      File.rm_rf!(dir)
    end
  end

  defp fake_cli_script do
    """
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "${1:-}" == "--version" ]]; then
      echo "claude 1.2.3"
      exit 0
    fi

    if [[ "${1:-}" == "--print" && "${2:-}" == "test" && "${3:-}" == "--output-format" && "${4:-}" == "json" ]]; then
      echo '{"type":"result","subtype":"success","session_id":"fake-session","result":"ok","duration_ms":1,"duration_api_ms":1,"num_turns":1,"is_error":false}'
      exit 0
    fi

    if [[ "${1:-}" == "--print" && "${2:-}" == "hello" && "${3:-}" == "--max-turns" && "${4:-}" == "1" ]]; then
      echo "hello"
      exit 0
    fi

    echo "unexpected args: $*" >&2
    exit 1
    """
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:claude_agent_sdk, key)
  defp restore_app_env(key, value), do: Application.put_env(:claude_agent_sdk, key, value)

  defp restore_env(key, nil), do: ClaudeAgentSDK.Env.delete(key)
  defp restore_env(key, value), do: ClaudeAgentSDK.Env.put(key, value)

  defp authority do
    [
      authority_ref: "authority://claude/auth-checker",
      credential_lease_ref: "lease://claude/auth-checker",
      connector_instance_ref: "connector-instance://claude/auth-checker",
      connector_binding_ref: "connector-binding://claude/auth-checker",
      provider_account_ref: "provider-account://claude/auth-checker",
      native_auth_assertion_ref: "native-auth-assertion://claude/auth-checker",
      target_ref: "target://local/auth-checker",
      operation_policy_ref: "operation-policy://claude/auth-checker",
      command: "/authority/bin/claude",
      cwd: "/workspace",
      env: %{"CLAUDE_CONFIG_DIR" => "/authority/config"},
      clear_env?: true,
      config_root: "/authority/config",
      auth_root: "/authority/auth",
      base_url: "https://authority.example"
    ]
  end
end
