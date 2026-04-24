# Streaming + Tools Examples (v0.6.0)

These examples demonstrate the new streaming + tools unification feature.

## Running the Examples

Simply use `mix run`:

```bash
mix run examples/streaming_tools/basic_streaming_with_hooks.exs
mix run examples/streaming_tools/sdk_mcp_streaming.exs
```

Or from IEx for interactive exploration:

```bash
iex -S mix
iex> StreamingHooksExample.run()
```

## Available Examples

### 1. basic_streaming_with_hooks.exs
Demonstrates streaming with pre-tool hooks for security and monitoring.

```bash
mix run examples/streaming_tools/basic_streaming_with_hooks.exs
```

Features:
- Pre-tool hooks that log tool usage
- Security validation for bash commands
- Typewriter effect with real-time streaming
- Tool execution monitoring

### 2. sdk_mcp_streaming.exs
Shows streaming with SDK MCP servers (in-process tools).

```bash
mix run examples/streaming_tools/sdk_mcp_streaming.exs
```

Features:
- SDK MCP server with calculator tools
- In-process tool execution (no subprocess overhead)
- Mixed event stream handling
- Real-time progress display

### 3. liveview_pattern.exs
Phoenix LiveView integration pattern (pseudo-code reference).

This is not runnable - it shows the recommended pattern for integrating
Claude streaming into a Phoenix LiveView application.

## Key Concepts

### Automatic Transport Selection

The SDK automatically chooses the right transport:

- **CLI-only** (fast): When you have no hooks/MCP/permissions
- **Control client** (full features): When you configure hooks/SDK MCP/permissions

You don't need to configure this - it just works!

### Event Types

Streaming events you'll receive:

- `%{type: :text_delta, text: "..."}` - Character chunks
- `%{type: :tool_use_start, name: "..."}` - Tool execution begins
- `%{type: :tool_complete, result: "..."}` - Tool finished
- `%{type: :message_stop}` - Response complete

See the EventParser and EventAdapter docs for more details.

## Troubleshooting

**Example runs but shows no output**
- The examples connect to the real Claude CLI
- Make sure you're authenticated: `claude --version`
- Output may take a few seconds to appear (Claude is thinking)

**CLI not authenticated**
- Run `claude --version` to check authentication
- Follow Claude CLI setup instructions if needed

**Module not found errors**
- Run `mix compile` first
- Then run the example again
