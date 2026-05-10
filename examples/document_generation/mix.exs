example_repo_root = Path.expand("../..", __DIR__)

unless Code.ensure_loaded?(DependencySources) do
  Code.require_file(Path.join(example_repo_root, "build_support/dependency_sources.exs"))
end

defmodule DocumentGeneration.MixProject do
  use Mix.Project

  @repo_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :document_generation,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Excel generation
      {:elixlsx, "~> 0.6.0"},

      # Claude Agent SDK from parent directory
      claude_agent_sdk_dep(),

      # Development and testing
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix]
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
