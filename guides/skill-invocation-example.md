# Skill Invocation Example

This example demonstrates using the **Skill tool** with the Claude Agent SDK for Elixir.

## What are Skills?

Skills are specialized, reusable capabilities that Claude can invoke during a conversation. The Skill tool is a built-in Claude Code tool that allows Claude to:

- Execute predefined commands (like `/commit`, `/review-pr`)
- Access domain-specific functionality (PDF processing, document creation)
- Leverage specialized workflows (scientific writing, research lookups)

Skills are loaded from:
1. Project-level `.claude/skills/` directories
2. User-level skill configurations
3. Installed skill packages (like `claude-scientific-writer`)

## How Skills Work

When Claude needs to use a skill, it invokes the Skill tool with:

```json
{
  "skill": "commit",
  "args": "-m 'Fix bug in parser'"
}
```

The Claude CLI then:
1. Locates the skill definition
2. Loads the skill's instructions
3. Executes the skill workflow

## Skill Tool Parameters

| Parameter | Type   | Required | Description                          |
|-----------|--------|----------|--------------------------------------|
| `skill`   | string | Yes      | Skill name (e.g., "commit", "pdf")   |
| `args`    | string | No       | Arguments to pass to the skill       |

## Available Skills

Common built-in skills include:

| Skill Name         | Description                                      |
|--------------------|--------------------------------------------------|
| `commit`           | Create a git commit with a descriptive message   |
| `review-pr`        | Review a pull request and provide feedback       |
| `pdf`              | PDF manipulation - extract, merge, split         |
| `docx`             | Create and edit Word documents                   |
| `pptx`             | Create and edit PowerPoint presentations         |
| `xlsx`             | Create and edit Excel spreadsheets               |
| `markitdown`       | Convert various files to Markdown                |
| `scientific-writing` | Write scientific manuscripts with IMRAD structure |
| `literature-review` | Conduct systematic literature reviews            |
| `generate-image`   | Generate images using AI models                  |

For a complete list, see the Skill tool's available skills in your Claude installation.

## Tracking Skill Invocations

This example includes a `SkillTracker` module that uses hooks to track when Claude invokes skills:

```elixir
# Start the tracker
{:ok, tracker} = SkillInvocation.SkillTracker.start_link()

# Create hooks for tracking
hooks = SkillInvocation.SkillTracker.create_hooks(tracker)

# Configure options with hooks
options = %ClaudeAgentSDK.Options{
  allowed_tools: ["Skill", "Bash", "Write"],
  hooks: hooks
}

# Start client
{:ok, client} = ClaudeAgentSDK.Client.start_link(options)

# ... run queries ...

# Get statistics
stats = SkillInvocation.SkillTracker.get_stats(tracker)
IO.inspect(stats)
# => %{total: 5, by_skill: %{"commit" => 3, "pdf" => 2}}
```

## Running the Demo

```bash
cd examples/skill_invocation
mix deps.get
mix run -e "SkillInvocation.run_demo()"
```

Example output:

```
=== Skill Invocation Demo ===

Started SkillTracker
  Tracking: Skill: commit with args: -m 'Initial commit'
  Tracking: Skill: pdf with args: document.pdf
  Tracking: Skill: commit
  Tracking: Skill: markitdown with args: report.docx

--- Tracking Results ---

Invocations: 4
  [OK] commit (tool_1)
  [OK] pdf (tool_2)
  [OK] commit (tool_3)
  [OK] markitdown (tool_4)

Statistics:
  Total: 4
  By skill:
    commit: 2
    pdf: 1
    markitdown: 1
```

## Running Tests

```bash
cd examples/skill_invocation
mix deps.get
mix test
```

## Hook-Based Tracking

The `SkillTracker` uses Claude Agent SDK hooks to intercept Skill tool invocations:

```elixir
# Pre-tool-use hook - tracks when skill starts
def pre_tool_use_hook(tracker, input, tool_use_id, _context) do
  if input["tool_name"] == "Skill" do
    skill_name = input["tool_input"]["skill"]
    args = input["tool_input"]["args"]
    track_skill_invocation(tracker, tool_use_id, skill_name, args)
  end
  %{}
end

# Post-tool-use hook - tracks when skill completes
def post_tool_use_hook(tracker, input, tool_use_id, _context) do
  if input["tool_name"] == "Skill" do
    is_error = input["tool_response"]["is_error"] || false
    result = if is_error, do: :error, else: :success
    complete_skill_invocation(tracker, tool_use_id, result)
  end
  %{}
end
```

## Integration with Live Claude

To use this with a live Claude session:

```elixir
alias ClaudeAgentSDK.{Client, Options}
alias SkillInvocation.SkillTracker

# Start tracker
{:ok, tracker} = SkillTracker.start_link()

# Create options with skill tracking hooks
options = %Options{
  allowed_tools: ["Skill", "Bash", "Write", "Read"],
  hooks: SkillTracker.create_hooks(tracker),
  model: "sonnet"
}

# Start client
{:ok, client} = Client.start_link(options)

# Send a query that might use skills
Client.send_message(client, "Please create a git commit for the current changes")

# Stream responses
Client.stream_messages(client)
|> Enum.each(fn message ->
  IO.inspect(message, label: "Message")
end)

# Check what skills were used
IO.inspect(SkillTracker.get_stats(tracker), label: "Skill Stats")
```

## Fully Qualified Skill Names

Some skills from packages use fully qualified names:

```
claude-scientific-writer:pdf
claude-scientific-writer:scientific-writing
claude-scientific-writer:literature-review
```

The format is `package-name:skill-name`.

## Related Documentation

- [Claude Code Hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk)
- [Claude Code Skills](https://docs.anthropic.com/en/docs/claude-code/skills)

## License

This example is part of the Claude Agent SDK for Elixir.
