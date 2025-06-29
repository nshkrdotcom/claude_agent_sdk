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
      {:erlexec, "~> 2.0"},
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
end
