defmodule ClaudeAgentSDK.GovernedLaunchTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.{GovernedLaunch, Options}
  alias CliSubprocessCore.Command

  test "builds governed invocation only from materialized authority" do
    options = %Options{governed_authority: authority()}

    assert {:ok, %Command{} = command} = GovernedLaunch.invocation(["--print", "hi"], options)

    assert command.command == "/authority/bin/claude"
    assert command.args == ["--print", "hi"]
    assert command.cwd == "/workspace"
    assert command.env == %{"CLAUDE_CONFIG_DIR" => "/authority/config"}
    assert command.clear_env? == true
  end

  test "rejects caller launch and model payload smuggling in governed mode" do
    assert {:error, {:governed_launch_smuggling, :env}} =
             GovernedLaunch.validate_options(%Options{
               governed_authority: authority(),
               env: %{"ANTHROPIC_API_KEY" => "ambient"}
             })

    assert {:error, {:governed_launch_smuggling, :path_to_claude_code_executable}} =
             GovernedLaunch.validate_options(%Options{
               governed_authority: authority(),
               path_to_claude_code_executable: "/ambient/claude"
             })

    assert {:error, {:governed_launch_smuggling, :model_payload, :env_overrides}} =
             GovernedLaunch.validate_options(%Options{
               governed_authority: authority(),
               model_payload: %{"env_overrides" => %{"ANTHROPIC_BASE_URL" => "http://ambient"}}
             })

    assert {:error, {:governed_launch_smuggling, :model_payload, :backend_metadata}} =
             GovernedLaunch.validate_options(%Options{
               governed_authority: authority(),
               model_payload: %{"backend_metadata" => %{"provider_backend" => "ollama"}}
             })
  end

  test "standalone options are not governed" do
    refute GovernedLaunch.governed?(%Options{})
    assert :ok = GovernedLaunch.validate_options(%Options{env: %{"ANTHROPIC_API_KEY" => "dev"}})
  end

  test "keeps two native auth roots distinct through redacted projection" do
    {:ok, root_a} =
      GovernedLaunch.authority(%Options{
        governed_authority:
          authority(
            provider_account_ref: "provider-account://claude/a",
            native_auth_assertion_ref: "native-auth-assertion://claude/a",
            auth_root: "/authority/auth/a"
          )
      })

    {:ok, root_b} =
      GovernedLaunch.authority(%Options{
        governed_authority:
          authority(
            provider_account_ref: "provider-account://claude/b",
            native_auth_assertion_ref: "native-auth-assertion://claude/b",
            auth_root: "/authority/auth/b"
          )
      })

    assert root_a.provider_account_ref == "provider-account://claude/a"
    assert root_b.provider_account_ref == "provider-account://claude/b"
    assert root_a.native_auth_assertion_ref != root_b.native_auth_assertion_ref

    {:ok, projection} = GovernedLaunch.check_auth(governed_authority: authority())

    assert projection.connector_instance_ref == "connector-instance://claude/1"
    assert projection.provider_account_ref == "provider-account://claude/1"
    assert projection.native_auth_assertion_ref == "native-auth-assertion://claude/1"
    assert projection.env_keys == ["CLAUDE_CONFIG_DIR"]
    assert projection.command != "/authority/bin/claude"
    assert String.starts_with?(projection.auth_root, "[redacted:")
    refute String.contains?(inspect(projection), "/authority/auth")
  end

  defp authority(overrides \\ []) do
    [
      authority_ref: "authority://claude/1",
      credential_lease_ref: "lease://claude/1",
      connector_instance_ref: "connector-instance://claude/1",
      connector_binding_ref: "connector-binding://claude/1",
      provider_account_ref: "provider-account://claude/1",
      native_auth_assertion_ref: "native-auth-assertion://claude/1",
      target_ref: "target://local/1",
      operation_policy_ref: "operation-policy://claude/1",
      command: "/authority/bin/claude",
      cwd: "/workspace",
      env: %{"CLAUDE_CONFIG_DIR" => "/authority/config"},
      clear_env?: true,
      config_root: "/authority/config",
      auth_root: "/authority/auth",
      base_url: "https://authority.example"
    ]
    |> Keyword.merge(overrides)
  end
end
