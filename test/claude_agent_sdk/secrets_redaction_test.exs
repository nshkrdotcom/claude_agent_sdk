defmodule ClaudeAgentSDK.SecretsRedactionTest do
  @moduledoc """
  Env-var & secrets hygiene coverage: Inspect redaction of secret-bearing
  structs, the allowlisted runtime env snapshot, and token-file permissions.
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.Config.Env, as: EnvConfig
  alias ClaudeAgentSDK.Options

  describe "Inspect redaction" do
    test "AuthManager state redacts the token on inspect" do
      state = %ClaudeAgentSDK.AuthManager{token: "sk-ant-oat01-SECRETVALUE", expiry: nil}
      rendered = inspect(state)

      refute rendered =~ "SECRETVALUE"
      assert rendered =~ "AuthManager"
    end

    test "Options redacts auth token and env on inspect" do
      options = %Options{
        anthropic_auth_token: "sk-ant-SECRETTOKEN",
        env: %{"ANTHROPIC_API_KEY" => "sk-ant-SECRETKEY"},
        model: "sonnet"
      }

      rendered = inspect(options)

      refute rendered =~ "SECRETTOKEN"
      refute rendered =~ "SECRETKEY"
      # Non-secret fields stay visible.
      assert rendered =~ "sonnet"
    end
  end

  describe "runtime env snapshot allowlist" do
    test "keeps every known SDK variable" do
      os_env = Map.new(EnvConfig.all_known_vars(), &{&1, "value"})
      assert EnvConfig.snapshot(os_env) == os_env
    end

    test "keeps CLAUDE_/ANTHROPIC_ namespaced variables" do
      os_env = %{
        "CLAUDE_FUTURE_FLAG" => "1",
        "ANTHROPIC_FUTURE_SETTING" => "x"
      }

      assert EnvConfig.snapshot(os_env) == os_env
    end

    test "drops unrelated variables (secrets must not be copied)" do
      os_env = %{
        "DATABASE_URL" => "postgres://user:secret@host/db",
        "GITHUB_TOKEN" => "ghp_secret",
        "SSH_AUTH_SOCK" => "/tmp/ssh.sock",
        "PATH" => "/usr/bin"
      }

      assert EnvConfig.snapshot(os_env) == %{"PATH" => "/usr/bin"}
    end

    test "every var the SDK reads is in the allowlist" do
      # The union list must cover the whole Config.Env registry — a read
      # through a registry accessor that is missing from all_known_vars/0
      # would silently return nil after the runtime.exs allowlisting.
      registry_vars =
        [
          EnvConfig.anthropic_api_key(),
          EnvConfig.anthropic_auth_token(),
          EnvConfig.anthropic_base_url(),
          EnvConfig.anthropic_model(),
          EnvConfig.oauth_token(),
          EnvConfig.use_bedrock(),
          EnvConfig.use_vertex(),
          EnvConfig.provider_backend(),
          EnvConfig.external_model_overrides(),
          EnvConfig.entrypoint(),
          EnvConfig.sdk_version(),
          EnvConfig.file_checkpointing(),
          EnvConfig.stream_close_timeout(),
          EnvConfig.claudecode(),
          EnvConfig.skip_version_check(),
          EnvConfig.traceparent(),
          EnvConfig.tracestate(),
          EnvConfig.aws_access_key_id(),
          EnvConfig.aws_profile(),
          EnvConfig.gcp_credentials(),
          EnvConfig.gcp_project(),
          EnvConfig.ci(),
          EnvConfig.live_mode(),
          EnvConfig.live_tests()
        ] ++ EnvConfig.passthrough_vars()

      known = MapSet.new(EnvConfig.all_known_vars())

      for var <- registry_vars do
        assert MapSet.member?(known, var) or String.starts_with?(var, "CLAUDE_") or
                 String.starts_with?(var, "ANTHROPIC_"),
               "#{var} is read by the SDK but missing from the snapshot allowlist"
      end
    end
  end
end
