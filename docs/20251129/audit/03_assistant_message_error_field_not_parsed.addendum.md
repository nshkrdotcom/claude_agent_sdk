# Addendum - Assistant Message Error Field Not Parsed

- **Elixir port already parses assistant errors.** `ClaudeAgentSDK.Message` extracts the optional `error` field and normalizes it via `AssistantError.cast/1`, so callers see `:authentication_failed | :billing_error | :rate_limit | :invalid_request | :server_error | :unknown` when the CLI surfaces an error (`lib/claude_agent_sdk/message.ex:139-285`, `lib/claude_agent_sdk/assistant_error.ex:1-39`).
- **Impact on port comparison:** This gap is Python-only; the Elixir SDK is already at parity for assistant error propagation. No Elixir work is needed beyond keeping docs aligned.
