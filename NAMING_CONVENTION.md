# Naming Convention & Terminology

This document clarifies the naming conventions used throughout this project.

## Two Distinct Entities

### 1. **Claude Code** (External CLI Tool)
- **What it is**: The official CLI tool from Anthropic for interacting with Claude AI
- **Installation**: `npm install -g @anthropic-ai/claude-code`
- **Executable name**: `claude` or `claude-code`
- **Purpose**: Provides command-line access to Claude AI with various tools
- **Authentication**: `claude login`
- **References in code**:
  - `path_to_claude_code_executable` - path to the Claude Code CLI executable
  - "Claude Code CLI" in documentation
  - Environment variables were intentionally NOT renamed (still use Claude Code naming)

### 2. **Claude Agent SDK** (This Elixir Library)
- **What it is**: An Elixir SDK that wraps and controls the Claude Code CLI
- **Package name**: `claude_agent_sdk`
- **Module name**: `ClaudeAgentSdk` / `ClaudeAgentSDK`
- **App name**: `:claude_agent_sdk`
- **Purpose**: Programmatic Elixir interface to Claude Code CLI
- **Installation**: Add `{:claude_agent_sdk, "~> 0.2.1"}` to mix.exs
- **Environment variables**:
  - `CLAUDE_AGENT_OAUTH_TOKEN` - OAuth token for the SDK
  - `CLAUDE_AGENT_USE_BEDROCK` - Enable AWS Bedrock provider
  - `CLAUDE_AGENT_USE_VERTEX` - Enable Google Vertex AI provider

## Terminology Guidelines

### ✅ Correct Usage

| Context | Term to Use | Example |
|---------|-------------|---------|
| Referring to the external CLI | "Claude Code CLI" or "Claude Code" | "This SDK requires the Claude Code CLI to be installed" |
| Referring to this library | "Claude Agent SDK" | "The Claude Agent SDK provides a simple interface" |
| Authentication command | `claude login` | "Run `claude login` to authenticate" |
| NPM package | `@anthropic-ai/claude-code` | "Install via npm install -g @anthropic-ai/claude-code" |
| This library's modules | `ClaudeAgentSDK.*` | "Use `ClaudeAgentSDK.query/2` to make requests" |
| This library's package | `:claude_agent_sdk` | "Add {:claude_agent_sdk, ...} to deps" |
| Environment variables | `CLAUDE_AGENT_*` | "Set CLAUDE_AGENT_OAUTH_TOKEN for authentication" |
| Executable path option | `path_to_claude_code_executable` | "Specify custom path to Claude Code CLI" |

### ❌ Avoid

- Don't say "Claude Agent CLI" (the CLI is Claude Code)
- Don't say "Claude Code SDK" (the SDK is Claude Agent SDK)
- Don't use `CLAUDE_CODE_*` env vars (changed to `CLAUDE_AGENT_*`)
- Don't confuse the two: the SDK wraps the CLI, they are separate tools

## Architecture

```
┌─────────────────────────────┐
│   Your Elixir Application   │
│                             │
│  Uses: Claude Agent SDK     │
│  (This Library)             │
└──────────────┬──────────────┘
               │
               │ spawns & controls
               ▼
┌─────────────────────────────┐
│     Claude Code CLI         │
│     (External Tool)         │
│                             │
│  Installed via npm          │
│  Auth: claude login         │
└──────────────┬──────────────┘
               │
               │ HTTPS
               ▼
┌─────────────────────────────┐
│      Claude API             │
│      (Anthropic)            │
└─────────────────────────────┘
```

## Summary

- **Claude Code** = The CLI tool we control
- **Claude Agent SDK** = This Elixir library that controls it

This naming makes it clear that:
1. The SDK is for building AI agents using Claude
2. The SDK wraps and manages the Claude Code CLI
3. They are two separate but complementary tools
