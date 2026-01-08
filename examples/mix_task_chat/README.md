# Mix Task Chat Example

> **Note:** This example is available in the [source repository](https://github.com/nshkrdotcom/claude_agent_sdk/tree/main/examples/mix_task_chat) and is not included in the Hex package. Clone the repo to run it locally.

A complete working example demonstrating how to use the Claude Agent SDK in Mix tasks with streaming responses.

## What This Example Shows

- How to create Mix tasks that use the Claude Agent SDK
- Real-time streaming of Claude's responses (typewriter effect)
- Multi-turn interactive conversations
- Simple query-response patterns for scripting
- Command-line argument parsing with options

## Prerequisites

1. **Elixir 1.15+** installed
2. **Claude Code CLI** installed and authenticated:
   ```bash
   # Install Claude Code CLI
   npm install -g @anthropic-ai/claude-code

   # Authenticate (opens browser)
   claude
   ```

## Quick Start

```bash
# Navigate to this example
cd examples/mix_task_chat

# Install dependencies
mix deps.get

# Run a streaming chat
mix chat "What is the capital of France?"

# Start an interactive session
mix chat --interactive
```

## The Two Mix Tasks

### `mix chat` - Streaming Responses

This task streams Claude's response in real-time, character by character:

```bash
# Basic usage - watch the response appear in real-time
mix chat "Explain how photosynthesis works"

# Interactive multi-turn conversation
mix chat --interactive
# or
mix chat -i

# Use a more capable model
mix chat --model sonnet "Write a haiku about Elixir"
mix chat -m opus "Solve this complex problem..."

# Allow Claude to use tools (read files, run commands, etc.)
mix chat --tools "What files are in this directory?"
mix chat -t "Read the mix.exs and explain the dependencies"

# Combine options
mix chat -i -m sonnet -t
```

#### Interactive Mode Commands

When in interactive mode (`-i`), you can use these commands:

- `/quit` or `/exit` - End the session
- `/clear` - Start a fresh conversation (clears context)

### `mix ask` - Complete Responses

This task waits for the full response before displaying it. Useful for scripting:

```bash
# Basic usage
mix ask "What is 2 + 2?"

# Quiet mode - only outputs the response (great for scripts)
mix ask -q "What is the square root of 144?"

# JSON output for programmatic parsing
mix ask -j "List 3 programming languages"

# With tools
mix ask -t "Summarize the README.md file"
```

#### Scripting Example

```bash
#!/bin/bash
# save_summary.sh

SUMMARY=$(cd /path/to/mix_task_chat && mix ask -q -t "Summarize the mix.exs file")
echo "Project Summary: $SUMMARY" > summary.txt
```

## How It Works

### Streaming Architecture

The `mix chat` task uses `ClaudeAgentSDK.Streaming` which:

1. Starts a persistent Claude CLI subprocess
2. Sends prompts via stdin as JSON
3. Receives streaming events via stdout
4. Parses events and displays text deltas in real-time

```
┌─────────────┐     stdin (JSON)      ┌──────────────┐
│  mix chat   │ ───────────────────►  │  Claude CLI  │
│   (Elixir)  │                       │  subprocess  │
│             │ ◄───────────────────  │              │
└─────────────┘   stdout (SSE/JSON)   └──────────────┘
                  ↓
            Parse events
                  ↓
            Display text_delta
            events in real-time
```

### Key Code Walkthrough

#### Starting a Session

```elixir
# In lib/mix/tasks/chat.ex

options = %Options{
  model: "haiku",              # Model to use
  max_turns: 10,               # Max conversation turns
  allowed_tools: [],           # Tools Claude can use
  include_partial_messages: true  # Enable streaming
}

{:ok, session} = Streaming.start_session(options)
```

#### Streaming a Response

```elixir
session
|> Streaming.send_message(prompt)
|> Stream.each(fn
  # Text chunk received - print immediately
  %{type: :text_delta, text: text} ->
    IO.write(text)

  # Tool being used
  %{type: :tool_use_start, name: tool_name} ->
    IO.write("\n[Using #{tool_name}...] ")

  # Tool finished
  %{type: :tool_complete} ->
    IO.write("[Done]\n")

  # Response complete
  %{type: :message_stop} ->
    IO.puts("")

  # Handle errors
  %{type: :error, error: reason} ->
    Mix.shell().error("\nError: #{inspect(reason)}")

  # Ignore other events
  _event ->
    :ok
end)
|> Stream.run()
```

#### Cleanup

```elixir
# Always close the session when done
try do
  stream_response(session, prompt)
after
  Streaming.close_session(session)
end
```

## Creating Your Own Mix Task

Here's a minimal template for your own streaming Mix task:

```elixir
defmodule Mix.Tasks.MyTask do
  use Mix.Task

  alias ClaudeAgentSDK.{Options, Streaming}

  @impl Mix.Task
  def run(args) do
    # Start the SDK application
    Application.ensure_all_started(:claude_agent_sdk)

    prompt = Enum.join(args, " ")

    options = %Options{
      model: "haiku",
      include_partial_messages: true
    }

    {:ok, session} = Streaming.start_session(options)

    try do
      session
      |> Streaming.send_message(prompt)
      |> Stream.each(fn
        %{type: :text_delta, text: text} -> IO.write(text)
        %{type: :message_stop} -> IO.puts("")
        _ -> :ok
      end)
      |> Stream.run()
    after
      Streaming.close_session(session)
    end
  end
end
```

## Event Types Reference

When streaming, you'll receive these event types:

| Event | Description | Fields |
|-------|-------------|--------|
| `:text_delta` | A chunk of text | `text`, `accumulated` |
| `:message_start` | Response beginning | `model`, `role` |
| `:message_stop` | Response complete | `final_text` |
| `:tool_use_start` | Tool invocation started | `name`, `id` |
| `:tool_input_delta` | Tool input being built | `json` |
| `:tool_complete` | Tool finished | `tool_name`, `result` |
| `:thinking_delta` | Extended thinking (Opus) | `thinking` |
| `:error` | An error occurred | `error` |

## Options Reference

```elixir
%Options{
  # Model selection
  model: "haiku",  # "haiku", "sonnet", or "opus"

  # Conversation limits
  max_turns: 10,

  # Tool permissions
  allowed_tools: ["Read", "Glob", "Grep", "Bash", "Write", "Edit"],

  # Streaming control
  include_partial_messages: true,  # Enable character-level streaming

  # Timeouts
  timeout_ms: 300_000,  # 5 minutes

  # Working directory for tools
  cwd: "/path/to/project"
}
```

## Troubleshooting

### "Claude CLI not found"

Make sure Claude Code CLI is installed and in your PATH:

```bash
npm install -g @anthropic-ai/claude-code
which claude  # Should show the path
```

### "Authentication required"

Run `claude` once to authenticate:

```bash
claude
# Follow the browser authentication flow
```

### "No response received"

Check that:
1. You have API credits available
2. The model name is correct (`haiku`, `sonnet`, or `opus`)
3. Your network can reach the Anthropic API

### Streaming not working

Ensure `include_partial_messages: true` is set in your options:

```elixir
options = %Options{
  include_partial_messages: true,  # Required for streaming!
  # ...
}
```

## Files in This Example

```
mix_task_chat/
├── README.md              # This file
├── mix.exs                # Project configuration
└── lib/
    ├── mix_task_chat.ex   # Application module
    └── mix/
        └── tasks/
            ├── chat.ex    # Streaming chat task
            └── ask.ex     # Simple query task
```

## Next Steps

- [Streaming Guide](../../guides/streaming.md) - Advanced streaming patterns
- [Hooks Guide](../../guides/hooks.md) - Tool interception and customization
- [More Examples](../README.md) - Additional example scripts
