# Research Agent

A multi-agent research coordination example using the Claude Agent SDK for Elixir.

## What This Demonstrates

This example showcases advanced Claude Agent SDK patterns:

- **Multi-Agent Coordination** - Lead agent spawns specialized subagents for parallel work
- **Hook-Based Tracking** - Pre/post tool hooks monitor subagent lifecycle
- **ETS-Backed State** - Concurrent tracking of agent metadata
- **Structured Output** - Research notes, reports, and transcripts
- **Parallel Research** - Multiple researcher agents gather information simultaneously

## Architecture

```
                                    +------------------+
                                    |   User Command   |
                                    |  /research topic |
                                    +--------+---------+
                                             |
                                             v
+-------------------------------------------------------------------------+
|                        ResearchAgent Application                        |
+-------------------------------------------------------------------------+
|                                                                         |
|  +-------------------+     +----------------------+                     |
|  |   Coordinator     |     |    HookCoordinator   |                     |
|  |   (Supervisor)    |     |                      |                     |
|  +--------+----------+     +----------+-----------+                     |
|           |                           |                                 |
|           v                           v                                 |
|  +--------+----------+     +----------+-----------+                     |
|  | SubagentTracker   |<--->|  pre_tool_use hooks  |                     |
|  | (GenServer + ETS) |     |  post_tool_use hooks |                     |
|  +-------------------+     +----------------------+                     |
|           |                                                             |
|           v                                                             |
|  +-------------------+                                                  |
|  | TranscriptLogger  |                                                  |
|  |   (GenServer)     |                                                  |
|  +-------------------+                                                  |
|                                                                         |
+-------------------------------------------------------------------------+
                                             |
                                             v
+-------------------------------------------------------------------------+
|                           Claude Agent SDK                              |
+-------------------------------------------------------------------------+
|                                                                         |
|  +------------------+  +------------------+  +------------------+       |
|  |   Lead Agent     |  |   Task Tool      |  |   WebSearch      |       |
|  |   (Coordinator)  |->|   (Subagents)    |->|   (Research)     |       |
|  +------------------+  +------------------+  +------------------+       |
|                               |                                         |
|                               v                                         |
|  +------------------+  +------------------+  +------------------+       |
|  |   Researcher     |  |   Data Analyst   |  |   Report Writer  |       |
|  |   (Subagent)     |  |   (Subagent)     |  |   (Subagent)     |       |
|  +------------------+  +------------------+  +------------------+       |
|                                                                         |
+-------------------------------------------------------------------------+
```

## Agent Roles

| Agent | Role | Tools Used |
|-------|------|------------|
| **Lead Agent** | Coordinates research, spawns subagents | Task |
| **Researcher** | Gathers information from web sources | WebSearch, Read |
| **Data Analyst** | Extracts metrics and insights | - |
| **Report Writer** | Produces final reports | Write |

## Installation

```bash
cd examples/research_agent
mix deps.get
```

## Usage

### Research Command

Perform comprehensive research on any topic:

```bash
# Basic research
mix research quantum computing applications

# Deep research with detailed output
mix research --depth deep --format detailed artificial intelligence ethics

# Quick overview
mix research --depth quick renewable energy trends
```

**Options:**
- `--depth` / `-d`: Research thoroughness (`quick`, `standard`, `deep`)
- `--format` / `-f`: Output format (`summary`, `detailed`, `comprehensive`)
- `--output-dir` / `-o`: Output directory

### Fact-Check Command

Verify claims with multi-source cross-referencing:

```bash
# Standard fact-check
mix fact_check The Great Wall of China is visible from space

# Thorough verification
mix fact_check --thoroughness high humans only use 10 percent of their brain
```

**Options:**
- `--thoroughness` / `-t`: Verification level (`quick`, `standard`, `high`)
- `--output-dir` / `-o`: Output directory

### Programmatic Usage

```elixir
# Start the application
Application.ensure_all_started(:research_agent)

# Perform research
ResearchAgent.research("climate change impacts",
  depth: :deep,
  format: :comprehensive
)

# Fact-check a claim
ResearchAgent.fact_check("Water boils at 100C at sea level",
  thoroughness: :high
)
```

## Output Organization

```
research_output/
  sessions/
    abc123/
      notes_quantum_computing.md     # Research notes per topic
      notes_applications.md
      report_quantum_computing.md    # Final report
      analysis_results.json          # Structured data
      transcript_abc123_*.json       # Full session transcript
```

## How Subagent Tracking Works

The `SubagentTracker` uses ETS for concurrent tracking of subagent state:

```elixir
# Hooks track Task tool usage
hooks = %{
  pre_tool_use: [
    Matcher.new("*", [&track_spawn/3])
  ],
  post_tool_use: [
    Matcher.new("*", [&track_complete/3])
  ]
}

# When Task tool is called, the hook records the spawn
def track_spawn(input, tool_use_id, _context) do
  case input do
    %{"tool_name" => "Task", "tool_input" => %{"subagent_type" => type}} ->
      SubagentTracker.track_spawn(tracker, tool_use_id, type, metadata)
      Output.allow()
    _ -> %{}
  end
end

# When Task completes, the hook records completion
def track_complete(input, tool_use_id, _context) do
  case input do
    %{"tool_name" => "Task", "tool_response" => result} ->
      SubagentTracker.track_complete(tracker, tool_use_id, result)
    _ -> :ok
  end
  %{}
end
```

## Configuration

Configure via `config/config.exs`:

```elixir
config :research_agent,
  output_dir: "./research_output"
```

Or set at runtime:

```elixir
ResearchAgent.research("topic", output_dir: "/custom/path")
```

## Running Tests

```bash
# Run all tests
mix test

# Run with verbose output
mix test --trace

# Run specific test file
mix test test/research_agent/subagent_tracker_test.exs
```

## Code Quality

```bash
# Format code
mix format

# Run Credo
mix credo --strict

# Run Dialyzer (first run will build PLT)
mix dialyzer

# All quality checks
mix quality
```

## Key SDK Features Demonstrated

### 1. Hook System

```elixir
# Pre-tool hooks for tracking and validation
hooks = %{
  pre_tool_use: [
    Matcher.new("Task", [&track_spawn/3, &audit_log/3])
  ]
}
```

### 2. Task Tool for Subagents

```elixir
# The Task tool enables parallel subagent execution
allowed_tools: ["Task", "WebSearch", "Read", "Write"]
```

### 3. Structured Output

```elixir
# JSON schema for structured responses
output_format: {:json_schema, %{
  type: "object",
  properties: %{
    verdict: %{type: "string"},
    confidence: %{type: "number"}
  }
}}
```

### 4. Session Management

```elixir
# Coordinator manages session lifecycle
{:ok, coord} = Coordinator.start_link(output_dir: dir)
hooks = Coordinator.get_hooks(coord)
```

## Reference

This example is inspired by the Python SDK research agent demo at:
`anthropics/claude-agent-sdk-demos/research-agent/`

The Elixir implementation leverages OTP patterns for:
- Supervised process trees
- ETS for concurrent state
- GenServer for stateful components
- Streams for efficient message processing

## License

MIT License - See the main Claude Agent SDK repository.
