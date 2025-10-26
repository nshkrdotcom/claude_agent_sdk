# Implementation Roadmap: Streaming + Tools Unification

**Project Duration**: 10-14 developer days
**Target Release**: v0.6.0
**Team Size**: 1-2 developers
**Start Date**: TBD
**Risk Level**: LOW-MEDIUM

---

## Executive Summary

This roadmap provides day-by-day implementation guidance for the Streaming + Tools transport unification. Each phase includes specific deliverables, verification steps, and decision points.

**Critical Path**: Day 1 CLI verification → Router → Client → Integration → Testing

**Buffer**: 2-3 days built into estimate for unknowns

---

## Pre-Implementation Checklist

### ☐ Environment Setup

```bash
# 1. Clone and branch
cd claude_agent_sdk
git checkout main
git pull origin main
git checkout -b feature/streaming-tools-unification

# 2. Verify test baseline
mix test
# Expected: 477 passes, 0 failures

# 3. Verify quality baseline
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer

# 4. Install dependencies
mix deps.get
mix deps.compile

# 5. Verify CLI availability
which claude
# Should return path to Claude CLI

# 6. Test auth
claude --version
# Should show version without auth errors
```

### ☐ Documentation Review

- [x] Read STREAMING_WITH_TOOLS_ARCHITECTURE.md
- [x] Read 00_FEASIBILITY_ASSESSMENT.md
- [x] Read 01_ROUTER_DESIGN.md
- [x] Read 02_CLIENT_STREAMING_ENHANCEMENTS.md
- [x] Read 03_STREAMING_FACADE_INTEGRATION.md
- [x] Read 04_TESTING_STRATEGY.md
- [x] Review existing EventParser implementation
- [x] Review existing Streaming.Session implementation

---

## Phase 1: Foundation & Verification (Days 1-3)

### Day 1: CLI Compatibility Verification & Setup

**Goal**: Confirm Claude CLI supports simultaneous streaming + control protocol

**Tasks**:

1. **CLI Verification** (GATE CONDITION):
   ```bash
   # Test CLI with both flags
   echo '{"type":"control_request","request_id":"test-001","request":{"subtype":"initialize","version":"1.0.0","hooks":{}}}' | \
   claude --output-format stream-json \
          --input-format stream-json \
          --include-partial-messages \
          --verbose

   # Expected: CLI accepts both, responds with control_response
   # If fails: ESCALATE - may need CLI update or pivot strategy
   ```

2. **Create router skeleton**:
   ```bash
   mkdir -p lib/claude_agent_sdk/transport
   touch lib/claude_agent_sdk/transport/streaming_router.ex
   touch test/claude_agent_sdk/transport/streaming_router_test.exs
   ```

3. **Write router tests (TDD Red)**:
   - 50 test cases following 01_ROUTER_DESIGN.md
   - All should fail (router not implemented yet)

4. **Implement router**:
   - ~120 lines per design doc
   - Pure function, no GenServer
   - Run tests until all pass

**Deliverables**:
- ✅ CLI compatibility confirmed (or pivot plan)
- ✅ StreamingRouter module complete (100% test coverage)
- ✅ 50 passing tests

**Verification**:
```bash
mix test test/claude_agent_sdk/transport/streaming_router_test.exs
# Expected: 50 passes, 0 failures

mix dialyzer lib/claude_agent_sdk/transport/streaming_router.ex
# Expected: no warnings
```

**Decision Point**:
- ❌ If CLI incompatible → STOP, escalate to stakeholders
- ✅ If CLI compatible → PROCEED to Day 2

---

### Day 2: Options Extension

**Goal**: Add new fields to Options for streaming control

**Tasks**:

1. **Update Options struct** (lib/claude_agent_sdk/options.ex):
   ```elixir
   # Add to defstruct (around line 94):
   :include_partial_messages,
   :preferred_transport
   ```

