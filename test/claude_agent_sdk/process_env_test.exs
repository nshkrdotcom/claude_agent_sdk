defmodule ClaudeAgentSDK.ProcessEnvTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Options, Process}
  alias ClaudeAgentSDK.Streaming.Session

  test "env builder merges option overrides and user" do
    options = %Options{
      env: %{"PORT_ENV_TEST" => "from_process", :PATH => "/custom"},
      user: "runner"
    }

    env_map =
      Process.__env_vars__(options)
      |> Map.new()

    assert env_map["PORT_ENV_TEST"] == "from_process"
    assert env_map["PATH"] == "/custom"
    assert env_map["USER"] == "runner"
    assert env_map["LOGNAME"] == "runner"
    assert env_map["CLAUDE_CODE_ENTRYPOINT"] == "sdk-elixir"
    assert env_map["CLAUDE_AGENT_SDK_VERSION"]
  end

  test "governed env builder uses only authority materialized env" do
    previous = %{
      "ANTHROPIC_API_KEY" => ClaudeAgentSDK.Env.get("ANTHROPIC_API_KEY"),
      "CLAUDE_AGENT_OAUTH_TOKEN" => ClaudeAgentSDK.Env.get("CLAUDE_AGENT_OAUTH_TOKEN"),
      "ANTHROPIC_BASE_URL" => ClaudeAgentSDK.Env.get("ANTHROPIC_BASE_URL"),
      "PATH" => ClaudeAgentSDK.Env.get("PATH"),
      "HOME" => ClaudeAgentSDK.Env.get("HOME")
    }

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> ClaudeAgentSDK.Env.delete(key)
        {key, value} -> ClaudeAgentSDK.Env.put(key, value)
      end)
    end)

    ClaudeAgentSDK.Env.put("ANTHROPIC_API_KEY", "ambient-api-key")
    ClaudeAgentSDK.Env.put("CLAUDE_AGENT_OAUTH_TOKEN", "ambient-oauth")
    ClaudeAgentSDK.Env.put("ANTHROPIC_BASE_URL", "https://ambient.example")

    env_map =
      %Options{governed_authority: authority()}
      |> Process.__env_vars__()
      |> Map.new()

    assert env_map == %{"CLAUDE_CONFIG_DIR" => "/authority/config"}
  end

  test "governed invocation rejects env and model payload overrides" do
    assert {:error, {:governed_launch_smuggling, :env}} =
             ClaudeAgentSDK.GovernedLaunch.validate_options(%Options{
               governed_authority: authority(),
               env: %{"ANTHROPIC_API_KEY" => "ambient"}
             })

    assert {:error, {:governed_launch_smuggling, :model_payload, :env_overrides}} =
             ClaudeAgentSDK.GovernedLaunch.validate_options(%Options{
               governed_authority: authority(),
               model_payload: %{
                 "env_overrides" => %{
                   "ANTHROPIC_AUTH_TOKEN" => "ollama",
                   "ANTHROPIC_BASE_URL" => "http://ambient"
                 }
               }
             })
  end

  test "env builder sets file checkpointing env var when enabled" do
    options = %Options{enable_file_checkpointing: true}

    env_map =
      options
      |> Process.__env_vars__()
      |> Map.new()

    assert env_map["CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"] == "true"
  end

  test "env builder applies model payload env overrides after option env" do
    options = %Options{
      env: %{"ANTHROPIC_BASE_URL" => "http://wrong"},
      model_payload: %{
        "env_overrides" => %{
          "ANTHROPIC_AUTH_TOKEN" => "ollama",
          "ANTHROPIC_API_KEY" => "",
          "ANTHROPIC_BASE_URL" => "http://localhost:11434"
        }
      }
    }

    env_map =
      options
      |> Process.__env_vars__()
      |> Map.new()

    assert env_map["ANTHROPIC_AUTH_TOKEN"] == "ollama"
    assert env_map["ANTHROPIC_API_KEY"] == ""
    assert env_map["ANTHROPIC_BASE_URL"] == "http://localhost:11434"
  end

  test "env builder propagates trace context and filters CLAUDECODE" do
    previous = %{
      "TRACEPARENT" => ClaudeAgentSDK.Env.get("TRACEPARENT"),
      "TRACESTATE" => ClaudeAgentSDK.Env.get("TRACESTATE"),
      "CLAUDECODE" => ClaudeAgentSDK.Env.get("CLAUDECODE")
    }

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> ClaudeAgentSDK.Env.delete(key)
        {key, value} -> ClaudeAgentSDK.Env.put(key, value)
      end)
    end)

    ClaudeAgentSDK.Env.put(
      "TRACEPARENT",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
    )

    ClaudeAgentSDK.Env.put("TRACESTATE", "vendor=value")
    ClaudeAgentSDK.Env.put("CLAUDECODE", "internal")

    env_map =
      %Options{env: %{"CLAUDECODE" => "explicit"}}
      |> Process.__env_vars__()
      |> Map.new()

    assert env_map["TRACEPARENT"] ==
             "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"

    assert env_map["TRACESTATE"] == "vendor=value"
    refute Map.has_key?(env_map, "CLAUDECODE")
  end

  test "shell escaping preserves empty string arguments" do
    assert Process.__shell_escape__("") == "\"\""
  end

  test "shell escaping includes redirection operators" do
    assert Process.__shell_escape__("a>b") == "\"a>b\""
    assert Process.__shell_escape__("a<b") == "\"a<b\""
  end

  test "process and streaming session use the same shell escaping rules" do
    for arg <- ["plain", "needs space", "quote\"test", "bang!", "a>b", "a<b"] do
      assert Process.__shell_escape__(arg) == Session.__shell_escape__(arg)
    end
  end

  defp authority do
    [
      authority_ref: "authority://claude/process",
      credential_lease_ref: "lease://claude/process",
      connector_instance_ref: "connector-instance://claude/process",
      connector_binding_ref: "connector-binding://claude/process",
      provider_account_ref: "provider-account://claude/process",
      native_auth_assertion_ref: "native-auth-assertion://claude/process",
      target_ref: "target://local/process",
      operation_policy_ref: "operation-policy://claude/process",
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
