# Migrating to 0.20

Claude Agent SDK 0.20 moves its shared CLI runtime requirement to
`cli_subprocess_core ~> 0.7.0`. This makes the SDK resolvable with
`agent_session_manager 0.14` and the current Execution Plane component line.

Update the dependency and remove any override that pins an older Core release:

```elixir
{:claude_agent_sdk, "~> 0.20.0"}
```

The Claude-native public API is unchanged by this dependency migration. Source
checkouts may continue to use the sibling Core path selected by the repository's
dependency-source registry. Published packages use only the Hex requirement
declared in `mix.exs`; build-support tooling is intentionally not shipped.
