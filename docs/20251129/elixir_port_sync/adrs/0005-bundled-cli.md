# ADR 0005: Optional Bundled Claude Code CLI for Elixir SDK

- **Status:** Proposed
- **Date:** 2025-11-29
- **Owner:** SDK team

## Context
- Python SDK 0.1.10 bundles the Claude Code CLI inside the wheel and prefers the bundled binary by default, with override options.
- Elixir currently requires a system-installed CLI (`claude` on PATH). For portability and reproducibility, bundling a CLI binary per platform is desirable, especially for CI and constrained environments.
- Risks include larger package size and per-platform distribution complexity on Hex.

## Decision
- Introduce optional bundling support for Elixir:
  - Provide a mix task to download the Claude Code CLI for the host platform and place it under `priv/_bundled/claude*`, with `.gitignore` in place.
  - Update executable resolution to prefer the bundled binary before PATH discovery.
  - Track a CLI version constant in code (e.g., `lib/claude_agent_sdk/cli_version.ex`) to guide downloads and warnings.
- Do not immediately ship bundled binaries in Hex packages; keep bundling as an opt-in developer/CI step initially. Re-evaluate shipping binaries later based on size/feedback.

## Rationale
- Aligns with Python’s ability to run out-of-the-box without manual CLI install.
- Improves reproducibility in CI and air-gapped scenarios when pre-bundled.
- Limits Hex package bloat by making bundling opt-in initially.

## Consequences
- Additional code paths for binary discovery and a new mix task to download/copy binaries.
- CI surface: need tests to ensure bundled-preferred logic works and PATH fallback remains intact.
- Platform-specific handling (Windows `.exe`, macOS/Linux binaries) and executable bit management.

## Implementation Plan
1) **Version tracking**
   - Add `lib/claude_agent_sdk/cli_version.ex` with a string `@cli_version`. Provide a helper to read it.
2) **Bundled discovery**
   - Add a `.gitignore` entry under `priv/_bundled` for `claude*`.
   - Update executable discovery (e.g., in `lib/claude_agent_sdk/process.ex` and any transport equivalents) to: check bundled path first (`priv/_bundled/claude` or `.exe`), then PATH. Log which source is used.
   - Add a minimum-version warning based on `@cli_version` if we detect an older PATH binary and no bundled binary.
3) **Download task**
   - Create `mix claude.bundle_cli` (or similar) that:
     - Reads desired version from CLI arg or `@cli_version`.
     - Downloads via official installer (curl/bash on Unix, PowerShell on Windows).
     - Copies the binary into `priv/_bundled/claude*`, sets execute bits on Unix.
     - Prints size and location; optional `--skip-download` to reuse existing binary.
4) **Packaging stance**
   - Do not include `priv/_bundled/claude*` in Hex package files for now. Document how to bundle before building Hex if we choose to support that path later.
5) **Tests**
   - Unit: executable resolution prefers bundled over PATH, falls back correctly; warns on old PATH binary when no bundle.
   - Task: dry-run download logic with mocks/fakes; integration minimal due to network sensitivity (guard with tags).
6) **Docs**
   - Add README/ops note on optional bundling, mix task usage, version pinning, and size considerations.

## Alternatives Considered
- Ship binaries in Hex by default — rejected for now due to package size, platform complexity, and policy considerations.
- Continue requiring PATH-only CLI — rejected; does not meet parity/repro goals.

## Rollout
- Phase 1: land code/task/tests/docs with opt-in bundling, PATH remains default when no bundle.
- Phase 2 (future): consider including bundled binaries in Hex artifacts based on feedback and size constraints.
