# Streaming + Tools Transport Unification Documentation

**Project**: Claude Agent SDK - Streaming with Tools Support
**Version**: v0.6.0
**Status**: Design Complete - Ready for Implementation
**Date**: 2025-10-25

---

## Overview

This directory contains comprehensive technical design and implementation documentation for unifying Claude Agent SDK's streaming (partial messages) and control protocol (tools, hooks, permissions) capabilities.

**Goal**: Enable simultaneous character-level streaming and tool execution through automatic transport selection.

**Impact**: Eliminates the current "streaming vs. tools" trade-off, enabling rich interactive experiences like LiveView UIs with real-time feedback while Claude uses tools.

---

## Document Index

### 00. [Feasibility Assessment](./00_FEASIBILITY_ASSESSMENT.md)
**Purpose**: Comprehensive analysis of project viability
**Status**: ✅ Approved - 85% confidence, LOW-MEDIUM risk
**Read First**: Yes
**Key Sections**:
- Architectural readiness analysis (existing infrastructure evaluation)
- Technical risk assessment (5 identified risks with mitigations)
- Component complexity breakdown (router: ⭐, client: ⭐⭐⭐)
- Timeline estimate (10-14 days with buffer)
- Success probability by component (82% overall)
- Backwards compatibility guarantee (zero breaking changes)

**Executive Summary**: Highly feasible project leveraging strong existing foundation. Key risks are CLI compatibility (Day 1 verification) and integration complexity (managed via TDD).

---

### 01. [Router Design](./01_ROUTER_DESIGN.md)
**Purpose**: Detailed design of StreamingRouter decision module
**Complexity**: ⭐ (1/5) - Low
**Implementation Time**: 1 day
**Key Sections**:
- Decision matrix (control features detection)
- Implementation (~120 LOC pure function)
- Test strategy (50 tests, 100% coverage target)
- Performance analysis (<0.1ms overhead)
- Integration points

**Key Insight**: Router is a simple pattern-matching function that analyzes Options to select between CLI-only (fast) and control client (full-featured) transports.

**Decision Logic**:
```elixir
needs_control? =
  has_hooks? or
  has_sdk_mcp? or
  has_permission_callback? or
  has_agents? or
  special_permission_mode?
```

---

### 02. [Client Streaming Enhancements](./02_CLIENT_STREAMING_ENHANCEMENTS.md)
**Purpose**: Modifications to enable streaming in control client
**Complexity**: ⭐⭐⭐ (3/5) - Medium
**Implementation Time**: 2-3 days
**Key Sections**:
- State structure changes (subscriber queue implementation)
- CLI command builder enhancement (`--include-partial-messages`)
- Stream event handler implementation (NEW)
- Subscriber queue semantics (FIFO, auto-activation)
- Mixed stream handling (events + messages)
- Testing strategy (40 tests)

**Key Challenge**: Implementing subscriber queue to match Streaming.Session semantics while integrating EventParser for consistent event format.

**Architecture Change**:
```elixir
# Before: Broadcast to all subscribers
subscribers: [pid(), ...]

# After: Queue model with active subscriber
subscribers: %{ref() => pid()},
active_subscriber: ref() | nil,
subscriber_queue: [{ref(), message()}, ...]
```

---

### 03. [Streaming Facade Integration](./03_STREAMING_FACADE_INTEGRATION.md)
**Purpose**: Update public Streaming API to use router
**Complexity**: ⭐⭐⭐ (3/5) - Medium
**Implementation Time**: 2 days
**Key Sections**:
- start_session/1 enhancement (router integration)
- send_message/2 polymorphism (Session vs Client)
- Control client stream adapter (event normalization)
- close/1 and get_session_id/1 polymorphism
- Event format unification
- Testing strategy (10 tests)

**Key Design**: Transparent transport switching via pattern matching on session type:
```elixir
# Session returns pid
{:ok, pid} = Streaming.start_session(%Options{})

# Client returns tagged tuple
{:ok, {:control_client, pid}} = Streaming.start_session(%Options{hooks: ...})
```

