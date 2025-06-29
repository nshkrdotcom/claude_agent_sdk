defmodule ClaudeCodeSdk.MixProject do
  use Mix.Project

  def project do
    [
      app: :claude_code_sdk,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An Elixir SDK for Claude Code",
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      preferred_cli_env: [
        "test.live": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:erlexec, "~> 2.0", runtime: runtime_erlexec?()},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/your-org/claude_code_sdk_elixir"}
    ]
  end

  defp docs do
    [
      main: "ClaudeCodeSDK",
      extras: ["README.md"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix]
    ]
  end

  # Runtime erlexec decision based on environment and live mode intent
  defp runtime_erlexec? do
    case Mix.env() do
      :test ->
        # In test env, only include erlexec at runtime if running live tests
        System.get_env("LIVE_TESTS") == "true"
      _ -> 
        true
    end
  end
end
