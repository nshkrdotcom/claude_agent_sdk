example_repo_root = Path.expand("../..", __DIR__)

unless Code.ensure_loaded?(DependencySources) do
  Code.require_file(Path.join(example_repo_root, "build_support/dependency_sources.exs"))
end

defmodule MixTaskChat.MixProject do
  use Mix.Project

  @repo_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :mix_task_chat,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Reference the SDK from parent directory
      claude_agent_sdk_dep()
    ]
  end

  defp claude_agent_sdk_dep do
    case DependencySources.dep(:claude_agent_sdk, @repo_root) do
      {:claude_agent_sdk, opts} when is_list(opts) ->
        if Keyword.has_key?(opts, :path) do
          {:claude_agent_sdk, Keyword.put(opts, :path, "../..")}
        else
          {:claude_agent_sdk, opts}
        end

      dep ->
        dep
    end
  end
end
