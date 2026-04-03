defmodule ClaudeAgentSdk.MixProject do
  use Mix.Project

  @app :claude_agent_sdk
  @version "0.16.0"
  @cli_subprocess_core_requirement "~> 0.1.0"
  @cli_subprocess_core_repo "nshkrdotcom/cli_subprocess_core"
  @source_url "https://github.com/nshkrdotcom/claude_agent_sdk"
  @homepage_url "https://hex.pm/packages/claude_agent_sdk"
  @docs_url "https://hexdocs.pm/claude_agent_sdk"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      homepage_url: @homepage_url,
      source_url: @source_url
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
    workspace_deps() ++
      [
        {:jason, "~> 1.4"},
        {:zoi, "~> 0.17"},
        {:ex_doc, "~> 0.40", only: :dev, runtime: false},
        {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:supertester, "~> 0.5.1", only: :test},
        {:stream_data, "~> 1.1", only: :test}
      ]
  end

  defp package do
    [
      name: "claude_agent_sdk",
      description: description(),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Hex" => @homepage_url,
        "HexDocs" => @docs_url,
        "Claude Code" => "https://claude.ai/code",
        "Examples" => "#{@source_url}/tree/main/examples",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"],
      files: ~w(
          lib
          guides
          examples/README.md
          examples/mix_task_chat/README.md
          examples/phoenix_chat/README.md
          examples/document_generation/README.md
          examples/research_agent/README.md
          examples/skill_invocation/README.md
          examples/email_agent/README.md
          assets/claude_agent_sdk.svg
          docs/RUNTIME_CONTROL.md
          mix.exs
          README.md
          LICENSE
          CHANGELOG.md
          .formatter.exs
        )
    ]
  end

  defp description do
    "An Elixir SDK for Claude Code - build AI-powered CLI tools with Claude."
  end

  defp docs do
    [
      main: "readme",
      name: "ClaudeAgentSDK",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @homepage_url,
      assets: %{"assets" => "assets"},
      logo: "assets/claude_agent_sdk.svg",
      extras: [
        {"README.md", title: "Overview", filename: "readme"},
        {"guides/getting-started.md", title: "Getting Started"},
        {"guides/streaming.md", title: "Streaming"},
        {"guides/hooks.md", title: "Hooks"},
        {"guides/mcp-tools.md", title: "MCP Tools"},
        {"guides/permissions.md", title: "Permissions"},
        {"guides/configuration.md", title: "Configuration"},
        {"guides/configuration-internals.md", title: "Configuration Internals"},
        {"guides/model-configuration.md", title: "Model Configuration"},
        {"guides/agents.md", title: "Agents"},
        {"guides/sessions.md", title: "Sessions"},
        {"docs/RUNTIME_CONTROL.md", title: "Runtime Control"},
        {"guides/testing.md", title: "Testing"},
        {"guides/error-handling.md", title: "Error Handling"},
        {"examples/README.md", title: "Examples", filename: "examples"},
        {"examples/mix_task_chat/README.md",
         title: "Mix Task Chat Example", filename: "mix-task-chat-example"},
        {"examples/phoenix_chat/README.md",
         title: "Phoenix Chat Example", filename: "phoenix-chat-example"},
        {"examples/document_generation/README.md",
         title: "Document Generation Example", filename: "document-generation-example"},
        {"examples/research_agent/README.md",
         title: "Research Agent Example", filename: "research-agent-example"},
        {"examples/skill_invocation/README.md",
         title: "Skill Invocation Example", filename: "skill-invocation-example"},
        {"examples/email_agent/README.md",
         title: "Email Agent Example", filename: "email-agent-example"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE", title: "License"}
      ],
      groups_for_extras: [
        "Project Overview": ["README.md"],
        Foundations: [
          "guides/getting-started.md",
          "guides/streaming.md",
          "guides/sessions.md"
        ],
        Tooling: [
          "guides/hooks.md",
          "guides/mcp-tools.md",
          "guides/permissions.md"
        ],
        "Models & Configuration": [
          "guides/configuration.md",
          "guides/configuration-internals.md",
          "guides/model-configuration.md",
          "guides/agents.md"
        ],
        Operations: [
          "docs/RUNTIME_CONTROL.md"
        ],
        Quality: [
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
        Reference: ["CHANGELOG.md", "LICENSE"]
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
          ClaudeAgentSDK.Runtime.CLI,
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
      plt_add_apps: [:mix],
      plt_core_path: "priv/plts/core",
      plt_local_path: "priv/plts",
      plt_ignore_apps: workspace_apps(),
      paths: [project_ebin_path() | workspace_dialyzer_paths()]
    ]
  end

  defp workspace_deps do
    Enum.map(workspace_dep_specs(), fn {app, path, requirement, opts} ->
      workspace_dep(app, path, requirement, opts)
    end)
  end

  defp workspace_dep_specs do
    [
      {:cli_subprocess_core, "../cli_subprocess_core", @cli_subprocess_core_requirement,
       github: @cli_subprocess_core_repo, branch: "main"}
    ]
  end

  defp workspace_apps do
    Enum.map(workspace_dep_specs(), &elem(&1, 0))
  end

  defp workspace_dialyzer_paths do
    Enum.map(workspace_apps(), fn app ->
      build_ebin_path(app)
    end)
  end

  defp project_ebin_path do
    build_ebin_path(@app)
  end

  defp build_ebin_path(app) when is_atom(app) do
    Path.join(["_build", Atom.to_string(Mix.env()), "lib", Atom.to_string(app), "ebin"])
  end

  defp workspace_dep(app, path, requirement, opts) do
    {release_opts, dep_opts} = Keyword.split(opts, [:github, :git, :branch, :tag, :ref])
    expanded_path = Path.expand(path, __DIR__)

    cond do
      hex_packaging?() ->
        {app, requirement, dep_opts}

      workspace_checkout?() and File.dir?(expanded_path) ->
        {app, Keyword.put(dep_opts, :path, path)}

      true ->
        {app, Keyword.merge(dep_opts, release_opts)}
    end
  end

  defp hex_packaging? do
    Enum.any?(System.argv(), &String.starts_with?(&1, "hex."))
  end

  defp workspace_checkout? do
    not Enum.member?(Path.split(Path.expand(__DIR__)), "deps")
  end
end