2. **Add typespecs** (around line 153):
   ```elixir
   include_partial_messages: boolean() | nil,
   preferred_transport: transport_preference() | nil

   @type transport_preference :: :auto | :cli | :control
   ```

3. **Add CLI arg generator**:
   ```elixir
   defp add_partial_messages_args(args, %{include_partial_messages: true}) do
     args ++ ["--include-partial-messages"]
   end
   defp add_partial_messages_args(args, _), do: args
   ```

4. **Update to_args pipeline** (line 202-222)

5. **Write tests**:
   ```elixir
   test "includes partial messages flag when set" do
     opts = %Options{include_partial_messages: true}
     args = Options.to_args(opts)
     assert "--include-partial-messages" in args
   end
   ```

6. **Update documentation**:
   - Module doc with new fields
   - Examples showing streaming + tools
   - Migration notes

**Deliverables**:
- ✅ Options extended with 2 new fields
- ✅ CLI arg generation updated
- ✅ 10 new tests passing
- ✅ Documentation updated

**Verification**:
```bash
mix test test/claude_agent_sdk/options_test.exs
# Expected: all tests pass (including new ones)

mix format
mix credo --strict
# Expected: no issues
```

---

### Day 3: Test Infrastructure Setup

**Goal**: Create mock CLI helpers for integration testing

**Tasks**:

1. **Create test support modules**:
   ```bash
   mkdir -p test/support
   touch test/support/mock_cli.ex
   touch test/support/cli_script_builder.ex
   touch test/support/event_assertions.ex
   ```

2. **Implement MockCLI** (per 04_TESTING_STRATEGY.md section 5.1)

3. **Implement CLIScriptBuilder**

4. **Write first failing integration test**:
   ```elixir
   # test/claude_agent_sdk/streaming_tools_integration_test.exs
   @tag :integration
   test "streams text while executing tools" do
     # Should fail - implementation not done yet
   end
   ```

5. **Set up test fixtures**:
   - Sample tool definitions
   - Test hooks
   - Mock MCP servers

**Deliverables**:
- ✅ Mock CLI infrastructure ready
- ✅ 1 failing integration test (expected)
- ✅ Test helpers documented

**Verification**:
```bash
mix test test/claude_agent_sdk/streaming_tools_integration_test.exs
# Expected: 1 failure (not implemented)

# Test helpers work
iex -S mix
iex> alias ClaudeAgentSDK.Test.CLIScriptBuilder
iex> CLIScriptBuilder.new() |> CLIScriptBuilder.emit_text("test")
# Expected: returns builder struct
```

**End of Phase 1 Checkpoint**:
- ✅ CLI compatibility verified
- ✅ Router complete and tested (50 tests)
- ✅ Options extended (10 tests)
- ✅ Test infrastructure ready
- ✅ Zero regressions (477 original tests still pass)

---

## Phase 2: Core Implementation (Days 4-8)

### Day 4-5: Client Enhancements (Part 1 - State & Parsing)

**Goal**: Add streaming support to Client GenServer

**Day 4 Tasks**:

1. **Update Client state** (lib/claude_agent_sdk/client.ex line 84-98):
   - Change `subscribers` to map
   - Add streaming fields (accumulated_text, active_subscriber, queue)

2. **Modify initialization** (line 337-354):
   - Initialize new state fields

3. **Update build_cli_command** (line 801-818):
   - Add conditional `--include-partial-messages`

4. **Write unit tests**:
   ```elixir
   test "includes partial messages in CLI command when set" do
     opts = %Options{include_partial_messages: true}
     {:ok, client} = Client.start_link(opts)
     # Verify via inspection or mock
   end
   ```

5. **Enhance Protocol.decode_message**:
   - Add `:stream_event` case
   - Test decoding

**Day 5 Tasks**:

6. **Implement handle_stream_event** (new function after line 837):
   - Delegate to EventParser
   - Broadcast to active subscriber
   - Handle message completion

