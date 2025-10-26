# Migration Guide: Streaming with Tools

**Audience:** Application developers embedding ClaudeAgentSDK streaming into interactive UIs.  
**Last updated:** 2025-10-25  
**Status:** Draft – aligns with proposed architecture & plan.

## 1. Summary
Upcoming releases will allow partial-response streaming and tool execution simultaneously. This guide outlines how to adopt the unified transport model without regressing existing behavior.

## 2. Key Changes
- `ClaudeAgentSDK.Streaming` will internally decide between CLI-only and control-enabled transports via a router.
- `Client.stream_messages/1` begins emitting partial events (text/tool/thinking deltas) in addition to full message structs.
- `ClaudeAgentSDK.Options` expands with:
  - `include_partial_messages` (boolean)
  - `preferred_transport` (`:auto | :cli | :control`)
- Helper utilities will be provided to normalize the mixed stream output.

## 3. Migration Steps

### Step 1 – Audit Usage
- Identify every call to `ClaudeAgentSDK.Streaming.*` and `Client.stream_messages/1`.
- Note whether the call expects only `%ClaudeAgentSDK.Message{}` structs or already works with raw maps.
- Flag any custom MCP server or hook usage; these will automatically switch to the control transport.

### Step 2 – Update Option Construction
- Add defaults for the new fields (most apps can rely on `%Options{preferred_transport: :auto}`).
- If you require guaranteed CLI-only behavior (e.g., to minimize latency), set `preferred_transport: :cli` temporarily.
- Enable `include_partial_messages: true` to opt in early once CLI support verified.

### Step 3 – Handle Mixed Stream Payloads
- Replace pattern matches like `Stream.filter(&(&1.type == :assistant))` with a helper:
  ```elixir
  ClaudeAgentSDK.Streaming.Event.consume(stream, fn
    {:event, %{type: :text_delta, text: text}} -> update_ui(text)
    {:message, %Message{type: :assistant} = msg} -> handle_completion(msg)
  end)
  ```
- For legacy code, provide adapter:
  ```elixir
  stream
  |> ClaudeAgentSDK.Streaming.Event.messages_only()
  |> Enum.each(&process_message/1)
  ```

### Step 4 – Test Tool Flows Under Streaming
- Execute integration suites with `mix test --include integration`.
- Confirm partial tool input appears via `tool_input_delta` events.
- Verify hooks (`pre_tool_use`, permissions) still fire and their decision outcomes propagate.

### Step 5 – Update UI/UX
- LiveView or Phoenix Channel consumers should append deltas immediately but also handle `:message_stop` to finalize text.
- Display tool progress (e.g., show spinner while `tool_use_start` event active).

## 4. Rollout Strategy
- **Phase 0 (opt-in beta):** Behind feature flag `preferred_transport: :control`. Documented for early adopters.
- **Phase 1 (default-on for control features):** Router auto-selects control transport when hooks/MCP are configured.
- **Phase 2 (full rollout):** Streaming facade always capable; CLI fallback remains for bare-bones scenarios.

## 5. Validation Checklist
- [ ] Integration test: streaming + SDK MCP tool call.
- [ ] Live UI smoke test (typewriter + tool responses).
- [ ] Hooks verification (allow/deny decisions recorded).
- [ ] Regression test for CLI-only streaming (no control features).
- [ ] Performance benchmarks before/after (latency, CPU).

## 6. Communication Plan
- Publish release notes summarizing behavior change and configuration knobs.
- Update `README`, `examples/advanced_features`, and demo scripts.
- Notify SDK consumers via CHANGELOG and internal channels.

## 7. Fallback / Rollback
- To revert quickly, set `preferred_transport: :cli` in application config.
- Disable `include_partial_messages` to restore legacy message-only stream if CLI issues arise.
- Maintain feature flag in configuration until confidence achieved.

## 8. Support & FAQs
- **Q:** Do I need to rewrite my streams?  
  **A:** Minimal changes—wrap with helper adapters if you only care about final assistant messages.

- **Q:** What happens on older Claude CLI versions?  
  **A:** Router detects capability; if the CLI rejects `--include-partial-messages`, we fall back to CLI-only streaming and log a warning.

- **Q:** Can I still run MCP tools without streaming?  
  **A:** Yes. Set `include_partial_messages: false` while keeping `preferred_transport: :control`.
