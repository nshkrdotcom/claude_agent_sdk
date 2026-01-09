# Project Structure Research: Claude Agent SDK for Elixir

**Date:** 2025-12-29
**Document Purpose:** Comprehensive analysis of project structure, mix.exs configuration, and ex_doc setup with recommendations for improved documentation organization.

---

## 1. Project Overview

### Basic Information

| Field | Value |
|-------|-------|
| **Package Name** | `claude_agent_sdk` |
| **Current Version** | `0.6.10` |
| **Elixir Requirement** | `~> 1.14` |
| **GitHub Repository** | https://github.com/nshkrdotcom/claude_agent_sdk |
| **Hex.pm Package** | https://hex.pm/packages/claude_agent_sdk |
| **HexDocs** | https://hexdocs.pm/claude_agent_sdk |

### Package Description

> An Elixir SDK for Claude Code - Build AI-powered CLI tools with Claude

---

## 2. Mix.exs Analysis

### 2.1 Dependencies

```elixir
defp deps do
  [
    {:erlexec, "~> 2.0", runtime: runtime_erlexec?()},
    {:jason, "~> 1.4"},
    {:ex_doc, "~> 0.31", only: :dev, runtime: false},
    {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
    {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
    {:supertester, "~> 0.4.0", only: :test},
    {:stream_data, "~> 1.0", only: :test}
  ]
end
```

**Dependency Breakdown:**

| Dependency | Version | Purpose | Environment |
|------------|---------|---------|-------------|
| `erlexec` | ~> 2.0 | Subprocess management for Claude CLI | Conditional runtime |
| `jason` | ~> 1.4 | JSON encoding/decoding | Runtime |
| `ex_doc` | ~> 0.31 | Documentation generation | Dev only |
| `dialyxir` | ~> 1.0 | Static analysis (Dialyzer) | Dev only |
| `credo` | ~> 1.6 | Code linting | Dev/Test |
| `supertester` | ~> 0.4.0 | Test harness utilities | Test only |
| `stream_data` | ~> 1.0 | Property-based testing | Test only |

### 2.2 Package Configuration

```elixir
defp package do
  [
    name: "claude_agent_sdk",
    licenses: ["MIT"],
    links: %{
      "GitHub" => "https://github.com/nshkrdotcom/claude_agent_sdk",
      "Documentation" => "https://hexdocs.pm/claude_agent_sdk",
      "Claude Code" => "https://claude.ai/code"
    },
    maintainers: [{"NSHkr", "ZeroTrust@NSHkr.com"}],
    files: ~w(lib mix.exs README.md HOOKS_GUIDE.md LICENSE CHANGELOG.md
              .formatter.exs assets docs/design examples/hooks
              examples/runtime_control test/claude_agent_sdk/hooks)
  ]
end
```

**Files Included in Package:**
- `lib/` - Source code
- `mix.exs` - Project configuration
- `README.md` - Main documentation
- `HOOKS_GUIDE.md` - Hooks system guide
- `LICENSE` - MIT license
- `CHANGELOG.md` - Version history
- `.formatter.exs` - Code formatter config
- `assets/` - Logo and images
- `docs/design/` - Design documentation
- `examples/hooks/` - Hook examples
- `examples/runtime_control/` - Runtime control examples
- `test/claude_agent_sdk/hooks/` - Hook tests

---

## 3. ExDoc Configuration

### 3.1 Current Configuration

```elixir
defp docs do
  [
    main: "readme",
    name: "ClaudeAgentSDK",
    source_ref: "v#{@version}",
    source_url: "https://github.com/nshkrdotcom/claude_agent_sdk",
    homepage_url: "https://claude.ai/code",
    assets: %{"assets" => "assets"},
    logo: "assets/claude_agent_sdk.svg",
    extras: [
      "README.md",
      "HOOKS_GUIDE.md",
      "COMPREHENSIVE_MANUAL.md",
      "MOCKING.md",
      "CHANGELOG.md",
      "LICENSE"
    ],
    groups_for_extras: [
      Guides: ["README.md", "HOOKS_GUIDE.md"],
      Documentation: ["COMPREHENSIVE_MANUAL.md", "MOCKING.md"],
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
        ClaudeAgentSDK.Options,
        ClaudeAgentSDK.OptionBuilder
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
```