7. **Implement handle_message_completion**:
   - Queue processing logic
   - Reset accumulated text

8. **Write comprehensive event handling tests** (~20 tests):
   - Text delta accumulation
   - Thinking deltas
   - Tool input deltas
   - Message completion

**Deliverables**:
- ✅ Client state updated
- ✅ Stream event parsing working
- ✅ Event handler implemented
- ✅ 20 new tests passing

**Verification**:
```bash
mix test test/claude_agent_sdk/client_streaming_test.exs
# Expected: 20 passes

mix test test/claude_agent_sdk/client_test.exs
# Expected: all original tests still pass
```

---

### Day 6: Client Enhancements (Part 2 - Subscriber Queue)

**Goal**: Implement subscriber queue management

**Tasks**:

1. **Enhance subscribe handler** (modify line 432-435):
   - Accept reference parameter
   - Activate or queue subscriber
   - Monitor subscriber

2. **Implement unsubscribe handler** (new):
   - Remove from map and queue
   - Activate next if was active

3. **Update send_message handler** (line 379-393):
   - Queue messages when subscriber active

4. **Write queue tests** (~15 tests):
   - First subscriber activates immediately
   - Second subscriber queues
   - Auto-activation on completion
   - Unsubscribe handling

5. **Add defensive programming**:
   - Queue overflow protection
   - Missing subscriber warnings
   - Error event generation

**Deliverables**:
- ✅ Subscriber queue working
- ✅ 15 new tests passing
- ✅ Error handling robust

**Verification**:
```bash
mix test test/claude_agent_sdk/client_streaming_test.exs
# Expected: 40 total passes (20 from Day 5 + 15 new + 5 error tests)

# Manual queue test
iex -S mix
iex> {:ok, client} = Client.start_link(%Options{include_partial_messages: true})
iex> ref1 = make_ref()
iex> ref2 = make_ref()
iex> GenServer.call(client, {:subscribe, ref1})
iex> GenServer.call(client, {:subscribe, ref2})
# ref2 should be queued
```

---

### Day 7: Streaming Facade Integration

**Goal**: Update Streaming module to use router

**Tasks**:

1. **Modify start_session** (lib/claude_agent_sdk/streaming.ex):
   - Add router call
   - Implement start_control_streaming
   - Force include_partial_messages

2. **Add send_message polymorphism**:
   - Handle both PID and {:control_client, pid}
   - Implement stream_via_control_client

3. **Implement control client stream adapter**:
   - adapt_control_client_stream function
   - Message-to-event conversion
   - Stream lifecycle management

4. **Add close/1 polymorphism**

5. **Write tests** (~10 tests):
   - Router integration
   - Session type detection
   - send_message with both transports
   - close with both transports

**Deliverables**:
- ✅ Streaming facade updated
- ✅ Transport switching transparent
- ✅ 10 new tests passing

**Verification**:
```bash
mix test test/claude_agent_sdk/streaming_test.exs
# Expected: all tests pass

# Manual verification
iex -S mix
iex> {:ok, session1} = Streaming.start_session()
iex> is_pid(session1)
# => true (CLI-only)

iex> {:ok, session2} = Streaming.start_session(%Options{hooks: %{...}})
iex> match?({:control_client, _}, session2)
# => true (control client)
```

---

### Day 8: Event Adapter Utilities

**Goal**: Provide helpers for consuming mixed streams

**Tasks**:

1. **Create EventAdapter module**:
   ```bash
   touch lib/claude_agent_sdk/streaming/event_adapter.ex
   touch test/claude_agent_sdk/streaming/event_adapter_test.exs
   ```

2. **Implement normalization functions** (per design doc):
   - to_events/1
   - text_only/1
   - tools_only/1
   - accumulate_text/1

3. **Write comprehensive tests** (~25 tests):
   - Event passthrough
   - Message conversion
   - Filtering
   - Accumulation
   - Edge cases

