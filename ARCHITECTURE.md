# Claude Code SDK for Elixir - Architecture

## Overview

The Claude Code SDK for Elixir is a wrapper around the Claude Code CLI tool. It spawns the `claude` executable as a subprocess and communicates with it via stdin/stdout using JSON messages.

## How It Works

1. **Subprocess Communication**: The SDK uses Elixir's `Port` to spawn the claude CLI tool
2. **Message Streaming**: Communication happens via JSON messages streamed over stdout
3. **Stream Processing**: Results are returned as Elixir Streams for efficient processing

## Key Components

### ClaudeAgentSDK (Main Module)
- Public API for users
- Functions: `query/2`, `continue/2`, `resume/3`
- Returns Streams of Messages

### ClaudeAgentSDK.Options
- Configuration struct for requests
- Converts options to CLI arguments via `to_args/1`

### ClaudeAgentSDK.Message
- Represents messages from Claude
- Types: `:system`, `:user`, `:assistant`, `:result`
- Parses JSON messages from the CLI

### ClaudeAgentSDK.Query
- Orchestrates query execution
- Builds command line arguments
- Handles continue/resume logic

### ClaudeAgentSDK.Process
- Manages subprocess lifecycle
- Spawns claude CLI via Port
- Streams and parses JSON output
- Handles buffering and line parsing

## Message Flow

```
User Code -> ClaudeAgentSDK.query/2
          -> Query.run/2
          -> Process.stream/2
          -> Port.open (spawns claude CLI)
          -> Parse JSON messages
          -> Return Stream of Messages
```

## CLI Integration

The SDK requires the Claude Code CLI to be installed via npm:
```bash
npm install -g @anthropic-ai/claude-code
```

The SDK then spawns this CLI with arguments like:
```bash
claude --print --output-format stream-json "Your prompt here"
```

## Authentication

Authentication is handled by the Claude CLI itself through environment variables:
- `ANTHROPIC_API_KEY` - For direct Anthropic API access
- `CLAUDE_AGENT_USE_BEDROCK=1` - For AWS Bedrock
- `CLAUDE_AGENT_USE_VERTEX=1` - For Google Vertex AI

## Stream Processing

The SDK uses Elixir's Stream module for lazy evaluation:
- Messages are yielded as they arrive from the CLI
- No buffering of entire response in memory
- Allows for real-time processing of Claude's responses

## Error Handling

- CLI not found: Raises error with installation instructions
- API key missing: Handled by the CLI tool
- Parse errors: Logged but processing continues
- Subprocess crashes: Stream terminates gracefully