---

### 04. [Testing Strategy](./04_TESTING_STRATEGY.md)
**Purpose**: Comprehensive test plan (unit, integration, E2E)
**Total Tests**: ~150 tests
**Coverage Target**: >90% for new code
**Key Sections**:
- Test pyramid (75% unit, 20% integration, 5% E2E)
- Unit tests breakdown (~115 tests across 3 modules)
- Integration tests (20 scenarios with mocked CLI)
- Live tests (5 scenarios with real Claude CLI)
- Property-based tests (optional)
- Test utilities & helpers
- CI/CD workflow

**Test Distribution**:
- StreamingRouter: 50 unit tests (100% coverage)
- Client Streaming: 40 unit tests (>95% coverage)
- EventAdapter: 25 unit tests (100% coverage)
- Integration: 20 mocked scenarios
- Live: 5 real CLI scenarios

**Key Tool**: MockCLI for reproducible integration testing without CLI dependency.

---

### 05. [Implementation Roadmap](./05_IMPLEMENTATION_ROADMAP.md)
**Purpose**: Day-by-day implementation guide
**Duration**: 10-14 days (4 phases)
**Team**: 1-2 developers
**Key Sections**:
- Pre-implementation checklist
- Phase 1: Foundation (Days 1-3) - Router + setup
- Phase 2: Core Implementation (Days 4-8) - Client + facade
- Phase 3: Integration & Hardening (Days 9-11) - Testing
- Phase 4: Finalization (Days 12-14) - Docs + release
- Risk management (contingency plans)
- Success metrics (quality gates)

**Critical Path**:
```
Day 1: CLI Verification (GATE)
  → Router (Days 1-2)
  → Options (Day 2)
  → Client (Days 4-6)
  → Facade (Day 7)
  → Integration (Day 9)
  → Testing (Days 10-11)
  → Release (Days 12-14)
```

**Buffer**: 2-3 days for unknowns

---

## Reading Guide

### For Project Managers
1. Read: [00_FEASIBILITY_ASSESSMENT](./00_FEASIBILITY_ASSESSMENT.md) - Executive summary
2. Read: [05_IMPLEMENTATION_ROADMAP](./05_IMPLEMENTATION_ROADMAP.md) - Timeline & deliverables
3. Review: Success metrics and risk management sections

**Key Takeaway**: 85% confidence, 10-14 days, minimal risk

### For Architects
1. Read: [00_FEASIBILITY_ASSESSMENT](./00_FEASIBILITY_ASSESSMENT.md) - Architecture readiness
2. Read: [01_ROUTER_DESIGN](./01_ROUTER_DESIGN.md) - Decision logic
3. Read: [02_CLIENT_STREAMING_ENHANCEMENTS](./02_CLIENT_STREAMING_ENHANCEMENTS.md) - State management
4. Read: [03_STREAMING_FACADE_INTEGRATION](./03_STREAMING_FACADE_INTEGRATION.md) - API design

**Key Takeaway**: Clean separation of concerns, reuses existing patterns

### For Developers (Implementing)
1. **Start**: [05_IMPLEMENTATION_ROADMAP](./05_IMPLEMENTATION_ROADMAP.md) - Daily tasks
2. **Day 1**: [01_ROUTER_DESIGN](./01_ROUTER_DESIGN.md) - Router implementation
3. **Days 4-6**: [02_CLIENT_STREAMING_ENHANCEMENTS](./02_CLIENT_STREAMING_ENHANCEMENTS.md) - Client mods
4. **Day 7**: [03_STREAMING_FACADE_INTEGRATION](./03_STREAMING_FACADE_INTEGRATION.md) - Facade
5. **Days 8-11**: [04_TESTING_STRATEGY](./04_TESTING_STRATEGY.md) - Test implementation