### 3.2 Custom JavaScript (Mermaid Support)

The project includes Mermaid.js integration for rendering diagrams:

```elixir
defp before_closing_head_tag(:html) do
  """
  <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
  <script>
    // Mermaid initialization and rendering logic
  </script>
  """
end
```

---

## 4. Directory Structure

### 4.1 Source Code (`lib/`)

```
lib/
├── claude_agent_sdk.ex              # Main API module
└── claude_agent_sdk/
    ├── abort_signal.ex
    ├── agent.ex
    ├── assistant_error.ex
    ├── auth/
    │   ├── provider.ex
    │   ├── providers/
    │   │   ├── anthropic.ex
    │   │   ├── bedrock.ex
    │   │   └── vertex.ex
    │   └── token_store.ex
    ├── auth_checker.ex
    ├── auth_manager.ex
    ├── cli.ex
    ├── client.ex
    ├── content_extractor.ex
    ├── control_protocol/
    │   └── protocol.ex
    ├── debug_mode.ex
    ├── errors.ex
    ├── hooks/
    │   ├── hooks.ex
    │   ├── matcher.ex
    │   ├── output.ex
    │   └── registry.ex
    ├── json.ex
    ├── message.ex
    ├── mock.ex
    ├── mock/
    │   └── process.ex
    ├── model.ex
    ├── option_builder.ex
    ├── options.ex
    ├── orchestrator.ex
    ├── permission.ex
    ├── permission/
    │   ├── context.ex
    │   └── result.ex
    ├── process.ex
    ├── query.ex
    ├── query/
    │   └── client_stream.ex
    ├── session.ex
    ├── session_store.ex
    ├── streaming.ex
    ├── streaming/
    │   ├── event_adapter.ex
    │   ├── event_parser.ex
    │   └── session.ex
    ├── tool.ex
    ├── tool/
    │   └── registry.ex
    └── transport/
        ├── agents_file.ex
        ├── erlexec.ex
        ├── port.ex
        └── streaming_router.ex

lib/mix/tasks/
├── claude.setup_token.ex
├── run.live.ex
├── showcase.ex
└── test.live.ex
```

**Module Count:** ~50 modules

### 4.2 Test Files (`test/`)

```
test/
├── test_helper.exs
├── tool_macro_debug.exs
├── claude_agent_sdk_test.exs
├── claude_agent_sdk/
│   ├── agent_test.exs
│   ├── auth_checker_test.exs
│   ├── auth_manager_test.exs
│   ├── cli_test.exs
│   ├── cli_version_test.exs
│   ├── client_*.exs (multiple client tests)
│   ├── content_extractor_test.exs
│   ├── control_protocol/
│   │   └── protocol_test.exs
│   ├── debug_mode_test.exs
│   ├── hooks/
│   │   ├── hooks_test.exs
│   │   ├── matcher_test.exs
│   │   ├── output_test.exs
│   │   └── registry_test.exs
│   ├── message_*.exs (multiple message tests)
│   ├── mock_test.exs
│   ├── model_test.exs
│   ├── option_builder_test.exs
│   ├── options_*.exs (multiple options tests)
│   ├── permission_test.exs
│   ├── process_*.exs (multiple process tests)
│   ├── sdk_mcp_*.exs (MCP integration tests)
│   ├── streaming/
│   │   ├── event_adapter_test.exs
│   │   ├── event_parser_test.exs
│   │   └── session_cwd_semantics_test.exs
│   ├── streaming_*.exs (streaming tests)
│   ├── tool/
│   │   ├── edge_cases_test.exs
│   │   └── registry_test.exs
│   ├── tool_test.exs
│   ├── transport/
│   │   ├── agents_file_test.exs
│   │   ├── env_parity_test.exs
│   │   ├── erlexec_transport_test.exs
│   │   ├── port_test.exs
│   │   ├── stderr_callback_test.exs
│   │   └── streaming_router_test.exs
│   └── user_option_test.exs
├── examples/
│   └── runtime_control_examples_test.exs
└── integration/
    ├── backward_compat_test.exs
    ├── custom_transport_test.exs
    ├── filesystem_agents_test.exs
    ├── live_smoke_test.exs
    └── model_switching_live_test.exs
```

