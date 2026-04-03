defmodule ClaudeAgentSDK.ExamplesSupportTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.ExamplesSupport
  alias CliSubprocessCore.ExecutionSurface

  test "parse_argv/1 keeps local defaults when ssh flags are absent" do
    assert {:ok, context} = ExamplesSupport.parse_argv(["--", "hello"])

    assert context.argv == ["hello"]
    assert context.execution_surface == nil
  end

  test "parse_argv/1 builds ssh execution_surface from shared flags" do
    assert {:ok, context} =
             ExamplesSupport.parse_argv([
               "--cwd",
               "/srv/claude",
               "--danger-full-access",
               "--ssh-host",
               "builder@example.internal",
               "--ssh-port",
               "2222",
               "--ssh-identity-file",
               "./tmp/id_ed25519"
             ])

    assert %ExecutionSurface{} = context.execution_surface
    assert context.execution_surface.surface_kind == :ssh_exec
    assert context.execution_surface.transport_options[:destination] == "example.internal"
    assert context.execution_surface.transport_options[:ssh_user] == "builder"
    assert context.execution_surface.transport_options[:port] == 2222
    assert context.execution_surface.transport_options[:identity_file] =~ "/tmp/id_ed25519"
    assert context.example_cwd == "/srv/claude"
    assert context.example_danger_full_access == true
  end

  test "parse_argv/1 rejects orphan ssh flags without --ssh-host" do
    assert {:error, message} = ExamplesSupport.parse_argv(["--ssh-user", "builder"])
    assert message =~ "require --ssh-host"
  end

  test "parse_argv/1 rejects blank cwd values" do
    assert {:error, message} = ExamplesSupport.parse_argv(["--cwd", "   "])
    assert message =~ "--cwd"
  end

  test "with_execution_surface/1 injects the parsed surface into options structs" do
    assert {:ok, context} =
             ExamplesSupport.parse_argv([
               "--cwd",
               "/srv/claude",
               "--danger-full-access",
               "--ssh-host",
               "example.internal"
             ])

    Process.put({ExamplesSupport, :ssh_context}, context)

    opts =
      %ClaudeAgentSDK.Options{model: "haiku"}
      |> ExamplesSupport.with_execution_surface()

    assert opts.execution_surface.surface_kind == :ssh_exec
    assert opts.execution_surface.transport_options[:destination] == "example.internal"
    assert opts.cwd == "/srv/claude"
    assert opts.permission_mode == :bypass_permissions
  after
    Process.delete({ExamplesSupport, :ssh_context})
  end

  test "preflight_options/0 carries the shared SSH context into the auth probe" do
    assert {:ok, context} =
             ExamplesSupport.parse_argv([
               "--cwd",
               "/srv/claude",
               "--danger-full-access",
               "--ssh-host",
               "example.internal"
             ])

    Process.put({ExamplesSupport, :ssh_context}, context)

    opts = ExamplesSupport.preflight_options()

    assert opts.execution_surface.surface_kind == :ssh_exec
    assert opts.execution_surface.transport_options[:destination] == "example.internal"
    assert opts.cwd == "/srv/claude"
    assert opts.permission_mode == :bypass_permissions
    assert opts.max_turns == 1
    assert opts.output_format == :json
    assert opts.setting_sources == ["user"]
  after
    Process.delete({ExamplesSupport, :ssh_context})
  end

  test "preflight_timeout_seconds/0 defaults to 30 seconds for Anthropic" do
    restore = capture_env()

    on_exit(fn ->
      restore_env(restore)
    end)

    System.delete_env("CLAUDE_AGENT_PROVIDER_BACKEND")
    System.delete_env("CLAUDE_EXAMPLES_BACKEND")
    System.delete_env("ANTHROPIC_AUTH_TOKEN")
    System.delete_env("ANTHROPIC_BASE_URL")
    System.delete_env("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS")

    assert ExamplesSupport.preflight_timeout_seconds() == 30
    assert ExamplesSupport.preflight_timeout_ms() == 30_000
  end

  test "preflight_timeout_seconds/0 defaults to 60 seconds for Ollama" do
    restore = capture_env()

    on_exit(fn ->
      restore_env(restore)
    end)

    System.put_env("CLAUDE_AGENT_PROVIDER_BACKEND", "ollama")
    System.delete_env("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS")

    assert ExamplesSupport.preflight_timeout_seconds() == 60
    assert ExamplesSupport.preflight_timeout_ms() == 60_000
  end

  test "preflight_timeout_seconds/0 respects explicit environment overrides" do
    restore = capture_env()

    on_exit(fn ->
      restore_env(restore)
    end)

    System.put_env("CLAUDE_AGENT_PROVIDER_BACKEND", "ollama")
    System.put_env("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS", "75")

    assert ExamplesSupport.preflight_timeout_seconds() == 75
    assert ExamplesSupport.preflight_timeout_ms() == 75_000
  end

  test "preflight hints are backend-aware" do
    restore = capture_env()

    on_exit(fn ->
      restore_env(restore)
    end)

    System.put_env("CLAUDE_AGENT_PROVIDER_BACKEND", "ollama")

    assert ExamplesSupport.preflight_auth_hint() =~ "Ollama"
    assert ExamplesSupport.preflight_timeout_hint() =~ "Ollama"

    System.put_env("CLAUDE_AGENT_PROVIDER_BACKEND", "anthropic")

    assert ExamplesSupport.preflight_auth_hint() =~ "claude login"
    assert ExamplesSupport.preflight_timeout_hint() =~ "CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS"
  end

  defp capture_env do
    %{
      "CLAUDE_AGENT_PROVIDER_BACKEND" => System.get_env("CLAUDE_AGENT_PROVIDER_BACKEND"),
      "CLAUDE_EXAMPLES_BACKEND" => System.get_env("CLAUDE_EXAMPLES_BACKEND"),
      "ANTHROPIC_AUTH_TOKEN" => System.get_env("ANTHROPIC_AUTH_TOKEN"),
      "ANTHROPIC_BASE_URL" => System.get_env("ANTHROPIC_BASE_URL"),
      "CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS" =>
        System.get_env("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS")
    }
  end

  defp restore_env(env) when is_map(env) do
    Enum.each(env, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)
  end
end
