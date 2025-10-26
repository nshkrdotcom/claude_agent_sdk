# Streaming + Tools Long-Term Architecture

**Last updated:** 2025-10-25  
**Status:** Proposed roadmap

## 1. Goals
- Deliver character-level streaming (`--include-partial-messages`) while preserving tool execution, hooks, and MCP support.
- Unify transport stack so the SDK automatically chooses the correct control protocol capabilities.
- Keep backwards compatibility for low-latency, CLI-only streaming and existing client workflows.

## 2. Current Constraints
- `ClaudeAgentSDK.Streaming` shells out with streaming flags but never speaks control protocol; SDK MCP servers and hooks are therefore ignored.
- `ClaudeAgentSDK.Client` runs the control channel (initialize request, hook callbacks, SDK MCP routing) but omits `--include-partial-messages`, so no deltas flow through.
- `Options.to_args/1` filters SDK servers when building CLI flags, assuming the control client will manage them. That assumption breaks when the streaming module is used.

## 3. Target Architecture

```
                        ┌───────────────────────────┐
                        │ ClaudeAgentSDK.Streaming  │
                        │ (public API facade)       │
                        └──────────────┬────────────┘
                                       │
          ┌────────────────────────────┴────────────────────────────┐
          │                                                         │
┌─────────▼──────────┐                                     ┌────────▼──────────┐
│ Lightweight CLI    │                                     │ Control Client    │
│ Transport          │                                     │ (bidirectional)   │
│  - stream-json     │                                     │  - initialize     │
│  - no tools/hooks  │                                     │  - hooks + MCP    │
└─────────┬──────────┘                                     └────────┬──────────┘
          │                                                         │
          └───────── Heuristic Router ──────────────────────────────┘
                            │
                  `Transport.StreamingRouter`
```

### 3.1 Router Selection Logic
1. **Control Features Present:** If options include hooks, permission callbacks, SDK MCP servers, or runtime agent/permission overrides → use control client with streaming enabled.
2. **Explicit Flag:** Allow callers to force either path (e.g., `%Options{transport: :control}`) for testing or fail-safe behavior.
3. **Default:** Fall back to lightweight CLI mode for minimal overhead when none of the control features are required.

### 3.2 Control Client Enhancements
- Append `--include-partial-messages` when streaming is requested.
- Add `include_partial_messages` option + auto-enable for streaming router.
- Normalize partial events (`stream_event`) into the same shape as `Streaming.EventParser`.
- Multiplex message bus so `Client.stream_messages/1` yields both `ClaudeAgentSDK.Message` structs and `Streaming.Event` maps (tagged union).

### 3.3 Streaming Facade Enhancements
- Reuse control client when selected, wrapping its stream into the existing event-delivery contract (`%{type: ...}` maps).
- Maintain sequential message queue semantics and timeout handling so existing callers do not break.

## 4. Data Flow Changes

| Flow | Current | Target |
|------|---------|--------|
| Partial text | `Streaming.Session` emits `%{type: :text_delta}` | Control client emits same event via parser |
| Tool input deltas | Lost (never parsed) | `tool_input_delta` events surfaced to streaming consumers |
| Hook callbacks | Only via `Client` | Routed automatically when control client path active |
| MCP SDK tools | Unsupported during streaming | Routed via `handle_sdk_mcp_request/3` |

## 5. API Surface Adjustments
- `ClaudeAgentSDK.Options` gains `include_partial_messages` (boolean) and `preferred_transport` (`:auto | :cli | :control`).
- `ClaudeAgentSDK.Streaming.start_session/1` forwards the enriched options; callers opt into new behavior by default through the router.
- Documented return type becomes `Stream.t([Streaming.Event.t() | ClaudeAgentSDK.Message.t()])` when routed through control client.

## 6. Compatibility & Risks
- **Backward Compatibility:** Default router continues to choose CLI mode if no control features are configured, matching today’s behavior.
- **Performance:** Control client incurs additional latency (initialize handshake, JSON parsing). Mitigation: only used when necessary.
- **Complexity:** Unified stream now mixes event structs and messages. Provide helper utilities (`Streaming.normalize_events/1`) to ease adoption.
- **Testing:** Requires new integration coverage that exercises both transports with partials + tools to catch regressions.

## 7. Open Questions
- Should partial events be surfaced as dedicated structs (`%Streaming.Event{}`) instead of bare maps?
- Do we need backpressure or flow control when both CLI and control client streams emit high-frequency deltas?
- How should we expose error semantics (e.g., tool invocation failures mid-stream) to LiveView consumers?

## 8. Next Steps
1. Finalize router interface and option schema.
2. Prototype control client with partial message support.
3. Build end-to-end integration test (CLI + MCP server + streaming UI harness).
4. Update docs/examples to demonstrate both modes and migration path.
