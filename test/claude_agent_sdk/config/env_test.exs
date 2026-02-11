defmodule ClaudeAgentSDK.Config.EnvTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Config.Env

  describe "anthropic auth" do
    test "anthropic_api_key" do
      assert Env.anthropic_api_key() == "ANTHROPIC_API_KEY"
    end

    test "oauth_token" do
      assert Env.oauth_token() == "CLAUDE_AGENT_OAUTH_TOKEN"
    end
  end

  describe "provider selectors" do
    test "use_bedrock" do
      assert Env.use_bedrock() == "CLAUDE_AGENT_USE_BEDROCK"
    end

    test "use_vertex" do
      assert Env.use_vertex() == "CLAUDE_AGENT_USE_VERTEX"
    end
  end

  describe "SDK control" do
    test "entrypoint" do
      assert Env.entrypoint() == "CLAUDE_CODE_ENTRYPOINT"
    end

    test "sdk_version" do
      assert Env.sdk_version() == "CLAUDE_AGENT_SDK_VERSION"
    end

    test "file_checkpointing" do
      assert Env.file_checkpointing() =~ "CHECKPOINTING"
    end

    test "stream_close_timeout" do
      assert Env.stream_close_timeout() =~ "STREAM_CLOSE"
    end

    test "skip_version_check" do
      assert Env.skip_version_check() =~ "SKIP_VERSION"
    end
  end

  describe "cloud providers" do
    test "aws_access_key_id" do
      assert Env.aws_access_key_id() == "AWS_ACCESS_KEY_ID"
    end

    test "aws_profile" do
      assert Env.aws_profile() == "AWS_PROFILE"
    end

    test "gcp_credentials" do
      assert Env.gcp_credentials() == "GOOGLE_APPLICATION_CREDENTIALS"
    end

    test "gcp_project" do
      assert Env.gcp_project() == "GOOGLE_CLOUD_PROJECT"
    end
  end

  describe "CI / test" do
    test "ci" do
      assert Env.ci() == "CI"
    end

    test "live_mode" do
      assert Env.live_mode() == "LIVE_MODE"
    end

    test "live_tests" do
      assert Env.live_tests() == "LIVE_TESTS"
    end
  end

  describe "passthrough_vars" do
    test "includes auth keys and system vars" do
      vars = Env.passthrough_vars()
      assert "CLAUDE_AGENT_OAUTH_TOKEN" in vars
      assert "ANTHROPIC_API_KEY" in vars
      assert "PATH" in vars
      assert "HOME" in vars
    end
  end
end
