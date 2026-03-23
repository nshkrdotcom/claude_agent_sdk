# Erlexec Consolidation R1 Review (claude_agent_sdk)

## Pass 1: Structural Correctness

- **1. Port fully removed from active code/docs scan**: **PASS**
  - Command: `rg -n "Transport\.Port|:port_closed" lib/ test/ README.md guides/ examples/ docs/CUSTOM_TRANSPORTS.md docs/RUNTIME_CONTROL.md`
  - Result: zero hits.
- **2. `default_transport_module` always Erlexec**: **PASS**
  - Verified single-clause implementation at `lib/claude_agent_sdk/client.ex:719`.
- **3. Transport behaviour new callbacks present**: **PASS**
  - `subscribe/3`, `force_close/1`, `stderr/1` present at `lib/claude_agent_sdk/transport.ex:40`, `lib/claude_agent_sdk/transport.ex:49`, `lib/claude_agent_sdk/transport.ex:75`.
- **4. No dead Port alias imports**: **PASS**
  - Command: `rg -n "alias.*Transport\.Port" lib/ test/`
  - Result: zero hits.

## Pass 2: Runtime Correctness (Erlexec)

- **Result**: **PASS** for requested 10 points.
- Evidence:
  - `safe_call/3` async wrapping + timeout: `lib/claude_agent_sdk/transport/erlexec.ex:376`.
  - `send/2` + `end_input/1` async task path with `pending_calls`: `lib/claude_agent_sdk/transport/erlexec.ex:220`, `lib/claude_agent_sdk/transport/erlexec.ex:239`, `lib/claude_agent_sdk/transport/erlexec.ex:223`, `lib/claude_agent_sdk/transport/erlexec.ex:242`.
  - `terminate/2` cancels timers, demonitors, cleans pending calls, force-stops subprocess: `lib/claude_agent_sdk/transport/erlexec.ex:360`.
  - `force_close/1` path and stop+kill: `lib/claude_agent_sdk/transport/erlexec.ex:110`, `lib/claude_agent_sdk/transport/erlexec.ex:257`, `lib/claude_agent_sdk/transport/erlexec.ex:731`.
  - Dual dispatch legacy/tagged: `lib/claude_agent_sdk/transport/erlexec.ex:593`.
  - Queue drain (`:queue`, batch 200, `:drain_stdout`): `lib/claude_agent_sdk/transport/erlexec.ex:32`, `lib/claude_agent_sdk/transport/erlexec.ex:27`, `lib/claude_agent_sdk/transport/erlexec.ex:337`.
  - Finalize delay and re-entrant drain loop: `lib/claude_agent_sdk/transport/erlexec.ex:26`, `lib/claude_agent_sdk/transport/erlexec.ex:303`, `lib/claude_agent_sdk/transport/erlexec.ex:320`.
  - Headless timeout + last-subscriber auto-stop: `lib/claude_agent_sdk/transport/erlexec.ex:347`, `lib/claude_agent_sdk/transport/erlexec.ex:519`.

## Pass 3: Source Parity vs amp_sdk Section 21

- **Result**: **FAIL** (strict parity gaps).
- Matched items:
  - Public API surface present (incl. `start/1`, `subscribe/3`, `force_close/1`, `stderr/1`).
  - Async I/O task pattern, queue drain, finalize timer, headless timeout, shutdown-on-last-subscriber all present.
- Gaps:
  - Struct does not match 15-field checklist; extra fields present (`stderr_callback`, `startup_opts`), yielding divergence from gold-standard state model (`lib/claude_agent_sdk/transport/erlexec.ex:29`).
  - Init is not strictly blocking on low-level subprocess launch due lazy startup mode (`handle_continue/2` subprocess spawn path): `lib/claude_agent_sdk/transport/erlexec.ex:171`, `lib/claude_agent_sdk/transport/erlexec.ex:187`.
  - `safe_call/3` uses local task launcher with `Task.async/1` fallback rather than strict TaskSupport pattern from amp (`lib/claude_agent_sdk/transport/erlexec.ex:410`).

## Pass 4: Documentation Coherence

- **Result**: **PASS**
- Checks:
  - `README.md`/`guides/`/`docs/CUSTOM_TRANSPORTS.md`/`docs/RUNTIME_CONTROL.md` scan showed no `Transport.Port` or `:port_closed` references.
  - `CHANGELOG.md` contains breaking-change entries for Port removal and reason normalization updates (`CHANGELOG.md:12`, `CHANGELOG.md:13`).

## Pass 5: Test Suite + Quality Gates

- **Result**: **FAIL (blocked in environment)**
- Commands attempted:
  - `mix compile --warnings-as-errors`
  - `mix test`
  - `mix credo --strict`
  - `mix dialyzer`
- All failed before project execution with the same environment error:
  - `failed to open a TCP socket in Mix.Sync.PubSub.subscribe/1, reason: :eperm`

## Critical Issues Requiring Rework

1. **Strict parity break: state model diverges from amp 15-field checklist**
   - `lib/claude_agent_sdk/transport/erlexec.ex:29`
2. **Strict parity break: lazy startup path bypasses the "init blocks on subprocess launch" invariant**
   - `lib/claude_agent_sdk/transport/erlexec.ex:171`
   - `lib/claude_agent_sdk/transport/erlexec.ex:187`
3. **Strict parity break: `safe_call` task-start strategy diverges from amp TaskSupport contract**
   - `lib/claude_agent_sdk/transport/erlexec.ex:410`

## Non-Critical Observations

- Runtime transport hardening is materially improved and aligns with amp semantics in most lifecycle/error paths.
- Cleanup cascade in stream consumer is present and monitor-based (`lib/claude_agent_sdk/query/cli_stream.ex:363`).

## Overall Verdict

**REWORK REQUIRED**
