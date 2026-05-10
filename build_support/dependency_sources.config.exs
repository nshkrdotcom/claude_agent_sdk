%{
  deps: %{
    claude_agent_sdk: %{
      path: ".",
      github: %{repo: "nshkrdotcom/claude_agent_sdk", branch: "main"},
      hex: "~> 0.18.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    cli_subprocess_core: %{
      path: "../cli_subprocess_core",
      github: %{repo: "nshkrdotcom/cli_subprocess_core", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
