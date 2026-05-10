defmodule ClaudeAgentSDK.ExamplesSupportTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.ExamplesSupport
  alias ClaudeAgentSDK.Options
  alias CliSubprocessCore.Command
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

  test "preflight argv with explicit empty system prompt is accepted by command lane" do
    args = Options.to_args(ExamplesSupport.preflight_options())

    assert flag_with_value?(args, "--system-prompt", "")

    invocation = Command.new("/bin/sh", ["-c", "printf ok", "preflight" | args])

    assert {:ok, result} = Command.run(invocation, timeout: 1_000)
    assert result.stdout == "ok"
  end

  test "preflight options ignore Mix test warning flags" do
    assert {:ok, context} = ExamplesSupport.parse_argv(["--warnings-as-errors"])
    assert context.argv == []

    Process.put({ExamplesSupport, :ssh_context}, context)

    args = Options.to_args(ExamplesSupport.preflight_options())

    assert flag_with_value?(args, "--system-prompt", "")
  after
    Process.delete({ExamplesSupport, :ssh_context})
  end

  test "preflight_timeout_seconds/0 defaults to 30 seconds for Anthropic" do
    restore = capture_env()

    on_exit(fn ->
      restore_env(restore)
    end)

    ClaudeAgentSDK.Env.delete("CLAUDE_AGENT_PROVIDER_BACKEND")
    ClaudeAgentSDK.Env.delete("CLAUDE_EXAMPLES_BACKEND")
    ClaudeAgentSDK.Env.delete("ANTHROPIC_AUTH_TOKEN")
    ClaudeAgentSDK.Env.delete("ANTHROPIC_BASE_URL")
    ClaudeAgentSDK.Env.delete("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS")

    assert ExamplesSupport.preflight_timeout_seconds() == 30
    assert ExamplesSupport.preflight_timeout_ms() == 30_000
  end

  test "preflight_timeout_seconds/0 defaults to 60 seconds for Ollama" do
    restore = capture_env()

    on_exit(fn ->
      restore_env(restore)
    end)

    ClaudeAgentSDK.Env.put("CLAUDE_AGENT_PROVIDER_BACKEND", "ollama")
    ClaudeAgentSDK.Env.delete("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS")

    assert ExamplesSupport.preflight_timeout_seconds() == 60
    assert ExamplesSupport.preflight_timeout_ms() == 60_000
  end

  test "preflight_timeout_seconds/0 respects explicit environment overrides" do
    restore = capture_env()

    on_exit(fn ->
      restore_env(restore)
    end)

    ClaudeAgentSDK.Env.put("CLAUDE_AGENT_PROVIDER_BACKEND", "ollama")
    ClaudeAgentSDK.Env.put("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS", "75")

    assert ExamplesSupport.preflight_timeout_seconds() == 75
    assert ExamplesSupport.preflight_timeout_ms() == 75_000
  end

  test "preflight hints are backend-aware" do
    restore = capture_env()

    on_exit(fn ->
      restore_env(restore)
    end)

    ClaudeAgentSDK.Env.put("CLAUDE_AGENT_PROVIDER_BACKEND", "ollama")

    assert ExamplesSupport.preflight_auth_hint() =~ "Ollama"
    assert ExamplesSupport.preflight_timeout_hint() =~ "Ollama"

    ClaudeAgentSDK.Env.put("CLAUDE_AGENT_PROVIDER_BACKEND", "anthropic")

    assert ExamplesSupport.preflight_auth_hint() =~ "claude login"
    assert ExamplesSupport.preflight_timeout_hint() =~ "CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS"
  end

  defp capture_env do
    %{
      "CLAUDE_AGENT_PROVIDER_BACKEND" => ClaudeAgentSDK.Env.get("CLAUDE_AGENT_PROVIDER_BACKEND"),
      "CLAUDE_EXAMPLES_BACKEND" => ClaudeAgentSDK.Env.get("CLAUDE_EXAMPLES_BACKEND"),
      "ANTHROPIC_AUTH_TOKEN" => ClaudeAgentSDK.Env.get("ANTHROPIC_AUTH_TOKEN"),
      "ANTHROPIC_BASE_URL" => ClaudeAgentSDK.Env.get("ANTHROPIC_BASE_URL"),
      "CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS" =>
        ClaudeAgentSDK.Env.get("CLAUDE_EXAMPLES_PREFLIGHT_TIMEOUT_SECONDS")
    }
  end

  defp restore_env(env) when is_map(env) do
    Enum.each(env, fn
      {key, nil} -> ClaudeAgentSDK.Env.delete(key)
      {key, value} -> ClaudeAgentSDK.Env.put(key, value)
    end)
  end

  defp flag_with_value?(args, flag, expected) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [candidate, value] -> candidate == flag and value == expected end)
  end
end