**Test Count:** ~65 test files

### 4.3 Examples (`examples/`)

```
examples/
├── basic_example.exs
├── session_features_example.exs
├── sandbox_settings_live.exs
├── tools_and_betas_live.exs
├── assistant_error_live.exs
├── file_checkpointing_live.exs
├── filesystem_agents_live.exs
├── structured_output_live.exs
├── sdk_mcp_tools_live.exs
├── support/
│   └── example_helper.exs
├── advanced_features/
│   ├── agents_live.exs
│   ├── permissions_live.exs
│   └── sdk_mcp_live_demo.exs
├── hooks/
│   ├── basic_bash_blocking.exs
│   ├── complete_workflow.exs
│   ├── context_injection.exs
│   ├── file_policy_enforcement.exs
│   └── logging_and_audit.exs
├── runtime_control/
│   └── control_parity_live.exs
├── streaming_tools/
│   ├── basic_streaming_with_hooks.exs
│   ├── quick_demo.exs
│   └── sdk_mcp_streaming.exs
└── archive/
    ├── advanced_features/
    ├── mock_demos/
    ├── runtime_control/
    ├── streaming_tools/
    └── top_level/
```

### 4.4 Documentation (`docs/`)

```
docs/
├── CUSTOM_TRANSPORTS.md
├── HOOKS_QUICK_REFERENCE.md
├── RATE_LIMITING_BEST_PRACTICES.md
├── RUNTIME_CONTROL.md
├── design/
│   └── hooks_implementation.md
├── 20251007/    # Historical planning documents
├── 20251017/    # Gap analysis and implementation
├── 20251018/    # v0.5.0 completion plan
├── 20251025/    # Streaming with tools design
├── 20251026/    # Supertester refactoring
├── 20251111/    # Python/Elixir gap report
├── 20251129/    # Port sync and audit
├── 20251202/    # Gap analysis
├── 20251213/    # Python SDK porting
└── 20251226/    # Additional gap analysis
```

### 4.5 Root-Level Documentation Files

| File | Purpose | Lines |
|------|---------|-------|
| `README.md` | Main project documentation | ~720 |
| `HOOKS_GUIDE.md` | Comprehensive hooks guide | ~825 |
| `COMPREHENSIVE_MANUAL.md` | Full SDK manual | ~1960 |
| `MOCKING.md` | Testing/mocking guide | ~235 |
| `CHANGELOG.md` | Version history | ~870 |
| `LICENSE` | MIT license | - |
| `ARCHITECTURE.md` | Architecture overview | - |
| `CONTRIBUTING.md` | Contribution guidelines | - |
| `AGENTS.md` | Agent system documentation | - |
| `ERLEXEC.md` | Erlexec usage documentation | - |
| `LIVE_TESTING_INSTRUCTIONS.md` | Live testing guide | - |
| `LOGIN_DESIGN.md` | Login system design | - |
| `NAMING_CONVENTION.md` | Code naming conventions | - |
| `ELIXIR_SDK_COMPLETE_OVERVIEW.md` | Complete SDK overview | - |

---

## 5. Current groups_for_extras Analysis

### Current Structure

```elixir
groups_for_extras: [
  Guides: ["README.md", "HOOKS_GUIDE.md"],
  Documentation: ["COMPREHENSIVE_MANUAL.md", "MOCKING.md"],
  "Release Notes": ["CHANGELOG.md", "LICENSE"]
]
```

