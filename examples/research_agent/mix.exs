example_repo_root = Path.expand("../..", __DIR__)

unless Code.ensure_loaded?(DependencySources) do
  Code.require_file(Path.join(example_repo_root, "build_support/dependency_sources.exs"))
end

defmodule ResearchAgent.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :research_agent,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Quality tools
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :underspecs]
      ],

      # Documentation
      name: "ResearchAgent",
      description: "Multi-agent research coordination example using Claude Agent SDK",
      source_url: "https://github.com/anthropics/claude-agent-sdk-elixir"
    ]
  end

  def application do
    [
      mod: {ResearchAgent.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependency - reference the SDK from parent directory
      claude_agent_sdk_dep(),

      # Testing
      {:mox, "~> 1.2", only: :test},

      # Development and quality tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      test: ["test"]
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
