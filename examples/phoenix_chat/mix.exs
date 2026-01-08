defmodule PhoenixChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_chat,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def application do
    [
      mod: {PhoenixChat.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Reference the SDK from parent directory
      {:claude_agent_sdk, path: "../.."},
      # Phoenix framework
      {:phoenix, "~> 1.7.17"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      # HTTP server
      {:plug_cowboy, "~> 2.7"},
      # JSON parsing (already in SDK deps)
      {:jason, "~> 1.4"},
      # Telemetry
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      # Development & Testing
      {:floki, "~> 0.36", only: :test},
      {:lazy_html, "~> 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