### Observations

1. **Limited Grouping**: Only 6 extras files are included
2. **Missing Content**: Many valuable docs files are not included:
   - `docs/RUNTIME_CONTROL.md`
   - `docs/CUSTOM_TRANSPORTS.md`
   - `docs/HOOKS_QUICK_REFERENCE.md`
   - `docs/RATE_LIMITING_BEST_PRACTICES.md`
   - `docs/design/hooks_implementation.md`
3. **No Examples Section**: Examples are not exposed in documentation
4. **Architecture Documentation Missing**: ARCHITECTURE.md not included

---

## 6. Recommendations for Improved ExDoc Structure

### 6.1 Proposed New extras List

```elixir
extras: [
  # Getting Started
  "README.md",

  # Core Guides
  "HOOKS_GUIDE.md",
  "docs/RUNTIME_CONTROL.md",
  "docs/CUSTOM_TRANSPORTS.md",

  # Reference Documentation
  "COMPREHENSIVE_MANUAL.md",
  "MOCKING.md",
  "docs/HOOKS_QUICK_REFERENCE.md",
  "docs/RATE_LIMITING_BEST_PRACTICES.md",

  # Architecture & Design
  "ARCHITECTURE.md",
  "docs/design/hooks_implementation.md",

  # Examples (new section)
  "examples/hooks/README.md": [title: "Hook Examples"],

  # Contributing & Development
  "CONTRIBUTING.md",
  "LIVE_TESTING_INSTRUCTIONS.md",

  # Release Information
  "CHANGELOG.md",
  "LICENSE"
]
```

### 6.2 Proposed New groups_for_extras

```elixir
groups_for_extras: [
  "Getting Started": [
    "README.md"
  ],
  "Core Guides": [
    "HOOKS_GUIDE.md",
    "docs/RUNTIME_CONTROL.md",
    "docs/CUSTOM_TRANSPORTS.md"
  ],
  Reference: [
    "COMPREHENSIVE_MANUAL.md",
    "MOCKING.md",
    "docs/HOOKS_QUICK_REFERENCE.md",
    "docs/RATE_LIMITING_BEST_PRACTICES.md"
  ],
  "Architecture & Design": [
    "ARCHITECTURE.md",
    "docs/design/hooks_implementation.md"
  ],
  "Contributing & Development": [
    "CONTRIBUTING.md",
    "LIVE_TESTING_INSTRUCTIONS.md"
  ],
  "Release Notes": [
    "CHANGELOG.md",
    "LICENSE"
  ]
]
```

### 6.3 Proposed Enhanced groups_for_modules