**Daily Workflow**:
- Morning: Review design doc for today's section
- Implement: Follow TDD (write tests first)
- Evening: Run quality gates, update roadmap checklist

### For QA/Testers
1. Read: [04_TESTING_STRATEGY](./04_TESTING_STRATEGY.md) - Full test plan
2. Review: Integration test scenarios (section 2.1)
3. Review: Live test scenarios (section 3.1)

**Focus Areas**: Mocked CLI integration tests, real CLI validation

---

## Key Design Decisions

### 1. Transport Selection Strategy
**Decision**: Automatic via router, overridable
**Rationale**: Minimize user configuration burden while providing escape hatch
**Alternative Considered**: Always use control client (rejected - unnecessary overhead)

### 2. Session Type Representation
**Decision**: Tagged tuple `{:control_client, pid}` vs bare `pid`
**Rationale**: Explicit distinction enables polymorphic handling
**Alternative Considered**: Opaque wrapper module (rejected - over-engineering)

### 3. Event Format
**Decision**: Keep bare maps (current EventParser output)
**Rationale**: Backwards compatible, defer struct unification to v0.7.0
**Alternative Considered**: Unified `%Streaming.Event{}` struct (future work)

### 4. Subscriber Queue Model
**Decision**: Single active subscriber + FIFO queue (from Streaming.Session)
**Rationale**: Proven pattern, matches existing behavior
**Alternative Considered**: Broadcast to all (rejected - race conditions)

### 5. CLI Flag Strategy
**Decision**: Conditional `--include-partial-messages` based on option
**Rationale**: Opt-in behavior, zero regressions
**Alternative Considered**: Always include flag (rejected - unnecessary for non-streaming)

---

## Success Criteria Checklist

### Functional Requirements
- [ ] Router correctly selects transport based on options
- [ ] Control client emits partial message events
- [ ] Text deltas and tool calls stream interleaved
- [ ] Hooks invoked correctly during streaming
- [ ] SDK MCP tools executable while streaming
- [ ] Permission callbacks work with streaming
- [ ] CLI-only path performance maintained (<5% regression)
- [ ] All 477 existing tests pass unchanged

### Non-Functional Requirements
- [ ] Router overhead <1ms (measured)
- [ ] Control streaming latency <350ms to first event
- [ ] Zero breaking changes (verified)
- [ ] Test coverage >90% for new code
- [ ] Documentation complete (6 docs)
- [ ] Code quality maintained (Credo, Dialyzer clean)

### Quality Gates
- [ ] `mix format --check-formatted`
- [ ] `mix compile --warnings-as-errors`
- [ ] `mix credo --strict` (zero issues)
- [ ] `mix dialyzer` (zero errors)
- [ ] `mix test --include integration` (0 failures, 620+ passes)
- [ ] `mix test --cover` (>90% new code coverage)

---

## Technical Specifications

### Code Changes Summary

| Module | Type | LOC | Tests | Complexity |
|--------|------|-----|-------|------------|
| StreamingRouter | New | ~120 | 50 | ⭐ (Low) |
| Options | Modify | ~30 | 10 | ⭐ (Trivial) |
| Client | Modify | ~200 | 40 | ⭐⭐⭐ (Medium) |
| Streaming | Modify | ~180 | 10 | ⭐⭐⭐ (Medium) |
| EventAdapter | New | ~120 | 25 | ⭐⭐ (Low-Med) |
| Protocol | Modify | ~20 | 5 | ⭐ (Trivial) |
| **TOTAL** | - | **~670** | **140** | **Medium** |

### Dependencies

**Unchanged**:
- erlexec (existing)
- jason (existing)
- All test dependencies (existing)

**New**: None

### Performance Targets

| Metric | Current | Target | Acceptable |
|--------|---------|--------|------------|
| Router decision | N/A | <0.1ms | <1ms |
| CLI streaming startup | ~200ms | <210ms | <250ms |
| Control client init | ~300ms | <300ms | <350ms |
| Control + streaming | N/A | <350ms | <400ms |
| Memory overhead | N/A | <2KB/session | <10KB/session |

