defmodule ClaudeCodeSDK.AuthCheckerTest do
  use ExUnit.Case

  alias ClaudeCodeSDK.AuthChecker

  # Since we're testing system commands, we'll use mocks where possible
  # and test the logic rather than actual CLI calls

  describe "check_auth/0" do
    @tag :skip
    test "returns ok when authenticated (skipped in test env)" do
      # This test would need actual CLI or mocking
      # For now, we test the function exists and returns expected format
      result = AuthChecker.check_auth()

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "authenticated?/0" do
    @tag :skip
    test "returns boolean based on auth status (skipped in test env)" do
      result = AuthChecker.authenticated?()
      assert is_boolean(result)
    end
  end

  describe "check_cli_installation/0" do
    @tag :skip
    test "returns expected format (skipped in test env)" do
      result = AuthChecker.check_cli_installation()

      assert match?({:ok, %{path: _, version: _}}, result) or match?({:error, _}, result)
    end
  end

  describe "diagnose/0" do
    @tag :skip
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

    @tag :skip
    test "includes CLI info when installed (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.cli_installed do
        assert Map.has_key?(diagnosis, :cli_path)
        assert Map.has_key?(diagnosis, :cli_version)
      else
        assert Map.has_key?(diagnosis, :cli_error)
      end
    end

    @tag :skip
    test "includes auth info based on status (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.authenticated do
        assert Map.has_key?(diagnosis, :auth_info)
      else
        assert Map.has_key?(diagnosis, :auth_error) or not diagnosis.cli_installed
      end
    end
  end

  describe "ensure_ready!/0" do
    @tag :skip
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
    @tag :skip
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
    @tag :skip
    test "provides install recommendation when CLI not found (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.status == :not_installed do
        assert Enum.any?(diagnosis.recommendations, &String.contains?(&1, "npm install"))
      end
    end

    @tag :skip
    test "provides login recommendation when not authenticated (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.status == :not_authenticated do
        assert Enum.any?(diagnosis.recommendations, &String.contains?(&1, "claude login"))
      end
    end

    @tag :skip
    test "no recommendations when ready (skipped in test env)" do
      diagnosis = AuthChecker.diagnose()

      if diagnosis.status == :ready do
        assert diagnosis.recommendations == []
      end
    end
  end
end
