# CHANGELOG Entry for v0.6.8

**Date**: 2025-12-20

## Entry to Add

Insert the following after `## [Unreleased]` in `CHANGELOG.md`:

```markdown
## [0.6.8] - 2025-12-20

### Changed

- Bumped recommended Claude CLI version from 2.0.72 to 2.0.74

### Python SDK Parity

- Ports CLI version bumps from Python SDK commits:
  - `57e8b6e`: bump bundled CLI version to 2.0.73
  - `3eb12c5`: bump bundled CLI version to 2.0.74
- Tracks bundled CLI version 2.0.74 (matching Python SDK v0.1.18)
```

## Version Bump Locations

### 1. mix.exs (Line 4)

```diff
-  @version "0.6.7"
+  @version "0.6.8"
```

### 2. README.md (Line 78)

```diff
-* Recommended version: `2.0.72`
+* Recommended version: `2.0.74`
```

### 3. README.md (Line 99)

```diff
-    {:claude_agent_sdk, "~> 0.6.7"}
+    {:claude_agent_sdk, "~> 0.6.8"}
```

### 4. lib/claude_agent_sdk/cli.ex (Line 13)

```diff
-  @recommended_version "2.0.72"
+  @recommended_version "2.0.74"
```

### 5. test/claude_agent_sdk/cli_version_test.exs (Lines 19-20)

```diff
-    test "recommended_version is 2.0.72" do
-      assert CLI.recommended_version() == "2.0.72"
+    test "recommended_version is 2.0.74" do
+      assert CLI.recommended_version() == "2.0.74"
```

## Verification

After making changes:

```bash
# Verify version
mix run -e 'IO.puts(Mix.Project.config()[:version])'
# Expected: 0.6.8

# Verify CLI version
mix run -e 'IO.puts(ClaudeAgentSDK.CLI.recommended_version())'
# Expected: 2.0.74

# Grep to confirm no remaining 0.6.7 references in key files
grep -n "0.6.7" mix.exs README.md CHANGELOG.md
# Should return only CHANGELOG.md historical entries

# Grep to confirm no remaining 2.0.72 in key files
grep -n "2.0.72" lib/claude_agent_sdk/cli.ex README.md
# Should return nothing (historical refs in docs are OK)
```

## Release Notes Template

For GitHub release or Hex.pm:

```markdown
# v0.6.8 - 2025-12-20

## What's Changed

- Updated recommended Claude CLI version to 2.0.74

## Python SDK Parity

This release ports the CLI version tracking from Python SDK v0.1.18:
- Matches bundled CLI version 2.0.74

## Full Changelog

See [CHANGELOG.md](CHANGELOG.md) for complete history.
```
