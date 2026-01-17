# Getting Started with Claude Agent SDK for Elixir

Welcome to the Claude Agent SDK for Elixir! This guide will walk you through setting up your environment, making your first query, and understanding the core patterns you will use throughout your development.

The Claude Agent SDK provides a production-ready Elixir interface to Claude Code, enabling you to build AI-powered tools and automate coding workflows with Claude's capabilities.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Your First Query](#your-first-query)
4. [Understanding the Response Stream](#understanding-the-response-stream)
5. [Common Patterns](#common-patterns)
6. [Next Steps](#next-steps)

---

## Prerequisites

Before you begin, ensure you have the following installed and configured.

### 1. Elixir and Erlang

The SDK requires **Elixir 1.14 or later**. Check your version:

```bash
elixir --version
```

If you need to install or upgrade Elixir, visit [elixir-lang.org/install](https://elixir-lang.org/install.html) or use a version manager like `asdf`:

```bash
asdf install elixir 1.14.5
asdf global elixir 1.14.5
```

### 2. Claude Code CLI

The SDK communicates with Claude through the Claude Code CLI. Install it globally via npm:

```bash
npm install -g @anthropic-ai/claude-code
```

Verify the installation:

```bash
claude --version
```

You should see a version number like `2.1.7` or higher.

### 3. Authentication

You need valid credentials to use Claude. Choose one of these authentication methods:

#### Option A: Interactive Login (Recommended for Development)

Run the login command and follow the prompts:

```bash
claude login
```

This opens a browser for OAuth authentication and stores your credentials locally.

#### Option B: API Key (Recommended for Production)

Set the `ANTHROPIC_API_KEY` environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."
```

Add this to your shell profile (`.bashrc`, `.zshrc`, etc.) for persistence.

#### Option C: OAuth Token (Programmatic Access)

Set the `CLAUDE_AGENT_OAUTH_TOKEN` environment variable:

```bash
export CLAUDE_AGENT_OAUTH_TOKEN="your-oauth-token"
```

### Verify Your Setup

Run a quick test to ensure everything is working:

```bash
claude -p "Say hello"
```

If you see a response from Claude, you are ready to proceed.

---

## Installation

Add `claude_agent_sdk` to your Mix dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:claude_agent_sdk, "~> 0.9.0"}
  ]
end
```

Then fetch the dependency:

```bash
mix deps.get
```

### Compile the Project

```bash
mix compile
```

The SDK is now ready to use in your application.

---

## Your First Query

Let us create a simple example that sends a prompt to Claude and displays the response.

### Minimal Example

Create a file called `hello_claude.exs`:

```elixir
# hello_claude.exs

# Simple query using defaults
ClaudeAgentSDK.query("Say hello in exactly five words.")
|> Enum.each(fn message ->
  case message.type do
    :assistant ->
      IO.puts("Claude says: #{message.data.message["content"]}")

    :result ->
      IO.puts("\nCost: $#{message.data.total_cost_usd}")
      IO.puts("Turns: #{message.data.num_turns}")

    _ ->
      :ok
  end
end)
```

Run it:

```bash
mix run hello_claude.exs
```

You should see output similar to:

```
Claude says: Hello there, nice to meet!

Cost: $0.00025
Turns: 1
```

### Using Options

For more control, use the `Options` struct:

```elixir
# hello_with_options.exs

alias ClaudeAgentSDK.Options

# Configure the query
options = %Options{
  model: "haiku",           # Use Claude Haiku for fast responses
  max_turns: 3,             # Limit conversation turns
  system_prompt: "You are a friendly assistant who speaks concisely."
}

# Run the query
ClaudeAgentSDK.query("What is Elixir best known for?", options)
|> Enum.each(fn message ->
  case message.type do
    :assistant ->
      IO.puts(message.data.message["content"])

    :result ->
      IO.puts("\n---")
      IO.puts("Duration: #{message.data.duration_ms}ms")

    _ ->
      :ok
  end
end)
```

### Using the OptionBuilder

For common configurations, use the pre-built option presets:

```elixir
alias ClaudeAgentSDK.{OptionBuilder, ContentExtractor}

# Use Haiku model preset
options = OptionBuilder.with_haiku()

# Query and extract text
response = ClaudeAgentSDK.query("Explain pattern matching in one sentence.", options)
|> Enum.to_list()

# Extract just the text content
text = response
|> Enum.filter(&(&1.type == :assistant))
|> Enum.map(&ContentExtractor.extract_text/1)
|> Enum.join("\n")

IO.puts(text)
```

---

## Understanding the Response Stream

The `ClaudeAgentSDK.query/2` function returns a **lazy stream** of messages. This design provides:

- **Memory efficiency**: Messages are processed one at a time
- **Real-time output**: Display responses as they arrive
- **Flexibility**: Filter, transform, or collect as needed

### Message Types

Each message in the stream has a `type` field indicating what it represents:

| Type | Description | Key Data Fields |
|------|-------------|-----------------|
| `:system` | Session initialization | `session_id`, `model`, `cwd`, `tools` |
| `:user` | User input echo | `message`, `session_id` |
| `:assistant` | Claude's response | `message` (with `content`), `session_id` |
| `:result` | Final summary | `total_cost_usd`, `duration_ms`, `num_turns` |
| `:stream_event` | Streaming event | `event`, `uuid` |

Note: CLI JSON frames are capped by `max_buffer_size` (default 1MB). If a frame exceeds the limit, the stream terminates with a `CLIJSONDecodeError` result.

### Example: Processing Each Message Type

```elixir
alias ClaudeAgentSDK.Options

options = %Options{model: "haiku", max_turns: 1}

ClaudeAgentSDK.query("Write a haiku about coding.", options)
|> Enum.each(fn message ->
  case message.type do
    :system ->
      IO.puts("[Session started: #{message.data.session_id}]")
      IO.puts("[Model: #{message.data.model}]")

    :user ->
      IO.puts("\n> #{message.data.message}")

    :assistant ->
      IO.puts("\nClaude:")
      IO.puts(message.data.message["content"])

    :result ->
      IO.puts("\n---")
      IO.puts("Completed in #{message.data.duration_ms}ms")
      IO.puts("Cost: $#{Float.round(message.data.total_cost_usd, 6)}")

    _ ->
      :ok
  end
end)
```

### Result Subtypes

The `:result` message includes a `subtype` field indicating how the session ended:

| Subtype | Description |
|---------|-------------|
| `:success` | Normal completion |
| `:error_max_turns` | Max turns limit reached |
| `:error_during_execution` | Error occurred during execution |

Check for errors:

```elixir
result = Enum.find(messages, &(&1.type == :result))

case result.subtype do
  :success ->
    IO.puts("Query completed successfully!")

  :error_max_turns ->
    IO.puts("Warning: Reached maximum turns limit")

  :error_during_execution ->
    IO.puts("Error: #{result.data.error}")
end
```

---

## Common Patterns

These patterns will help you write clean, maintainable code with the SDK.

### Pattern 1: Extract Text from Response

The most common need is extracting the text content from Claude's response:

```elixir
alias ClaudeAgentSDK.{OptionBuilder, ContentExtractor}

def get_claude_response(prompt) do
  OptionBuilder.with_haiku()
  |> then(&ClaudeAgentSDK.query(prompt, &1))
  |> Enum.to_list()
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.join("\n")
end

# Usage
response = get_claude_response("What is OTP?")
IO.puts(response)
```

### Pattern 2: Handle Errors Gracefully

Always handle potential errors in your queries:

```elixir
alias ClaudeAgentSDK.{Options, Message}

def safe_query(prompt, options \\ %Options{}) do
  try do
    messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

    # Check for errors in assistant messages
    error = Enum.find_value(messages, fn
      %Message{type: :assistant, data: %{error: err}} when not is_nil(err) -> err
      _ -> nil
    end)

    if error do
      {:error, error}
    else
      # Check result subtype
      result = Enum.find(messages, &(&1.type == :result))

      case result do
        %{subtype: :success} ->
          {:ok, messages}

        %{subtype: :error_during_execution, data: %{error: err}} ->
          {:error, err}

        %{subtype: :error_max_turns} ->
          {:error, :max_turns_reached}

        _ ->
          {:ok, messages}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end

# Usage
case safe_query("Hello, Claude!") do
  {:ok, messages} ->
    IO.puts("Success!")

  {:error, reason} ->
    IO.puts("Failed: #{inspect(reason)}")
end
```

### Pattern 3: Collect Session Metadata

Extract useful metadata from the response:

```elixir
alias ClaudeAgentSDK.Session

def query_with_metadata(prompt, options) do
  messages = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

  %{
    session_id: Session.extract_session_id(messages),
    model: Session.extract_model(messages),
    cost: Session.calculate_cost(messages),
    turns: Session.count_turns(messages),
    messages: messages
  }
end
```

### Pattern 4: Resume Conversations

Continue a previous conversation using the session ID:

```elixir
alias ClaudeAgentSDK.{Options, Session}

# First query
options = %Options{model: "haiku", max_turns: 5}
messages1 = ClaudeAgentSDK.query("My name is Alice.", options) |> Enum.to_list()

# Extract session ID
session_id = Session.extract_session_id(messages1)
IO.puts("Session: #{session_id}")

# Resume with follow-up
messages2 = ClaudeAgentSDK.resume(session_id, "What is my name?", options)
|> Enum.to_list()

# Claude remembers: "Your name is Alice."
```

### Pattern 5: Stream with Typewriter Effect

Display responses in real-time as Claude generates them:

```elixir
alias ClaudeAgentSDK.{Options, Streaming}

options = %Options{model: "haiku", max_turns: 1}

{:ok, session} = Streaming.start_session(options)

try do
  Streaming.send_message(session, "Tell me a short joke.")
  |> Enum.each(fn event ->
    case event do
      %{type: :text_delta, text: chunk} ->
        IO.write(chunk)

      %{type: :message_stop} ->
        IO.puts("\n")

      %{type: :error, error: reason} ->
        IO.puts("\nError: #{inspect(reason)}")

      _ ->
        :ok
    end
  end)
after
  Streaming.close_session(session)
end
```

---

## Next Steps

Now that you have the basics, explore these areas to deepen your knowledge:

### Guides and Documentation

- **[Hooks Guide](hooks.md)** - Learn to intercept and control tool execution with hooks
- **[Testing Guide](testing.md)** - Set up deterministic tests with the mock system
- **[Configuration Guide](configuration.md)** - Complete options and configuration reference

### Examples

The `examples/` directory contains runnable demonstrations of all SDK features:

```bash
# Run a single example
mix run examples/basic_example.exs

# Run all examples
bash examples/run_all.sh
```

Key examples to explore:

| Example | Description |
|---------|-------------|
| `basic_example.exs` | Minimal query pattern |
| `session_features_example.exs` | Session persistence and resume |
| `sdk_mcp_tools_live.exs` | Define in-process tools with `deftool` |
| `streaming_tools/quick_demo.exs` | Real-time streaming |
| `hooks/basic_bash_blocking.exs` | Security hooks for tool control |

### Advanced Features

Once comfortable with the basics, explore:

1. **SDK MCP Tools** - Define custom tools that Claude can invoke:
   ```elixir
   defmodule MyTools do
     use ClaudeAgentSDK.Tool

     deftool :add, "Add two numbers", %{
       type: "object",
       properties: %{a: %{type: "number"}, b: %{type: "number"}},
       required: ["a", "b"]
     } do
       def execute(%{"a" => a, "b" => b}) do
         {:ok, %{"content" => [%{"type" => "text", "text" => "#{a + b}"}]}}
       end
     end
   end
   ```

2. **Hooks** - Intercept and control Claude's actions:
   ```elixir
   alias ClaudeAgentSDK.Hooks.{Matcher, Output}

   hooks = %{
     pre_tool_use: [
       Matcher.new("Bash", [fn input, _id, _ctx ->
         # Block dangerous commands
         if String.contains?(input["tool_input"]["command"], "rm -rf") do
           Output.deny("Dangerous command blocked")
         else
           Output.allow()
         end
       end])
     ]
   }

   options = %Options{hooks: hooks}
   ```

3. **Permissions** - Fine-grained tool access control:
   ```elixir
   alias ClaudeAgentSDK.Permission.Result

   callback = fn context ->
     case context.tool_name do
       "Write" -> Result.allow()
       "Bash" -> Result.deny("Bash disabled")
       _ -> Result.allow()
     end
   end

   options = %Options{
     can_use_tool: callback,
     permission_mode: :default
   }
   ```

   `can_use_tool` routes `query/2` through the control client (string or streaming prompts), enables `include_partial_messages`, and is mutually exclusive with `permission_prompt_tool` (the SDK sets it to `"stdio"` internally). Use `:default` for built-in tool permissions.

### Getting Help

- **GitHub Issues**: [github.com/nshkrdotcom/claude_agent_sdk/issues](https://github.com/nshkrdotcom/claude_agent_sdk/issues)
- **Claude Code Documentation**: [docs.anthropic.com/claude-code/sdk](https://docs.anthropic.com/en/docs/claude-code/sdk)

---

## Summary

You have learned how to:

1. Set up your environment with Elixir, Claude CLI, and authentication
2. Install the Claude Agent SDK via Mix
3. Make basic queries and understand the response stream
4. Use common patterns for text extraction, error handling, and streaming
5. Find resources for continued learning

The Claude Agent SDK opens up powerful possibilities for AI-assisted development. Start with simple queries, then gradually explore hooks, tools, and advanced patterns as your needs grow.

Happy coding with Claude!