4. **Add documentation and examples**

**Deliverables**:
- ✅ EventAdapter module complete
- ✅ 25 new tests passing
- ✅ Examples documented

**Verification**:
```bash
mix test test/claude_agent_sdk/streaming/event_adapter_test.exs
# Expected: 25 passes, 100% coverage

# Manual test
iex> alias ClaudeAgentSDK.Streaming.EventAdapter
iex> stream = [%{type: :text_delta, text: "Hi"}, %Message{...}]
iex> EventAdapter.to_events(stream) |> Enum.to_list()
# Should normalize both types
```

**End of Phase 2 Checkpoint**:
- ✅ Client streaming complete (~200 LOC, 40 tests)
- ✅ Streaming facade integrated (~180 LOC, 10 tests)
- ✅ EventAdapter ready (~120 LOC, 25 tests)
- ✅ Total new tests: 125+ passing
- ✅ Zero regressions (477 original + 60 from Phase 1 still pass)

---

## Phase 3: Integration & Hardening (Days 9-11)

### Day 9: Integration Testing

**Goal**: Validate end-to-end scenarios with mocked CLI

**Tasks**:

1. **Implement 20 integration scenarios** (per 04_TESTING_STRATEGY.md):
   - Text-only streaming via control
   - Interleaved text + tools
   - Multiple tools
   - Tool errors
   - Hook denials
   - Permission callbacks
   - SDK MCP invocation
   - Queue scenarios
   - etc.

2. **Use MockCLI infrastructure** from Day 3

3. **Debug integration issues**:
   - Event ordering
   - State machine transitions
   - Error propagation

4. **Add logging for debugging**:
   ```elixir
   require Logger

   Logger.debug("Router selected",
     transport: choice,
     features: detect_features(opts)
   )
   ```

**Deliverables**:
- ✅ 20 integration tests passing
- ✅ Known integration issues resolved
- ✅ Comprehensive scenario coverage

**Verification**:
```bash
mix test --include integration
# Expected: 20 new integration tests passing

# Run specific scenarios
mix test test/claude_agent_sdk/streaming_tools_integration_test.exs:42
# Test line 42: "streams text while executing tools"
```

---

### Day 10: Performance Validation & Optimization

**Goal**: Ensure no significant performance regressions

**Tasks**:

1. **Benchmark router overhead**:
   ```elixir
   defmodule StreamingRouterBenchmark do
     def run do
       opts = %Options{hooks: %{...}}  # Worst case

       {time_us, _} = :timer.tc(fn ->
         for _ <- 1..1000 do
           StreamingRouter.select_transport(opts)
         end
       end)

       avg_us = time_us / 1000
       IO.puts("Router: #{avg_us}μs avg")
       # Target: <100μs
     end
   end
   ```

2. **Benchmark streaming latency**:
   ```elixir
   # CLI-only baseline
   {time_cli, _} = measure_time_to_first_event(:cli_only)

   # Control client
   {time_control, _} = measure_time_to_first_event(:control_client)

   regression = (time_control - time_cli) / time_cli * 100
   # Target: <10% regression
   ```

3. **Profile if needed**:
   ```bash
   mix profile.fprof -e "run_streaming_scenario()"
   # Identify hot spots
   ```

4. **Optimize if regression >10%**:
   - Cache router decisions?
   - Optimize JSON parsing?
   - Reduce GenServer call overhead?

5. **Document performance characteristics**

**Deliverables**:
- ✅ Benchmark results documented
- ✅ Performance within acceptable range
- ✅ Optimization applied if needed

**Verification**:
```bash
mix run -e "StreamingRouterBenchmark.run()"
# Expected: <100μs avg

mix run -e "StreamingLatencyBenchmark.run()"
# Expected: CLI: ~200ms, Control: <350ms
```

---

### Day 11: Edge Cases & Error Handling

**Goal**: Harden implementation against edge cases

