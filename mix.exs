defmodule ClaudeCodeSdk.MixProject do
  use Mix.Project

  @version "0.0.1"

  def project do
    [
      app: :claude_code_sdk,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An Elixir SDK for Claude Code - Build AI-powered CLI tools with Claude",
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      preferred_cli_env: [
        "test.live": :test,
        "run.live": :dev
      ],
      source_url: "https://github.com/nshkrdotcom/claude_code_sdk_elixir"
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
      name: "claude_code_sdk",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/claude_code_sdk_elixir",
        "Documentation" => "https://hexdocs.pm/claude_code_sdk",
        "Claude Code" => "https://claude.ai/code"
      },
      maintainers: [{"NSHkr", "ZeroTrust@NSHkr.com"}],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "ClaudeCodeSDK",
      extras: ["README.md", "CHANGELOG.md", "LICENSE", "COMPREHENSIVE_MANUAL.md", "MOCKING.md"],
      source_ref: "v#{@version}",
      source_url: "https://github.com/nshkrdotcom/claude_code_sdk_elixir",
      homepage_url: "https://claude.ai/code",
      before_closing_head_tag: &before_closing_head_tag/1,
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_head_tag(:epub), do: ""

  defp before_closing_body_tag(:html), do: ""

  defp before_closing_body_tag(:epub), do: ""

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
