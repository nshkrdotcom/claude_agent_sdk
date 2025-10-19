# Phase 9 Prompt – Release Prep & Quality Checks

## Required Reading

- **README.md** – Updated feature overview (runtime control + transport abstraction) for high-level positioning.
- **docs/MIGRATION_V0_5.md** – Migration checklist outlining version, dependency, and API changes relevant to release notes.
- **docs/RUNTIME_CONTROL.md** – Detailed behaviour of `Client.set_model/2`, transport options, and runtime guarantees.
- **docs/CUSTOM_TRANSPORTS.md** – Expectations for the `ClaudeAgentSDK.Transport` behaviour and guidance for integrators.
- **lib/claude_agent_sdk/client.ex** – Source of runtime control logic (state fields, `set_model/2`, pending request handling).
- **lib/claude_agent_sdk/control_protocol/protocol.ex** – Encoding/decoding helpers for control frames.
- **lib/claude_agent_sdk/transport.ex** & **lib/claude_agent_sdk/transport/port.ex** – Transport abstraction definitions and default implementation.
- **mix.exs** – Dependency updates (Supertester) and current version tag (still 0.4.0).
- **docs/CHANGELOG.md** (existing file) – Previous release entries to follow formatting conventions.

## Phase 9 Objectives

1. **Static Analysis**
   - Run `mix format` (verify clean).
   - Run `mix credo --strict` and fix any new issues.
   - Run `mix dialyzer` (ensure PLT available via `priv/plts/dialyzer.plt`).
2. **Test Matrix**
   - Execute `mix test` (already green) and any live/integration suites required by CI (e.g., `mix test --include integration` if feasible).
3. **Release Artifacts**
   - Update `CHANGELOG.md` with v0.5.0 entry (highlight runtime control, transport abstraction, Supertester integration).
   - Bump version in `mix.exs` (e.g., `@version "0.5.0"`), regenerate docs badge if used in README.
   - Regenerate docs if part of workflow (`mix docs`) and note any required updates in `doc/` if output committed.
4. **Dependency Audit**
   - Double-check new dependency (`supertester`) scope (`only: :test`) and ensure lockfile is up to date.
5. **Final Verification**
   - Confirm README feature tables align with parity statements (`PYTHON_SDK_COMPARISON.md` already updated).
   - Ensure new documentation files are referenced where appropriate (README quick links, docs index if applicable).
   - Gather release note bullets for GitHub (feature summary, testing completed, migration steps).

## Deliverables Checklist

- [ ] `CHANGELOG.md` entry for v0.5.0.
- [ ] Version bump in `mix.exs` (+ README badges if applicable).
- [ ] Credo & Dialyzer reports clean (document any suppressions).
- [ ] Confirmation that `mix test` passes with new Supertester harness.
- [ ] Optional: prepare draft GitHub release notes referencing runtime control & transport abstractions.
