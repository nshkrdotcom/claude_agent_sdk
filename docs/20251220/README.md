# Python SDK Port: 2025-12-20

This directory contains documentation for porting Python Claude Agent SDK changes from commit `0434749` to `3eb12c5` to the Elixir SDK.

## Summary

**Scope**: CLI version bump from 2.0.72 to 2.0.74
**Impact**: Minimal - version constant update only
**Elixir Version**: 0.6.7 → 0.6.8

## Documents

| File | Description |
|------|-------------|
| [00_overview.md](00_overview.md) | Executive summary and porting checklist |
| [01_implementation.md](01_implementation.md) | Step-by-step implementation guide |
| [02_sdk_comparison.md](02_sdk_comparison.md) | Feature parity matrix between Python and Elixir SDKs |
| [03_changelog_entry.md](03_changelog_entry.md) | Changelog entry and version bump details |
| [04_cli_bundling_analysis.md](04_cli_bundling_analysis.md) | Analysis of CLI bundling approaches |

## Quick Start

1. Read `00_overview.md` for the full picture
2. Follow `01_implementation.md` for step-by-step changes
3. Reference `03_changelog_entry.md` for exact file changes

## Changes Required

### Files to Modify

1. **lib/claude_agent_sdk/cli.ex:13** - `@recommended_version "2.0.72"` → `"2.0.74"`
2. **mix.exs:4** - `@version "0.6.7"` → `"0.6.8"`
3. **README.md:78** - `Recommended version: 2.0.72` → `2.0.74`
4. **README.md:99** - `{:claude_agent_sdk, "~> 0.6.7"}` → `"~> 0.6.8"`
5. **test/claude_agent_sdk/cli_version_test.exs:19-20** - Test assertion `"2.0.72"` → `"2.0.74"`
6. **CHANGELOG.md** - Add `[0.6.8] - 2025-12-20` section

## Verification

```bash
# Run tests
mix test

# Check versions
mix run -e 'IO.puts(ClaudeAgentSDK.CLI.recommended_version())'  # 2.0.74
mix run -e 'IO.puts(Mix.Project.config()[:version])'            # 0.6.8
```

## Python SDK Reference

- Python SDK repo: `anthropics/claude-agent-sdk-python`
- Commits ported: `57e8b6e`, `3eb12c5`
- Python version: v0.1.18
