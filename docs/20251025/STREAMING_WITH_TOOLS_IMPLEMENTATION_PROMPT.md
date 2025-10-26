# Streaming + Tools Transport Unification Prompt

**Date**: 2025-10-25  
**Status**: Ready to start  
**Estimated Effort**: 14 developer-days (two-week iteration)  
**Dependencies**: Claude CLI ≥ v2.0 with `--include-partial-messages`; docs in `docs/20251025/STREAMING_WITH_TOOLS_ARCHITECTURE.md`

---

## CONTEXT

### System Architecture
- **SDK Layers**: Public API (`lib/claude_agent_sdk.ex`) dispatches to `Query`, `Streaming`, and `Client`.  
- **Transports**:  
  - `ClaudeAgentSDK.Streaming.Session` spawns the CLI with `--include-partial-messages`, streams stdout events, but never initializes the control protocol.  
  - `ClaudeAgentSDK.Client` opens a port, sends the control-protocol initialize request, manages hooks, permissions, and SDK MCP servers, but currently omits the partial-stream flag.  
- **Options Handling**: `ClaudeAgentSDK.Options.to_args/1` builds CLI arguments; SDK MCP servers with `%{type: :sdk, ...}` are stripped because the control client owns them.  
- **Event Parsing**: `ClaudeAgentSDK.Streaming.EventParser` converts stream-json payloads into maps with `:text_delta`, `:tool_input_delta`, etc. `Client` currently emits `ClaudeAgentSDK.Message` structs only.

### Key Invariants
- `mix compile --warnings-as-errors`, `mix credo --strict`, `mix dialyzer`, and `mix test` must all pass.  
- SDK MCP hooks, permission callbacks, and `Client.stream_messages/1` semantics remain backwards compatible.  
- Streaming consumers continue to receive `%{type: :text_delta, ...}` maps even after control routing.  
- No regressions to CLI-only streaming latency when no hooks/MCP are configured.  
- Tool execution (SDK MCP) continues to work under both transports.

### Related Systems
- `lib/claude_agent_sdk/options.ex` – argument generation affects every CLI invocation.  
- `lib/claude_agent_sdk/control_protocol/protocol.ex` – initialization and request routing.  
- `lib/claude_agent_sdk/tool/registry.ex` and associated tests – SDK MCP execution path.  
- README streaming docs and examples (LiveView integration).  
- Tests under `test/claude_agent_sdk/client_*`, `test/claude_agent_sdk/sdk_mcp_*`, and `test/claude_agent_sdk/transport/`.

### Current State Analysis

#### Example 1: Streaming Session lacks control protocol
`lib/claude_agent_sdk/streaming/session.ex:445-461`
```elixir
defp build_streaming_args(%Options{} = options) do
  base_args = [
    "--print",
    "--input-format",
    "stream-json",
    "--output-format",
    "stream-json",
    "--include-partial-messages",
    "--verbose"
  ]

  user_args = Options.to_args(options)
  user_args = Enum.reject(user_args, &(&1 == "--verbose"))

  base_args ++ user_args
end
```
*Issue*: appends streaming flags but never registers hooks or SDK MCP servers, so tool calls and permission prompts are ignored.

#### Example 2: Control client never enables partial messages
`lib/claude_agent_sdk/client.ex:801-809`
```elixir
defp build_cli_command(options) do
  executable = System.find_executable("claude")

  if executable do
    args = ["--output-format", "stream-json", "--input-format", "stream-json", "--verbose"]
    args = args ++ Options.to_args(options)
    cmd = Enum.join([executable | args], " ") <> " 2>/dev/null"
    {:ok, cmd}
  else
    {:error, :claude_not_found}
  end
end
```
*Issue*: lacks `--include-partial-messages`; downstream `Client.stream_messages/1` consumers never see deltas.

---

## REQUIRED READING

### Documentation (read first)
1. **Streaming + Tools Architecture Proposal**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/docs/20251025/STREAMING_WITH_TOOLS_ARCHITECTURE.md`  
   - Purpose: Target architecture, router design, compatibility risks.  
   - Focus: Sections 3–5 (router logic, data flow changes, API surface).

2. **Historical Streaming Plan**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/docs/20251007/06_BIDIRECTIONAL_STREAMING_PLAN.md`  
   - Purpose: Original streaming requirements and CLI flag usage.  
   - Focus: Implementation section (“StreamingSession Module”) and Testing notes.

3. **Gap Analysis – Architecture Differences**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/docs/20251017/gap_analysis/architecture_differences.md`  
   - Purpose: Comparison between Python and Elixir clients; highlights control protocol needs.  
   - Focus: Sections on concurrency model and transport layer.

4. **SDK MCP Integration Status**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/docs/SDK_MCP_STATUS.md`  
   - Purpose: Current MCP capabilities and limitations when streaming.  
   - Focus: Sections on server creation and outstanding issues.

