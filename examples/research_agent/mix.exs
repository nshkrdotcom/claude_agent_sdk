if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule ResearchAgent.MixProject do
  use Mix.Project

  @version "0.1.0"

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
    workspace_dep({:claude_agent_sdk, "~> 0.20.0"})
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
