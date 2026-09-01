if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule EmailAgent.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :email_agent,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl, :crypto],
      mod: {EmailAgent.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Claude Agent SDK from parent directory
      claude_agent_sdk_dep(),

      # IMAP client - using yustrianthe mail library which has IMAP support
      {:mail, "~> 0.3"},

      # SQLite database
      {:exqlite, "~> 0.23"},

      # Environment variable handling
      {:dotenvy, "~> 1.1.1"},

      # Development & Testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd mkdir -p priv"],
      "db.reset": ["cmd rm -f priv/emails.db", "run -e 'EmailAgent.Storage.init_db([])'"],
      test: ["test"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp claude_agent_sdk_dep do
    workspace_dep({:claude_agent_sdk, "~> 0.20.0"})
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, @repo_root]),
      else: committed
  end
end