```elixir
groups_for_modules: [
  "Core API": [
    ClaudeAgentSDK,
    ClaudeAgentSDK.Client,
    ClaudeAgentSDK.Query,
    ClaudeAgentSDK.Orchestrator
  ],
  "Streaming & Sessions": [
    ClaudeAgentSDK.Streaming,
    ClaudeAgentSDK.Streaming.Session,
    ClaudeAgentSDK.Streaming.EventParser,
    ClaudeAgentSDK.Streaming.EventAdapter,
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
  "Hooks & Permissions": [
    ClaudeAgentSDK.Hooks,
    ClaudeAgentSDK.Hooks.Matcher,
    ClaudeAgentSDK.Hooks.Output,
    ClaudeAgentSDK.Hooks.Registry,
    ClaudeAgentSDK.Permission,
    ClaudeAgentSDK.Permission.Context,
    ClaudeAgentSDK.Permission.Result
  ],
  "Message & Content": [
    ClaudeAgentSDK.Message,
    ClaudeAgentSDK.ContentExtractor,
    ClaudeAgentSDK.AssistantError
  ],
  Configuration: [
    ClaudeAgentSDK.Options,
    ClaudeAgentSDK.OptionBuilder,
    ClaudeAgentSDK.Model,
    ClaudeAgentSDK.Agent
  ],
  "Tools & MCP": [
    ClaudeAgentSDK.Tool,
    ClaudeAgentSDK.Tool.Registry
  ],
  Transport: [
    ClaudeAgentSDK.Transport,
    ClaudeAgentSDK.Transport.Port,
    ClaudeAgentSDK.Transport.Erlexec,
    ClaudeAgentSDK.Transport.StreamingRouter,
    ClaudeAgentSDK.Transport.AgentsFile
  ],
  "Control Protocol": [
    ClaudeAgentSDK.ControlProtocol.Protocol
  ],
  "Testing & Mocking": [
    ClaudeAgentSDK.Mock,
    ClaudeAgentSDK.Mock.Process
  ],
  Utilities: [
    ClaudeAgentSDK.JSON,
    ClaudeAgentSDK.CLI,
    ClaudeAgentSDK.DebugMode,
    ClaudeAgentSDK.Process,
    ClaudeAgentSDK.AbortSignal,
    ClaudeAgentSDK.Errors
  ],
  "Mix Tasks": [
    Mix.Tasks.Claude.SetupToken,
    Mix.Tasks.Run.Live,
    Mix.Tasks.Test.Live,
    Mix.Tasks.Showcase
  ]
]
```

### 6.4 Additional ExDoc Enhancements

```elixir
defp docs do
  [
    main: "readme",
    name: "ClaudeAgentSDK",
    source_ref: "v#{@version}",
    source_url: "https://github.com/nshkrdotcom/claude_agent_sdk",
    homepage_url: "https://claude.ai/code",
    assets: %{"assets" => "assets"},
    logo: "assets/claude_agent_sdk.svg",

    # Add canonical URL for SEO
    canonical: "https://hexdocs.pm/claude_agent_sdk",

    # Add extra metadata
    extras: [...],  # As proposed above
    groups_for_extras: [...],  # As proposed above
    groups_for_modules: [...],  # As proposed above

    # Add API reference grouping
    api_reference: false,  # Modules grouped manually

    # Add nest_modules_by_prefix for cleaner sidebar
    nest_modules_by_prefix: [
      ClaudeAgentSDK.Auth,
      ClaudeAgentSDK.Hooks,
      ClaudeAgentSDK.Permission,
      ClaudeAgentSDK.Streaming,
      ClaudeAgentSDK.Tool,
      ClaudeAgentSDK.Transport,
      ClaudeAgentSDK.Query,
      ClaudeAgentSDK.Mock,
      ClaudeAgentSDK.ControlProtocol
    ],

    # Keep Mermaid support
    before_closing_head_tag: &before_closing_head_tag/1,
    before_closing_body_tag: &before_closing_body_tag/1
  ]
end
```

---

## 7. Summary

### Key Findings

1. **Version**: 0.6.10 (latest)
2. **Module Organization**: Well-structured with ~50 modules organized into clear namespaces
3. **Test Coverage**: Comprehensive with ~65 test files
4. **Documentation**: Extensive but fragmented across multiple locations
5. **ExDoc Config**: Functional but can be improved with more comprehensive extras

### Recommended Actions

1. **Expand extras**: Include more documentation files from `docs/` directory
2. **Reorganize groups_for_extras**: Create clearer categorization (Getting Started, Core Guides, Reference, etc.)
3. **Enhance groups_for_modules**: Add missing modules and refine groupings
4. **Add nest_modules_by_prefix**: Improve sidebar organization
5. **Create examples README**: Add a consolidated examples guide for inclusion in docs

### Files to Consider Adding to Hex Package

Current `files` list could be expanded to include:
- `docs/RUNTIME_CONTROL.md`
- `docs/CUSTOM_TRANSPORTS.md`
- `docs/HOOKS_QUICK_REFERENCE.md`
- More examples directories

---

*Generated: 2025-12-29*
