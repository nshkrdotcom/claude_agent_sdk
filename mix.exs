defmodule ClaudeAgentSdk.MixProject do
  use Mix.Project

  @version "0.14.0"

  def project do
    [
      app: :claude_agent_sdk,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An Elixir SDK for Claude Code - Build AI-powered CLI tools with Claude",
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      source_url: "https://github.com/nshkrdotcom/claude_agent_sdk"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.live": :test,
        "run.live": :dev
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:erlexec, "~> 2.0", runtime: runtime_erlexec?()},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:supertester, "~> 0.5.1", only: :test},
      {:stream_data, "~> 1.0", only: :test}
    ]
  end

  defp package do
    [
      name: "claude_agent_sdk",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/claude_agent_sdk",
        "Claude Code" => "https://claude.ai/code",
        "Examples" => "https://github.com/nshkrdotcom/claude_agent_sdk/tree/main/examples"
      },
      maintainers: [{"NSHkr", "ZeroTrust@NSHkr.com"}],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "ClaudeAgentSDK",
      source_ref: "v#{@version}",
      source_url: "https://github.com/nshkrdotcom/claude_agent_sdk",
      homepage_url: "https://hex.pm/packages/claude_agent_sdk",
      assets: %{"assets" => "assets"},
      logo: "assets/claude_agent_sdk.svg",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/streaming.md",
        "guides/hooks.md",
        "guides/mcp-tools.md",
        "guides/permissions.md",
        "guides/configuration.md",
        "guides/configuration-internals.md",
        "guides/model-configuration.md",
        "guides/agents.md",
        "guides/sessions.md",
        "guides/testing.md",
        "guides/error-handling.md",
        {"examples/README.md", filename: "examples"},
        {"examples/mix_task_chat/README.md", filename: "mix-task-chat-example"},
        {"examples/phoenix_chat/README.md", filename: "phoenix-chat-example"},
        {"examples/document_generation/README.md", filename: "document-generation-example"},
        {"examples/research_agent/README.md", filename: "research-agent-example"},
        {"examples/skill_invocation/README.md", filename: "skill-invocation-example"},
        {"examples/email_agent/README.md", filename: "email-agent-example"},
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        "Getting Started": [
          "README.md",
          "guides/getting-started.md"
        ],
        "Core Guides": [
          "guides/streaming.md",
          "guides/hooks.md",
          "guides/mcp-tools.md",
          "guides/permissions.md"
        ],
        "Advanced Topics": [
          "guides/configuration.md",
          "guides/configuration-internals.md",
          "guides/model-configuration.md",
          "guides/agents.md",
          "guides/sessions.md"
        ],
        "Testing & Errors": [
          "guides/testing.md",
          "guides/error-handling.md"
        ],
        Examples: [
          "examples/README.md",
          "examples/mix_task_chat/README.md",
          "examples/phoenix_chat/README.md",
          "examples/document_generation/README.md",
          "examples/research_agent/README.md",
          "examples/skill_invocation/README.md",
          "examples/email_agent/README.md"
        ],
        "Release Notes": ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        "Core API": [
          ClaudeAgentSDK,
          ClaudeAgentSDK.Client,
          ClaudeAgentSDK.Orchestrator,
          ClaudeAgentSDK.Query
        ],
        Session: [
          ClaudeAgentSDK.Session,
          ClaudeAgentSDK.SessionStore
        ],
        Authentication: [
          ClaudeAgentSDK.AuthManager,
          ClaudeAgentSDK.AuthChecker,
          ClaudeAgentSDK.Auth.TokenStore,
          ClaudeAgentSDK.Auth.Provider,
          ClaudeAgentSDK.Auth.Providers.Anthropic,
          ClaudeAgentSDK.Auth.Providers.Vertex,
          ClaudeAgentSDK.Auth.Providers.Bedrock
        ],
        Streaming: [
          ClaudeAgentSDK.Streaming,
          ClaudeAgentSDK.Streaming.Session,
          ClaudeAgentSDK.Streaming.EventParser
        ],
        "Message Handling": [
          ClaudeAgentSDK.Message,
          ClaudeAgentSDK.ContentExtractor
        ],
        Configuration: [
          ClaudeAgentSDK.Config,
          ClaudeAgentSDK.Config.Timeouts,
          ClaudeAgentSDK.Config.Buffers,
          ClaudeAgentSDK.Config.Auth,
          ClaudeAgentSDK.Config.CLI,
          ClaudeAgentSDK.Config.Env,
          ClaudeAgentSDK.Config.Orchestration,
          ClaudeAgentSDK.Options,
          ClaudeAgentSDK.OptionBuilder,
          ClaudeAgentSDK.Model
        ],
        Testing: [
          ClaudeAgentSDK.Mock,
          ClaudeAgentSDK.Mock.Process
        ],
        Hooks: [
          ClaudeAgentSDK.Hooks,
          ClaudeAgentSDK.Hooks.Matcher,
          ClaudeAgentSDK.Hooks.Output,
          ClaudeAgentSDK.Hooks.Registry
        ],
        "Control Protocol": [
          ClaudeAgentSDK.ControlProtocol.Protocol
        ],
        Utilities: [
          ClaudeAgentSDK.JSON,
          ClaudeAgentSDK.DebugMode,
          ClaudeAgentSDK.Process
        ],
        "Mix Tasks": [
          Mix.Tasks.Claude.SetupToken,
          Mix.Tasks.Run.Live,
          Mix.Tasks.Test.Live,
          Mix.Tasks.Showcase
        ]
      ],
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
