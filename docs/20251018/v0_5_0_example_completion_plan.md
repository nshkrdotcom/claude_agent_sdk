# v0.5.0 Working Examples Completion Plan

## 1. Purpose
Create production-ready, CLA-deployable examples that demonstrate every major runtime control and transport capability introduced in v0.5.0. These scripts must run without manual tweaking, rely on deterministic transports where practical, and include automated validation so regressions are caught before release.

## 2. Scope
Covered features:

- Runtime model switching (`Client.set_model/2`, broadcast propagation)
- Transport abstraction (`ClaudeAgentSDK.Transport` behaviour, default port transport, mock/test transport)
- Supertester-driven deterministic testing pipeline
- Control protocol helpers (`encode_set_model_request/2`, `decode_set_model_response/1`)
- Options surface changes (`transport`, `transport_opts`, runtime control hooks)

Out of scope:

- MCP hybrid query system (already demoed in v0.4.x examples)
- Live CLI UI polishing (tracked separately in 20251017/LIVE_EXAMPLES_STATUS.md)

## 3. Deliverables

| Deliverable | Description | Validation Strategy |
|-------------|-------------|---------------------|
| `examples/runtime_control/model_switcher.exs` | Minimal script that switches models mid-conversation and prints annotated output. | Deterministic run via `mix run.live` with mock transport; asserts success frames. |
| `examples/runtime_control/transport_swap.exs` | Demonstrates swapping between port transport and custom mock transport within a single session. | Supertester case exercises both transports and asserts message routing. |
| `examples/runtime_control/subscriber_broadcast.exs` | Shows multiple subscribers receiving control + content events during model change. | ExUnit doc test capturing subscriber messages; CLI smoke test optional. |
| `examples/testing/supertester_model_switch_case.exs` | Standalone test module showing Supertester usage with mock transport. | Runs via `mix test examples/testing/supertester_model_switch_case.exs`. |
| README section update | Step-by-step guide linking to the above scripts, with copy-paste commands. | Manual review + `mix docs` preview. |
| CI script entry | `test_all_examples.sh` additions to cover new runtime control examples (mock mode + optional live path). | Shell script dry run in CI container. |

## 4. Current State Assessment

1. **Inventory existing examples**  
   - `examples/basic_example.exs`, `simple_analyzer.exs`, etc., do not cover runtime control.
   - No scripts call `Client.set_model/2` or demonstrate multiple transports.
   - `test/support` contains a mock transport usable for deterministic flows.

2. **Gaps**  
   - No automation to validate model switching end-to-end.  
   - Documentation references runtime control but lacks runnable scripts.  
   - `test_all_examples.sh` has placeholders for v0.5.0 flows but not actual commands.

## 5. Workstreams & Tasks

### WS1 – Example Design & Prototyping
1. Draft flow charts for each example (input/output expectations, error handling).  
2. Define required helper modules (e.g., subscriber capture helper).  
3. Decide on transport injection strategy (Port vs Mock vs Hybrid).

### WS2 – Implementation
1. Implement scripts under `examples/runtime_control/`.  
2. Add inline comments where flow is non-obvious (e.g., transport swap boundaries).  
3. Ensure scripts default to mock transport and accept `--live` flag for CLI usage.

### WS3 – Automated Validation
1. Convert scripts into ExUnit-powered smoke tests using Supertester.  
2. Integrate with `mix test --include integration` where live CLI is necessary.  
3. Add assertions for model-change acknowledgement frames and subscriber broadcasts.

### WS4 – Documentation & Tooling Updates
1. Update README runtime control section with quick-start commands.  
2. Add cross-links in `docs/RUNTIME_CONTROL.md` and `docs/MIGRATION_V0_5.md`.  
3. Extend `test_all_examples.sh` to run new examples in mock mode by default.  
4. Update HexDocs extras if new guides are required.

### WS5 – Review & Sign-off
1. Peer review scripts for clarity and determinism.  
2. Run `mix credo --strict`, `mix dialyzer`, `mix test`, and targeted example tests.  
3. Capture CLI transcript for optional live demo (if CLI login available).  
4. Prepare final checklist before merging.

## 6. Milestones & Timeline (estimate)

- **Day 1:** WS1 complete, prototypes stubbed.  
- **Day 2:** WS2 implementation for model switcher + transport swap; initial tests pass.  
- **Day 3:** WS3 automation + README updates.  
- **Day 4:** Remaining docs, CI script adjustments, final validation.  
- **Day 5:** Review feedback, polish, merge.

## 7. Success Criteria

- All scripts run with `mix run.live` using mock transport without edits.  
- Integration flag `--live` (or env var) seamlessly switches to port transport.  
- Tests cover model change acknowledgement and subscriber fan-out.  
- README instructions allow a new user to replicate runtime control flows in <5 minutes.  
- CI regression harness executes new examples (mock mode) on PRs.

## 8. Dependencies

- **Mock transport enhancements** (if any) to simulate control responses.  
- Updated fixtures for control protocol frames.  
- Access to CLI for optional live run verification (document steps even if skipped).

## 9. Risks & Mitigations

- **CLI instability:** Use mock transport as default; gate live runs behind tag.  
- **Flaky timing in examples:** Leverage Supertester `eventually/2` helper; avoid `Process.sleep/1`.  
- **Credo/Dialyzer constraints:** Keep scripts formatting-compliant; add moduledocs where required.  
- **Documentation drift:** Link examples from a single README section to avoid duplication.

## 10. Open Questions

1. Should examples log raw control frames or user-friendly summaries?  
2. How should we expose transport swap configuration (CLI args vs env vars)?  
3. Do we need a Phoenix LiveView demo for runtime control as part of v0.5.0, or defer to v0.5.1?

## 11. Next Actions

1. Schedule design review for example flows (target: tomorrow 10:00 UTC).  
2. Spin up feature branch `feature/v0.5_examples` with initial skeleton scripts.  
3. Prepare mock transport fixtures to simulate CLI model change responses.  
4. Draft README copy aligned with scripts for early feedback.