**Tasks**:

1. **Test error scenarios**:
   - Malformed stream events
   - CLI crashes mid-stream
   - Subscriber process dies
   - Queue overflow
   - Timeout scenarios

2. **Add defensive programming**:
   - Validate event structure
   - Handle missing fields gracefully
   - Log warnings for unexpected states

3. **Test concurrent scenarios**:
   - Multiple subscribers
   - Rapid subscribe/unsubscribe
   - Message flood

4. **Memory leak testing**:
   ```elixir
   test "no memory leaks after 1000 messages" do
     {:ok, session} = Streaming.start_session()

     initial_memory = :erlang.memory(:total)

     for i <- 1..1000 do
       Streaming.send_message(session, "Message #{i}")
       |> Enum.take(10)
     end

     final_memory = :erlang.memory(:total)
     growth = final_memory - initial_memory

     # Should not grow significantly
     assert growth < 10_000_000  # 10MB threshold
   end
   ```

5. **Document known limitations**

**Deliverables**:
- ✅ Edge case tests passing
- ✅ Error handling robust
- ✅ No memory leaks
- ✅ Limitations documented

**Verification**:
```bash
mix test --include edge_cases
# Expected: all pass

# Stress test
mix test --include stress
# Monitor memory usage
```

**End of Phase 3 Checkpoint**:
- ✅ 20 integration tests passing
- ✅ Performance validated
- ✅ Edge cases handled
- ✅ Total tests: ~600+ (477 original + 125 new)
- ✅ Zero regressions, zero memory leaks

---

## Phase 4: Finalization (Days 12-14)

### Day 12: Documentation & Examples

**Goal**: Complete documentation for release

**Tasks**:

1. **Update README.md**:
   - Add streaming + tools section
   - Show LiveView integration example
   - Migration guide from v0.5.x

2. **Update module documentation**:
   - StreamingRouter
   - Client (new functions)
   - Streaming (updated behavior)
   - EventAdapter

3. **Create examples**:
   ```bash
   mkdir -p examples/streaming_tools
   touch examples/streaming_tools/basic_streaming_with_hooks.exs
   touch examples/streaming_tools/sdk_mcp_calculator.exs
   touch examples/streaming_tools/liveview_integration.exs
   ```

4. **Write CHANGELOG entry** for v0.6.0:
   ```markdown
   ## [0.6.0] - 2025-XX-XX

   ### Added
   - Streaming + tools unification via StreamingRouter
   - `include_partial_messages` option for character-level streaming
   - `preferred_transport` option for transport override
   - EventAdapter utilities for mixed streams
   - Comprehensive integration tests

   ### Changed
   - Streaming module now automatically selects transport
   - Client supports partial message events

   ### Migration
   - No breaking changes
   - Opt-in via `include_partial_messages: true`
   ```

5. **Update architecture docs**:
   - Update design/streaming.md
   - Add transport selection diagram
   - Document decision matrix

**Deliverables**:
- ✅ README updated
- ✅ Examples working
- ✅ CHANGELOG complete
- ✅ Architecture docs updated

**Verification**:
```bash
# Test examples
mix run examples/streaming_tools/basic_streaming_with_hooks.exs

# Docs preview
mix docs
open doc/index.html
# Verify new sections rendered correctly
```

---

### Day 13: Live CLI Validation

**Goal**: Validate with real Claude CLI

**Tasks**:

1. **Set up live test environment**:
   ```bash
   export CLAUDE_AGENT_OAUTH_TOKEN=...
   export LIVE_TESTS=true
   ```

2. **Run live test suite**:
   ```bash
   mix test --include live
   # Expected: 5 passes (real CLI scenarios)
   ```

3. **Manual smoke tests**:
   - Run examples with real CLI
   - Test with actual SDK MCP server
   - Verify LiveView pattern works

4. **Performance validation with real CLI**:
   - Measure actual latency
   - Compare against targets

