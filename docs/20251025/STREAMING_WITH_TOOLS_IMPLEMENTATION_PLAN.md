# Streaming + Tools Implementation Plan

**Last updated:** 2025-10-25  
**Status:** Draft execution plan

## Milestone Overview
| Milestone | Focus | Duration | Exit Criteria |
|-----------|-------|----------|----------------|
| M1 | Option schema + transport router | 3d | Tests cover router selection logic |
| M2 | Control client partial streaming | 5d | CLI emits deltas + tools functional |
| M3 | Unified streaming facade | 4d | `Streaming.send_message/2` auto-routes |
| M4 | Documentation + migration | 2d | README + examples updated |

## M1 – Option Schema & Router
1. **Schema Updates**
   - Add `include_partial_messages :: boolean()` (default `false`) and `preferred_transport :: :auto | :cli | :control` to `ClaudeAgentSDK.Options`.
   - Ensure `OptionBuilder` presets set these fields sensibly (dev = `:auto`, prod = `:auto`).
2. **Router Module**
   - Create `ClaudeAgentSDK.Transport.StreamingRouter`.
   - Public function: `select(options, message)` returning `{:cli, normalized_options}` or `{:control, normalized_options}`.
   - Encoding logic: detect hooks, `can_use_tool`, SDK MCP servers, runtime agent/mode overrides.
3. **Testing**
   - Unit tests in `test/claude_agent_sdk/transport/streaming_router_test.exs`.
   - Cover edge cases (explicit override, mixed MCP servers, nil options).

## M2 – Control Client Partial Streaming
1. **Command Invocation**
   - Update `Client.build_cli_command/1` to append `--include-partial-messages` when streaming requested (via option or router flag).
   - Respect new `include_partial_messages` option in addition to router decisions.
2. **Event Parsing**
   - When decoding `sdk_message`, detect `"type": "stream_event"` and forward raw payload to `Streaming.EventParser.parse_event/2`.
   - Extend subscriber broadcast to send `%Streaming.Event{}` alongside existing `ClaudeAgentSDK.Message`.
   - Introduce internal struct (`%Streaming.Event{type: atom(), payload: map()}`) for type safety.
3. **API Adjustments**
   - Document that `Client.stream_messages/1` now emits tagged tuples (e.g., `{:event, event}` vs `{:message, msg}`) to preserve compatibility.
4. **Testing**
   - Expand mock transport to simulate stream-event frames.
   - Add integration spec verifying that tool requests still function while partial deltas flow.

## M3 – Unified Streaming Facade
1. **Session Startup**
   - Refactor `Streaming.Session.start_link/1` to delegate to router.
   - For control path: start `Client`, wrap `Client.stream_messages/1` into existing Stream.resource contract (respect queueing/timeouts).
   - For CLI path: retain current behavior.
2. **Event Normalization**
   - Provide helper `Streaming.Event.normalize/1` to ensure consumer-facing shape matches historical `%{type: :text_delta, ...}` maps.
   - Bridge between `%Streaming.Event{}` and map format when broadcasting from control client.
3. **Tool + Hook Support**
   - On control path, ensure `send_message/2` triggers hook invocation and SDK MCP routing without regression.
4. **Testing**
   - Integration test covering streaming + tool call: user prompt triggers tool, partial tool input deltas visible, final result emitted.
   - Live demo script under `examples/` to validate CLI experience.

## M4 – Documentation & Migration
1. **Docs**
   - Update README streaming section with control-aware behavior note.
   - Add new LiveView example showing partial updates + tool output.
   - Document router configuration in `docs/`.
2. **Examples**
   - Refresh `examples/advanced_features/mcp_*` scripts to use streaming.
   - Provide simple UI snippet demonstrating mixed event types.
3. **Migration Notes**
   - Draft `docs/20251025/STREAMING_WITH_TOOLS_MIGRATION.md` (see companion doc).
4. **Validation**
   - Run full validation suite: `mix format`, `mix credo --strict`, `mix dialyzer`, `mix test`, plus new integration tag.

## Risk Mitigation
- **CLI Compatibility:** Guard new flags behind version detection (`claude --version` probe) or provide fallbacks for older CLIs.
- **API Breakage:** Deliver transitional helpers (`Streaming.Event.stream_only/1`) so existing `Enum.filter(& &1.type == :text_delta)` code continues to work.
- **Performance Regression:** Benchmark both transports; capture metrics before/after and note in docs.

## Deliverables Checklist
- [ ] Router module + tests
- [ ] Options struct + builder updates
- [ ] Control client streaming support
- [ ] Unified streaming session logic
- [ ] Updated examples & docs
- [ ] Migration guide + release notes draft
