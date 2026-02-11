# Erlexec Consolidation R2 Review (claude_agent_sdk)

## Findings

### 1) Missing multi-subscriber burst integrity stress test
- **Severity**: HIGH
- **Area**: Concurrency
- **Description**: Test coverage does not validate that multiple subscribers each receive a full burst stream without loss/duplication under load. Current tests cover one-message fanout and single-subscriber burst independently, but not combined stress.
- **Location**: `test/claude_agent_sdk/transport/erlexec_transport_test.exs:108`
- **Recommendation**: Add a stress test with `N` subscribers and `M` burst lines; assert each subscriber receives exactly `M` unique lines and one exit event.

### 2) Missing finalize-drain responsiveness/starvation test
- **Severity**: MEDIUM
- **Area**: Concurrency
- **Description**: No test equivalent to amp’s large pending-queue finalize test to prove `GenServer.call` remains responsive while `:finalize_exit` re-enters drain cycles.
- **Location**: `test/claude_agent_sdk/transport/erlexec_transport_test.exs:260`
- **Recommendation**: Port amp’s finalize responsiveness scenario (`pending_lines` preloaded, `:finalize_exit` injected, short-timeout `status` call asserted while draining).

### 3) No SIGTERM-ignoring cleanup regression test for stream consumer
- **Severity**: MEDIUM
- **Area**: Shutdown
- **Description**: `CLIStream` implements a force-close/shutdown/kill cascade, but there is no stubborn child process test (ignoring TERM/INT) to prove end-to-end cleanup behavior.
- **Location**: `lib/claude_agent_sdk/query/cli_stream.ex:363`
- **Recommendation**: Add a stream cleanup test mirroring amp’s stubborn process fixture (`trap '' TERM`) and assert process death within bounded time.

### 4) Custom transport guide has conflicting error-shape guidance
- **Severity**: LOW
- **Area**: Doc Mismatch
- **Description**: The guide states transport failures should be `{:error, {:transport, reason}}`, but later recommends returning `{:error, {:transport_failed, reason}}` from `start_link/1`.
- **Location**: `docs/CUSTOM_TRANSPORTS.md:65`
- **Recommendation**: Standardize on one documented error contract and update the conflicting bullet.

## Summary Table

| # | Severity | Area | Description | Location |
|---|----------|------|-------------|----------|
| 1 | HIGH | Concurrency | No multi-subscriber burst integrity test (loss/dup under load unproven) | `test/claude_agent_sdk/transport/erlexec_transport_test.exs:108` |
| 2 | MEDIUM | Concurrency | No finalize-drain responsiveness/starvation test | `test/claude_agent_sdk/transport/erlexec_transport_test.exs:260` |
| 3 | MEDIUM | Shutdown | No SIGTERM-ignoring stream-cleanup regression test | `lib/claude_agent_sdk/query/cli_stream.ex:363` |
| 4 | LOW | Doc Mismatch | Conflicting transport error-shape guidance in custom transport docs | `docs/CUSTOM_TRANSPORTS.md:65` |

## Recommendations for Follow-Up Work

1. Add high-load multi-subscriber transport stress tests (fanout correctness + no duplication).
2. Add finalize/drain responsiveness tests to protect against mailbox starvation regressions.
3. Add stubborn-subprocess cleanup tests for `CLIStream.cleanup/1` (TERM-ignore path).
4. Align custom transport documentation to a single error contract.

## Overall Verdict

**ACCEPT WITH CAVEATS** — No CRITICAL issues found, but one HIGH concurrency coverage gap should be addressed in a follow-up PR.