5. **Fix any live-only issues**:
   - CLI output format differences
   - Timing issues
   - Auth problems

**Deliverables**:
- ✅ 5 live tests passing
- ✅ Examples work with real CLI
- ✅ Performance meets targets
- ✅ No live-only bugs

**Verification**:
```bash
LIVE_TESTS=true mix test --include live test/integration/streaming_tools_live_test.exs
# Expected: 5 passes

mix run.live examples/streaming_tools/sdk_mcp_calculator.exs
# Should show streaming + tool execution
```

---

### Day 14: Final Quality Gates & Release Prep

**Goal**: Final verification and release preparation

**Tasks**:

1. **Run full quality suite**:
   ```bash
   # Format
   mix format
   git diff --exit-code
   # Expected: no changes

   # Compile warnings
   mix clean
   mix compile --warnings-as-errors
   # Expected: zero warnings

   # Credo
   mix credo --strict
   # Expected: zero issues

   # Dialyzer
   mix dialyzer
   # Expected: zero errors

   # Full test suite
   mix test --include integration
   # Expected: 600+ passes, 0 failures

   # Coverage
   mix test --cover
   # Expected: >90% coverage on new code
   ```

2. **Code review prep**:
   - Self-review all changes
   - Check for TODOs
   - Verify all tests have assertions
   - Review error messages for clarity

3. **Performance regression test**:
   ```bash
   # Compare main vs feature branch
   git checkout main
   mix test
   # Record time

   git checkout feature/streaming-tools-unification
   mix test
   # Compare time - should be <5% slower
   ```

4. **Create PR**:
   - Descriptive title
   - Link to design docs
   - Checklist of deliverables
   - Screenshots/demos if applicable

5. **Tag release candidate**:
   ```bash
   git tag v0.6.0-rc1
   ```

**Deliverables**:
- ✅ All quality gates passed
- ✅ PR created
- ✅ Release candidate tagged
- ✅ Ready for review

**Verification**:
```bash
# Final checklist
./scripts/pre_release_check.sh

# Expected output:
# ✅ Format: PASS
# ✅ Compile: PASS
# ✅ Credo: PASS
# ✅ Dialyzer: PASS
# ✅ Tests: PASS (620/620)
# ✅ Coverage: 92%
# ✅ Docs: PASS
# ✅ Examples: PASS
# Ready for release!
```

**End of Phase 4 Checkpoint**:
- ✅ Documentation complete
- ✅ Examples working
- ✅ Live tests passing
- ✅ All quality gates passed
- ✅ PR ready for review
- ✅ v0.6.0-rc1 tagged

---

## Risk Management

### Daily Standups (Virtual)

End of each day, answer:
1. What did I complete today?
2. What am I working on tomorrow?
3. Any blockers or risks?

Example Day 5 standup:
- ✅ Completed: Client state updated, stream event parsing working
- 🏗️ Tomorrow: Subscriber queue implementation
- ⚠️ Risks: Queue complexity higher than estimated, may need Day 6.5

### Contingency Triggers

| Trigger | Action |
|---------|--------|
| Day 1 CLI incompatible | STOP - escalate to stakeholders |
| Day 5 behind schedule | Drop EventAdapter to Phase 4 |
| Day 9 integration failures >50% | Add Day 9.5 for debugging |
| Day 10 performance >20% regression | Add optimization sprint (Day 10.5) |
| Day 13 live tests fail | Defer live tests to post-release |

### Escalation Path

1. **Minor issue** (< 4 hours delay): Continue, note in standup
2. **Moderate issue** (< 1 day delay): Use buffer day, adjust schedule
3. **Major issue** (> 1 day delay): Escalate to project lead
4. **Blocker** (architectural problem): STOP, convene decision meeting

---

## Success Metrics

### Completion Criteria

