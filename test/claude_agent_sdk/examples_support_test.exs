defmodule ClaudeAgentSDK.ExamplesSupportTest do
  use ExUnit.Case, async: true

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
end