---

## FAQ

### Q: Will this break my existing code?
**A**: No. Zero breaking changes. New behavior is opt-in via `include_partial_messages: true`.

### Q: Do I need to upgrade my Claude CLI?
**A**: Possibly. Day 1 verification will confirm minimum required version. If needed, documentation will specify.

### Q: What if I don't want streaming + tools together?
**A**: Use `preferred_transport: :cli` to force CLI-only (ignores control features) or `preferred_transport: :control` to force control without streaming.

### Q: How do I consume the mixed event/message stream?
**A**: Use `EventAdapter.to_events/1` to normalize, or pattern match on `{:stream_event, ref, event}` vs `{:claude_message, message}`.

### Q: What's the performance impact?
**A**: Router adds <0.1ms (negligible). Control client with streaming adds ~50-150ms to first event vs CLI-only (one-time initialization cost).

### Q: Can I use this in production immediately?
**A**: v0.6.0-rc1 will be beta. v0.6.0 final after 1-2 weeks of community testing. Production use at your discretion.

### Q: What if something goes wrong?
**A**: Fallback: Disable `include_partial_messages` to revert to current behavior. Report issues on GitHub.

---

## Related Documentation

### Existing SDK Docs
- `docs/20251007/06_BIDIRECTIONAL_STREAMING_PLAN.md` - Original streaming plan
- `docs/20251017/gap_analysis/architecture_differences.md` - Python vs Elixir comparison
- `docs/SDK_MCP_STATUS.md` - Current MCP capabilities

### Architecture Docs
- `docs/20251025/STREAMING_WITH_TOOLS_ARCHITECTURE.md` - Target architecture
- `docs/design/hooks_implementation.md` - Hooks system

### Claude CLI Docs
- Claude Code documentation (external)
- `--include-partial-messages` flag documentation
- Control protocol specification

---

## Changelog

### 2025-10-25 - Initial Documentation
- Created comprehensive design documentation suite
- Feasibility assessment approved (85% confidence)
- Timeline estimated at 10-14 days
- All 5 core documents complete:
  - 00_FEASIBILITY_ASSESSMENT.md (57KB)
  - 01_ROUTER_DESIGN.md (24KB)
  - 02_CLIENT_STREAMING_ENHANCEMENTS.md (29KB)
  - 03_STREAMING_FACADE_INTEGRATION.md (13KB)
  - 04_TESTING_STRATEGY.md (19KB)
  - 05_IMPLEMENTATION_ROADMAP.md (25KB)

**Total Documentation**: ~167KB, ~6500 lines

---

## Next Steps

### For Project Approval
1. Review [00_FEASIBILITY_ASSESSMENT](./00_FEASIBILITY_ASSESSMENT.md)
2. Review [05_IMPLEMENTATION_ROADMAP](./05_IMPLEMENTATION_ROADMAP.md)
3. Approve or request changes
4. Schedule Day 1 CLI verification

### For Implementation Kickoff
1. Create feature branch: `feature/streaming-tools-unification`
2. Run pre-implementation checklist (see [05_IMPLEMENTATION_ROADMAP](./05_IMPLEMENTATION_ROADMAP.md))
3. Begin Day 1: CLI verification and router implementation
4. Follow daily roadmap, updating daily standup

### For Questions/Feedback
- Open GitHub issue with `[streaming-tools]` tag
- Contact project maintainer
- Review design docs for clarifications

---

## Authors

- **Feasibility Assessment**: Claude Code + NSHkr
- **Technical Design**: Claude Code + NSHkr
- **Implementation**: TBD

## License

Same as Claude Agent SDK (MIT)

---

**Status**: 🟢 Ready for Implementation
**Confidence**: 85%
**Risk**: LOW-MEDIUM
**Recommendation**: PROCEED with Day 1 gate verification