### Test Files (read second)
1. **Client Core Tests**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/test/claude_agent_sdk/client_test.exs`  
   - Purpose: Ensures `Client.stream_messages/1`, control protocol handshake, and message handling stay stable.  
   - Focus: Tests covering initialization and message subscription.

2. **Client Permission & Agent Tests**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/test/claude_agent_sdk/client_permission_test.exs`  
   - Purpose: Validates permission modes and callbacks we must keep working under control routing.

3. **SDK MCP Integration Tests**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/test/claude_agent_sdk/sdk_mcp_integration_test.exs`  
   - Purpose: Verifies SDK MCP server routing; must pass under streaming mode too.  
   - Focus: Cases for tool execution and error propagation.

4. **Transport Tests**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/test/claude_agent_sdk/transport/transport_test.exs`  
   - Purpose: Understand expectations for transport behaviour when switching router paths.

### Existing Infrastructure (read third)
1. **Options Builder**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/options.ex`  
   - Purpose: CLI argument generation; will need new fields (`include_partial_messages`, `preferred_transport`).  
   - Focus: `to_args/1`, `add_mcp_args/2`.

2. **Client Control Protocol Handling**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/client.ex`  
   - Purpose: Hook registry, SDK MCP routing, message broadcast logic.  
   - Focus: `build_cli_command/1`, `handle_decoded_message/3`, `handle_sdk_mcp_request/3`.

3. **Streaming Session**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/streaming/session.ex`  
   - Purpose: Current streaming-only path to compare against router-based version.

4. **Event Parser**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/streaming/event_parser.ex`  
   - Purpose: Ensure partial-event semantics match new control-client parsing.

