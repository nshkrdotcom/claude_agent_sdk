defmodule ClaudeAgentSDK.TokenStoreTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Auth.TokenStore
  alias ClaudeAgentSDK.TestEnvHelpers

  setup do
    lock_id = TestEnvHelpers.acquire_global_state_lock()

    path =
      Path.join(
        System.tmp_dir!(),
        "token_store_test_#{System.unique_integer([:positive])}.json"
      )

    original = Application.get_env(:claude_agent_sdk, :auth_file_path)
    Application.put_env(:claude_agent_sdk, :auth_file_path, path)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:claude_agent_sdk, :auth_file_path)
      else
        Application.put_env(:claude_agent_sdk, :auth_file_path, original)
      end

      TestEnvHelpers.release_global_state_lock(lock_id)
      File.rm(path)
    end)

    %{path: path}
  end

  test "load maps known provider strings", %{path: path} do
    write_token_file(path, "bedrock")

    assert {:ok, token_data} = TokenStore.load()
    assert token_data.provider == :bedrock
  end

  test "load defaults unknown provider strings to anthropic", %{path: path} do
    write_token_file(path, "unknown-provider")

    assert {:ok, token_data} = TokenStore.load()
    assert token_data.provider == :anthropic
  end

  test "load defaults nil provider to anthropic", %{path: path} do
    write_token_file(path, nil)

    assert {:ok, token_data} = TokenStore.load()
    assert token_data.provider == :anthropic
  end

  test "governed storage path uses authority auth root instead of app env", %{path: path} do
    authority_root = Path.join(Path.dirname(path), "authority-auth")
    authority_path = Path.join(authority_root, "token.json")
    File.mkdir_p!(authority_root)
    write_token_file(authority_path, "vertex")

    assert TokenStore.storage_path(governed_authority: authority(authority_root)) ==
             authority_path

    assert {:ok, token_data} = TokenStore.load(governed_authority: authority(authority_root))
    assert token_data.provider == :vertex
  end

  defp write_token_file(path, provider) do
    File.mkdir_p!(Path.dirname(path))

    payload =
      Jason.encode!(%{
        "token" => "sk-ant-oat01-test",
        "expiry" => nil,
        "provider" => provider
      })

    File.write!(path, payload)
  end

  defp authority(auth_root) do
    [
      authority_ref: "authority://claude/token-store",
      credential_lease_ref: "lease://claude/token-store",
      target_ref: "target://local/token-store",
      command: "/authority/bin/claude",
      cwd: "/workspace",
      env: %{"CLAUDE_CONFIG_DIR" => "/authority/config"},
      clear_env?: true,
      config_root: "/authority/config",
      auth_root: auth_root,
      base_url: "https://authority.example"
    ]
  end
end
