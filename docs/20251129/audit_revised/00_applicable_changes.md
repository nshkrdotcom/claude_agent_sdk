# Revised Gap List – Applicable Changes for the Elixir Port

## Scope

This consolidates the original Python audit into the gaps that still apply to the Elixir SDK after reviewing the codebase and addenda. Items marked as Python-only (assistant error parsing, auth provider stack) are excluded. The `set_user` control method remains a cross-SDK/CLI limitation and is noted separately.

## Applicable Changes

1) **Implement control cancel handling**
- **Current state:** The Elixir client handles `control_request` and `control_response` but never routes or acts on `control_cancel_request` messages (no references in `lib/claude_agent_sdk/`).
- **Impact:** Long-running hook/permission callbacks cannot be cancelled from the CLI; the SDK will ignore CLI-initiated cancellations.
- **Change needed:** Plumb cancellation through the control protocol, track pending requests, and propagate cancel to in-flight tasks (e.g., by exiting tasks or flagging contexts).

2) **Provide abort/cancel signals to callbacks**
- **Current state:** Hook and permission contexts reserve a `:signal` field (`lib/claude_agent_sdk/hooks/hooks.ex`, `lib/claude_agent_sdk/permission/context.ex`) but it is never populated or triggered.
- **Impact:** Callback implementations cannot cooperatively stop on user interrupt, session shutdown, or cancel; they only time out.
- **Change needed:** Introduce an abort signal (e.g., reference or cancellation token), attach it to contexts, and trigger it when control cancel/interrupt events arrive or the session closes.

3) **Broaden SDK MCP method routing**
- **Current state:** JSON-RPC routing for SDK MCP servers only supports `initialize`, `tools/list`, and `tools/call` (`lib/claude_agent_sdk/client.ex:1640-1707`).
- **Impact:** MCP capabilities beyond tools (resources, prompts, sampling, notifications) are unavailable until explicitly added; feature lag versus evolving MCP protocol.
- **Change needed:** Add Transport-like abstraction or extend routing to cover additional MCP methods, and log/return “method not found” for unknown calls to surface gaps.

4) **Support session/notification hooks**
- **Current state:** Supported hook events are limited to `:pre_tool_use | :post_tool_use | :user_prompt_submit | :stop | :subagent_stop | :pre_compact` (`lib/claude_agent_sdk/hooks/hooks.ex`). SessionStart, SessionEnd, and Notification hooks are explicitly unsupported.
- **Impact:** Cannot run setup/cleanup logic or custom notification handling in the Elixir SDK even though the CLI hook system supports these events.
- **Change needed:** Add hook event plumbing (registration, dispatch, callback payloads) for SessionStart, SessionEnd, and Notification, or document and expose a clear fallback.

## Cross-SDK / CLI-Dependent

- **Runtime user switching (`set_user` control subtype):** Neither SDK nor the CLI in this repo implements a `set_user` control message; `Options.user` is only applied at process spawn. Enabling runtime switches would require CLI protocol support plus client wiring in both SDKs.