### Example Usage (read fourth)
1. **Streaming Module Public API**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/lib/claude_agent_sdk/streaming.ex`  
   - Shows: Public contract consumers rely on; must remain stable.

2. **Examples – LiveView Integration**  
   - Location: `/home/home/p/g/n/claude_agent_sdk/docs/20251007/06_BIDIRECTIONAL_STREAMING_PLAN.md` (Phoenix LiveView section)  
   - Purpose: Understand UI expectations for event ordering and message completion.

---

## TASK

Deliver a unified streaming pipeline that automatically selects the appropriate transport, enabling simultaneous partial-response streaming and tool execution.

**Quantified Goals**
- Introduce router that chooses between CLI-only and control transport based on options.  
- Add `include_partial_messages` and `preferred_transport` fields to `ClaudeAgentSDK.Options`.  
- Modify `ClaudeAgentSDK.Client` to support `--include-partial-messages` and emit parsed streaming events.  
- Update `ClaudeAgentSDK.Streaming` to route through the control client when tools/hooks/SDK MCP are requested.  
- Provide helper utilities for consuming mixed event/message streams.  
- Maintain zero regressions across existing tests; add new integration coverage for streaming + tools.

**Deliverables**
1. `lib/claude_agent_sdk/transport/streaming_router.ex` (+ tests).  
2. Updated `ClaudeAgentSDK.Options`, OptionBuilder, and documentation.  
3. Enhanced `ClaudeAgentSDK.Client` with partial-event parsing and broadcast.  
4. Refactored `ClaudeAgentSDK.Streaming` facade supporting both transports.  
5. New or updated tests covering streaming with MCP tools and hooks.  
6. Updated docs/examples per migration plan.

**Impact**
- Enables LiveView/UI clients to display partial responses while the agent uses tools.  
- Removes “tools vs. streaming” trade-off for SDK adopters.  
- Lays groundwork for future transport pluggability.

---

## CONSTRAINTS

### Must Work With
- Existing hook system (`ClaudeAgentSDK.Hooks`), permission callbacks, and SDK MCP servers.  
- CLI transport fallback for simple use cases (no hooks/tools).  
- Elixir Streams contract used by `Streaming.send_message/2`.  
- Mix tasks: `mix claude.setup_token`, `mix run.live`, existing examples.

### Cannot Break
- Backwards compatibility of `Client.stream_messages/1` for code expecting `%ClaudeAgentSDK.Message{}` only (provide adapters).  
- CLI-only streaming performance characteristics.  
- Existing API signatures (`Streaming.start_session/1`, `Streaming.send_message/2`).  
- Dialyzer and Credo cleanliness.

### Performance Requirements
- Maintain streaming latency comparable to current CLI path when no control features required.  
- Control transport overhead acceptable but must be benchmarked; avoid unnecessary blocking operations.  
- Event parsing should avoid allocating large intermediate lists for high-frequency deltas.

### Architectural Requirements
- Router logic isolated and unit-tested.  
- No duplicate flag handling; options remain source of truth.  
- Streaming events represented with typed struct or well-documented tagged tuples.  
- Documentation updated to reflect new option fields and behaviour.

---

## PROCESS

### Phase 1: Investigation
1. Read documentation set above in order (architecture → historical plans → gap analyses → MCP status).  
2. Review test files to understand current behavioural guarantees.  
3. Study existing implementation modules and usage examples.

### Phase 2: Analysis
1. Map all code paths that currently launch the CLI (CLI streaming vs. Client).  
2. Catalogue features requiring control protocol (hooks, MCP, permission callbacks, agents, runtime model changes).  
3. Define router decision matrix and document in-line with architecture doc.  
4. Identify serialization format for mixed event/message stream (tagging strategy).

### Phase 3: Implementation (TDD)

**RED – Write Failing Tests**
1. Create `test/claude_agent_sdk/transport/streaming_router_test.exs` covering selection logic.  
2. Add integration test (e.g., `test/claude_agent_sdk/streaming/control_streaming_test.exs`) that simulates partial events + tool requests (use mocks).  
3. Extend existing client tests to expect partial event handling when `include_partial_messages: true`.  
4. Run `mix test` – ensure failures correspond to missing implementations.

**GREEN – Implement Minimum Code**
1. Implement router module and integrate into `Streaming.Session.start_link/1`.  
2. Extend `Options` struct, OptionBuilder, and CLI builders.  
3. Update `Client.build_cli_command/1`, partial-event parsing, and broadcast pipeline.  
4. Adapt `Streaming` facade to consume router output and normalize events.  
5. Implement helper adapters for downstream consumers.  
6. Run `mix test` continuously; tests should begin passing as functionality is completed.

**REFACTOR – Hardening & Cleanup**
1. Ensure zero duplication between CLI and control transport code paths.  
2. Optimize event normalization utilities.  
3. Update documentation and examples.  
4. Run full quality suite:  
   - `mix format`  
   - `mix compile --warnings-as-errors`  
   - `mix credo --strict`  
   - `mix dialyzer`  
   - `mix test --include integration`

### Phase 4: Verification
1. Execute sample scripts (`mix run.live examples/basic_example.exs`).  
2. Manual smoke test with CLI to confirm partial streaming and tool usage operate concurrently.  
3. Gather benchmark data (latency/CPU) before and after changes; document in release notes.

---

## SUCCESS CRITERIA

### Functional
- Router correctly selects control transport when hooks/MCP/permission callbacks/agents are present.  
- Partial events (`:text_delta`, `:tool_input_delta`, `:thinking_delta`) appear when streaming via control client.  
- Tool calls succeed while partial events stream (validated by integration test).  
- CLI-only mode remains unaffected for options without control features.

### Quality
- All tests pass (`mix test`, `mix test --include integration`).  
- No compiler warnings (`mix compile --warnings-as-errors`).  
- Credo and Dialyzer clean.  
- Updated docs/examples committed.

### Verification Commands
```bash
mix format
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
mix test --include integration
mix run.live examples/basic_example.exs --once
```
Expected: no failures or warnings.

---

## SHOW ME

### Artifacts to Produce
1. **Router Module & Tests**  
   - `lib/claude_agent_sdk/transport/streaming_router.ex`  
   - `test/claude_agent_sdk/transport/streaming_router_test.exs`

2. **Options & Builders**  
   - Updated `lib/claude_agent_sdk/options.ex` with new fields and docs.  
   - OptionBuilder presets reflecting new defaults.

3. **Control Client Enhancements**  
   - `lib/claude_agent_sdk/client.ex` changes showing partial-event support.  
   - New helper module (if introduced) for event normalization.

4. **Streaming Facade Integration**  
   - Changes to `lib/claude_agent_sdk/streaming/session.ex` and `lib/claude_agent_sdk/streaming.ex`.

5. **Documentation Updates**  
   - Revised sections in `README.md` (streaming), `docs/20251025/*`, and examples under `examples/`.

6. **Test Evidence**  
   - Paste final `mix test` and `mix test --include integration` output showing zero failures/warnings.  
   - Provide excerpt of integration test demonstrating partial events + tool usage.

### Confidence Checks
```bash
# Ensure router logic exercised
mix test test/claude_agent_sdk/transport/streaming_router_test.exs

# Validate combined streaming + tools behaviour
mix test --include integration test/claude_agent_sdk/streaming/control_streaming_test.exs

# Manual CLI sanity check (optional)
CLAUDE_AGENT_OAUTH_TOKEN=... iex -S mix
iex> {:ok, session} = ClaudeAgentSDK.Streaming.start_session(%Options{include_partial_messages: true, mcp_servers: %{...}})
iex> stream = ClaudeAgentSDK.Streaming.send_message(session, "List project files")
iex> Enum.take(stream, 5)
```
Expected: mixed event/message tuples with tool usage results.

---

By following this prompt, Claude Code (or any engineer) has all necessary context, constraints, and verification steps to deliver the streaming + tools unification without additional clarification.***
