# Implementation Guide: Port Python SDK 0434749 → 3eb12c5

**Date**: 2025-12-20

This document provides step-by-step instructions for implementing the port from Python SDK commit `0434749` to `3eb12c5`.

## Overview

The changes are minimal - only CLI version bumps. This port updates the recommended Claude CLI version from `2.0.72` to `2.0.74`.

## File Changes

### 1. lib/claude_agent_sdk/cli.ex

**Location**: Line 13

**Current**:
```elixir
@recommended_version "2.0.72"
```

**Target**:
```elixir
@recommended_version "2.0.74"
```

**Diff**:
```diff
-  @recommended_version "2.0.72"
+  @recommended_version "2.0.74"
```

### 2. mix.exs

**Location**: Line 4

**Current**:
```elixir
@version "0.6.7"
```

**Target**:
```elixir
@version "0.6.8"
```

**Diff**:
```diff
-  @version "0.6.7"
+  @version "0.6.8"
```

### 3. README.md

**Location 1**: Line 78 (CLI version reference)

**Current**:
```markdown
* Recommended version: `2.0.72`
```

**Target**:
```markdown
* Recommended version: `2.0.74`
```

**Location 2**: Line 99 (dependency version)

**Current**:
```elixir
{:claude_agent_sdk, "~> 0.6.7"}
```

**Target**:
```elixir
{:claude_agent_sdk, "~> 0.6.8"}
```

### 5. test/claude_agent_sdk/cli_version_test.exs

**Location**: Line 19-20

**Current**:
```elixir
test "recommended_version is 2.0.72" do
  assert CLI.recommended_version() == "2.0.72"
end
```

**Target**:
```elixir
test "recommended_version is 2.0.74" do
  assert CLI.recommended_version() == "2.0.74"
end
```

**Diff**:
```diff
-    test "recommended_version is 2.0.72" do
-      assert CLI.recommended_version() == "2.0.72"
+    test "recommended_version is 2.0.74" do
+      assert CLI.recommended_version() == "2.0.74"
```

### 6. CHANGELOG.md

**Location**: After line 8 (after `## [Unreleased]`)

**Add new section**:
```markdown
## [0.6.8] - 2025-12-20

### Changed

- Bumped recommended Claude CLI version from 2.0.72 to 2.0.74

### Python SDK Parity

- Ports CLI version bumps from Python SDK commits 57e8b6e and 3eb12c5
- Tracks bundled CLI version 2.0.74 (matching Python SDK v0.1.18)
```

## Verification

### Test Commands

```bash
# 1. Run full test suite
mix test

# 2. Verify CLI version constant
mix run -e 'IO.puts("Recommended: #{ClaudeAgentSDK.CLI.recommended_version()}")'
# Expected output: Recommended: 2.0.74

# 3. Verify minimum version still correct
mix run -e 'IO.puts("Minimum: #{ClaudeAgentSDK.CLI.minimum_version()}")'
# Expected output: Minimum: 2.0.0

# 4. Verify package version
mix run -e 'IO.puts("Version: #{Mix.Project.config()[:version]}")'
# Expected output: Version: 0.6.8

# 5. Run dialyzer (optional)
mix dialyzer
```

### Expected Test Results

All existing tests should pass. Key tests to verify:

- `test/claude_agent_sdk/cli_test.exs` - CLI discovery and version functions
- Any tests that check `recommended_version/0`

## Commit Message

Use the following conventional commit message:

```
chore: bump CLI version to 2.0.74 and release v0.6.8

- Update recommended_version from 2.0.72 to 2.0.74
- Bump package version from 0.6.7 to 0.6.8
- Update README.md version references
- Add CHANGELOG.md entry for 2025-12-20

Ports Python SDK commits:
- 57e8b6e: bump bundled CLI version to 2.0.73
- 3eb12c5: bump bundled CLI version to 2.0.74

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Post-Implementation

After implementing and committing:

1. **Git tag**: `git tag v0.6.8`
2. **Push**: `git push origin main --tags`
3. **Hex publish** (if applicable): `mix hex.publish`

## Rollback Plan

If issues arise, revert with:
```bash
git revert HEAD
```

The only functional change is a version constant, so rollback is low risk.