| Metric | Target | Actual |
|--------|--------|--------|
| Unit tests | 115 | ___ |
| Integration tests | 30 | ___ |
| Live tests | 5 | ___ |
| Code coverage | >90% | ___% |
| Performance regression | <10% | ___% |
| Dialyzer warnings | 0 | ___ |
| Credo issues | 0 | ___ |
| Documentation pages | 6+ | ___ |
| Working examples | 3+ | ___ |

### Quality Gates (All Must Pass)

- [ ] `mix format --check-formatted`
- [ ] `mix compile --warnings-as-errors`
- [ ] `mix credo --strict`
- [ ] `mix dialyzer`
- [ ] `mix test --include integration` (0 failures)
- [ ] `mix test --cover` (>90% new code coverage)
- [ ] Examples run without errors
- [ ] Docs render correctly
- [ ] CHANGELOG updated
- [ ] No security vulnerabilities

---

## Post-Implementation

### Release Process

1. **Create release PR** from feature branch
2. **Team review** (1-2 days)
3. **Address feedback**
4. **Merge to main**
5. **Tag v0.6.0**:
   ```bash
   git tag -a v0.6.0 -m "Streaming + Tools Unification"
   git push origin v0.6.0
   ```

6. **Publish to Hex**:
   ```bash
   mix hex.publish
   ```

7. **Announce release**:
   - GitHub release notes
   - Community post
   - Update docs site

### Monitoring (First Week)

- **Community feedback**: Monitor issues/discussions
- **Bug reports**: Triage within 24 hours
- **Performance**: Ask users to report latency
- **Adoption**: Track MCP usage with streaming

### Retrospective (After 1 Week)

Questions:
1. What went well?
2. What could be improved?
3. What surprised us?
4. What should we do differently next time?

Document in: `docs/retrospectives/v0.6.0_streaming_tools.md`

---

## Appendix A: Daily Checklist Template

```markdown
## Day X: [Task Name]

Date: ___________
Developer: ___________

### Morning
- [ ] Review design doc for today's tasks
- [ ] Pull latest changes
- [ ] Run baseline tests

### Implementation
- [ ] Task 1: _____________
- [ ] Task 2: _____________
- [ ] Task 3: _____________

### Testing
- [ ] Unit tests written (TDD)
- [ ] Unit tests passing
- [ ] Integration tests (if applicable)
- [ ] Manual verification

### Quality
- [ ] `mix format`
- [ ] `mix credo`
- [ ] `mix dialyzer` (if new modules)
- [ ] Code review self-check

### Documentation
- [ ] Inline docs updated
- [ ] Examples updated (if applicable)
- [ ] CHANGELOG noted

### End of Day
- [ ] Commit changes
- [ ] Push to feature branch
- [ ] Update daily standup
- [ ] Note blockers/risks

### Notes
_______________
```

---

## Appendix B: Useful Commands Reference

```bash
# Quick test cycle
alias test-quick="mix format && mix test --exclude integration --exclude live"

# Full CI simulation
alias test-ci="mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix dialyzer && mix test --include integration"

# Coverage for specific module
mix test --cover --filter module:StreamingRouter

# Run single test
mix test path/to/test.exs:42

# Benchmark
mix run -e "MyBenchmark.run()"

# Docs preview
mix docs && open doc/index.html

# Profile
mix profile.fprof -e "MyModule.expensive_function()"

# Memory profiling
iex -S mix
:observer.start()
```

---

## Summary

This roadmap provides a structured 14-day path to deliver Streaming + Tools unification with:

✅ **Clear daily goals** and deliverables
✅ **Built-in verification** at each step
✅ **Risk mitigation** via checkpoints and contingencies
✅ **Quality gates** enforced throughout
✅ **Buffer time** for unknowns (Days 10.5, 14+)

**Follow this roadmap** to minimize risk and maximize probability of on-time, high-quality delivery.

**Questions?** Refer back to design docs (00-04) for detailed implementation guidance.
