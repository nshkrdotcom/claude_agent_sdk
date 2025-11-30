# Addendum - Authentication Fully Delegated to CLI

- **Elixir port ships an auth provider stack.** The Elixir SDK has a full `AuthManager` with token acquisition/refresh and multi-provider support (`lib/claude_agent_sdk/auth_manager.ex:1-152`) plus provider adapters for Anthropic, Bedrock, and Vertex (`lib/claude_agent_sdk/auth/providers/*.ex`). It also persists tokens via `Auth.TokenStore`.
- **Impact on port comparison:** Unlike Python, authentication is not fully delegated to environment variables; the Elixir SDK already offers explicit auth flows and validation. Treat this as an upstream Python gap only—no Elixir parity work required.
