defmodule ClaudeAgentSDK.ForbiddenTokensTest do
  use ExUnit.Case, async: true

  @project_root Path.expand("../..", __DIR__)
  @forbidden_tokens [
    "ExternalRuntimeTransport",
    "external_runtime_transport"
  ]
  @paths [
    "lib",
    "test",
    "guides",
    "README.md",
    "mix.exs",
    "mix.lock"
  ]

  test "repo contains no external runtime transport references" do
    Enum.each(expanded_files(), fn path ->
      if path != __ENV__.file do
        contents = File.read!(path)

        Enum.each(@forbidden_tokens, fn token ->
          refute contents =~ token,
                 "unexpected forbidden token #{inspect(token)} in #{Path.relative_to(path, @project_root)}"
        end)
      end
    end)
  end

  defp expanded_files do
    @paths
    |> Enum.flat_map(fn relative ->
      full_path = Path.join(@project_root, relative)

      cond do
        File.regular?(full_path) ->
          [full_path]

        File.dir?(full_path) ->
          Path.wildcard(Path.join(full_path, "**/*"))
          |> Enum.filter(&File.regular?/1)

        true ->
          []
      end
    end)
  end
end
