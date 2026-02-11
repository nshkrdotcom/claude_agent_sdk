defmodule ClaudeAgentSDK.Config.AuthTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Config.Auth

  setup do
    original = Application.get_env(:claude_agent_sdk, Auth)
    on_exit(fn -> restore(original) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:claude_agent_sdk, Auth)
  defp restore(val), do: Application.put_env(:claude_agent_sdk, Auth, val)

  describe "defaults" do
    test "token_store_path" do
      assert Auth.token_store_path() == "~/.claude_sdk/token.json"
    end

    test "session_storage_dir" do
      assert Auth.session_storage_dir() == "~/.claude_sdk/sessions"
    end

    test "token_ttl_days" do
      assert Auth.token_ttl_days() == 365
    end

    test "session_max_age_days" do
      assert Auth.session_max_age_days() == 30
    end

    test "oauth_token_prefix" do
      assert Auth.oauth_token_prefix() == "sk-ant-oat01-"
    end

    test "api_key_prefix" do
      assert Auth.api_key_prefix() == "sk-ant-"
    end

    test "aws_credentials_path" do
      assert Auth.aws_credentials_path() == "~/.aws/credentials"
    end

    test "gcp_credentials_path" do
      assert Auth.gcp_credentials_path() =~
               "application_default_credentials.json"
    end

    test "providers" do
      assert Auth.providers() == [:anthropic, :bedrock, :vertex]
    end
  end

  describe "runtime override" do
    test "overrides token_store_path" do
      Application.put_env(:claude_agent_sdk, Auth, token_store_path: "/tmp/tok.json")

      assert Auth.token_store_path() == "/tmp/tok.json"
    end
  end
end
