defmodule SkillInvocation do
  @moduledoc """
  Demonstrates using the Skill tool with the Claude Agent SDK.

  The Skill tool is a built-in Claude Code tool that allows Claude to invoke
  predefined skills. Skills are specialized capabilities that can be loaded
  from project directories or configured via settings.

  ## What are Skills?

  Skills are reusable, domain-specific capabilities that Claude can invoke
  during a conversation. They are defined in `.claude/skills/` directories
  and can include:

    * Document processing (PDF, DOCX, PPTX)
    * Code formatting and analysis
    * Research and literature review
    * Scientific writing assistance
    * And many more specialized capabilities

  ## Skill Tool Parameters

  The Skill tool accepts:

    * `skill` (required) - The skill name or fully qualified name
    * `args` (optional) - Arguments to pass to the skill

  ## Example Usage

      # Start the tracker
      {:ok, tracker} = SkillInvocation.SkillTracker.start_link()

      # Create hooks for tracking
      hooks = SkillInvocation.SkillTracker.create_hooks(tracker)

      # Configure options
      options = %ClaudeAgentSDK.Options{
        model: "haiku",
        allowed_tools: ["Skill", "Bash", "Write"],
        hooks: hooks
      }

      # Run a query that uses skills
      {:ok, client} = ClaudeAgentSDK.Client.start_link(options)

  ## Available Skills

  Use `available_skills/0` to get a list of commonly available skills.
  The actual skills available depend on the Claude installation and
  project configuration.
  """

  alias SkillInvocation.SkillTracker

  @typedoc """
  Skill definition with name and description.
  """
  @type skill_def :: %{
          name: String.t(),
          description: String.t()
        }

  @doc """
  Returns the Skill tool definition as used by Claude Code.

  This shows the structure of the Skill tool that Claude uses to invoke skills.

  ## Examples

      definition = SkillInvocation.skill_tool_definition()
      # => %{
      #   name: "Skill",
      #   description: "Execute a skill within the main conversation...",
      #   input_schema: %{...}
      # }
  """
  @spec skill_tool_definition() :: %{
          name: String.t(),
          description: String.t(),
          input_schema: map()
        }
  def skill_tool_definition do
    %{
      name: "Skill",
      description: """
      Execute a skill within the main conversation.

      When users ask you to perform tasks, check if any of the available skills
      can help complete the task more effectively. Skills provide specialized
      capabilities and domain knowledge.

      When users ask you to run a "slash command" or reference "/<something>"
      (e.g., "/commit", "/review-pr"), they are referring to a skill.
      """,
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "skill" => %{
            "description" => "The skill name. E.g., \"commit\", \"review-pr\", or \"pdf\"",
            "type" => "string"
          },
          "args" => %{
            "description" => "Optional arguments for the skill",
            "type" => "string"
          }
        },
        "required" => ["skill"]
      }
    }
  end

  @doc """
  Returns a list of commonly available skills.

  Note: The actual skills available depend on the Claude installation,
  project configuration, and any custom skills defined in `.claude/skills/`.

  ## Examples

      skills = SkillInvocation.available_skills()
      Enum.each(skills, fn skill ->
        IO.puts("\#{skill.name}: \#{skill.description}")
      end)
  """
  @spec available_skills() :: [skill_def()]
  def available_skills do
    [
      %{
        name: "commit",
        description: "Create a git commit with a descriptive message"
      },
      %{
        name: "review-pr",
        description: "Review a pull request and provide feedback"
      },
      %{
        name: "pdf",
        description: "PDF manipulation toolkit - extract text, merge, split"
      },
      %{
        name: "docx",
        description: "Document toolkit - create/edit DOCX files"
      },
      %{
        name: "pptx",
        description: "Presentation toolkit - create/edit presentations"
      },
      %{
        name: "xlsx",
        description: "Spreadsheet toolkit - create/edit spreadsheets"
      },
      %{
        name: "markitdown",
        description: "Convert files and office documents to Markdown"
      },
      %{
        name: "scientific-writing",
        description: "Write scientific manuscripts with proper structure"
      },
      %{
        name: "literature-review",
        description: "Conduct systematic literature reviews"
      },
      %{
        name: "generate-image",
        description: "Generate images using AI models"
      },
      %{
        name: "research-lookup",
        description: "Look up current research information"
      }
    ]
  end

  @doc """
  Formats a skill invocation for display.

  ## Parameters

    * `skill_name` - The name of the skill
    * `args` - Optional arguments string

  ## Examples

      SkillInvocation.format_skill_invocation("commit", nil)
      # => "Skill: commit"

      SkillInvocation.format_skill_invocation("pdf", "document.pdf")
      # => "Skill: pdf with args: document.pdf"
  """
  @spec format_skill_invocation(String.t(), String.t() | nil) :: String.t()
  def format_skill_invocation(skill_name, nil) do
    "Skill: #{skill_name}"
  end

  def format_skill_invocation(skill_name, "") do
    "Skill: #{skill_name}"
  end

  def format_skill_invocation(skill_name, args) do
    "Skill: #{skill_name} with args: #{args}"
  end

  @doc """
  Parses and validates a skill name.

  Skill names can be:
    * Simple: `"commit"`, `"pdf"`
    * Fully qualified: `"claude-scientific-writer:pdf"`

  ## Examples

      {:ok, "commit"} = SkillInvocation.parse_skill_name("commit")
      {:ok, "writer:pdf"} = SkillInvocation.parse_skill_name("writer:pdf")
      {:error, :empty_skill_name} = SkillInvocation.parse_skill_name("")
  """
  @spec parse_skill_name(String.t() | nil) :: {:ok, String.t()} | {:error, atom()}
  def parse_skill_name(nil), do: {:error, :nil_skill_name}
  def parse_skill_name(""), do: {:error, :empty_skill_name}

  def parse_skill_name(skill_name) when is_binary(skill_name) do
    trimmed = String.trim(skill_name)

    if trimmed == "" do
      {:error, :empty_skill_name}
    else
      {:ok, trimmed}
    end
  end

  @doc """
  Runs a demonstration of skill invocation tracking.

  This function:
  1. Starts a SkillTracker
  2. Simulates skill invocations
  3. Displays tracking results

  ## Options

    * `:verbose` - Print detailed output (default: true)

  ## Examples

      SkillInvocation.run_demo()
  """
  @spec run_demo(keyword()) :: :ok
  def run_demo(opts \\ []) do
    verbose = Keyword.get(opts, :verbose, true)

    if verbose do
      IO.puts("\n=== Skill Invocation Demo ===\n")
    end

    # Start tracker
    {:ok, tracker} = SkillTracker.start_link(name: nil)

    if verbose do
      IO.puts("Started SkillTracker")
    end

    # Simulate some skill invocations
    simulate_invocations(tracker, verbose)

    # Show results
    if verbose do
      show_results(tracker)
    end

    GenServer.stop(tracker)

    :ok
  end

  defp simulate_invocations(tracker, verbose) do
    invocations = [
      {"tool_1", "commit", "-m 'Initial commit'"},
      {"tool_2", "pdf", "document.pdf"},
      {"tool_3", "commit", nil},
      {"tool_4", "markitdown", "report.docx"}
    ]

    for {tool_id, skill, args} <- invocations do
      if verbose do
        IO.puts("  Tracking: #{format_skill_invocation(skill, args)}")
      end

      :ok = SkillTracker.track_skill_invocation(tracker, tool_id, skill, args)
      :ok = SkillTracker.complete_skill_invocation(tracker, tool_id, :success)
    end
  end

  defp show_results(tracker) do
    IO.puts("\n--- Tracking Results ---\n")

    invocations = SkillTracker.get_invocations(tracker)

    IO.puts("Invocations: #{length(invocations)}")

    for inv <- invocations do
      status_icon = if inv.result == :success, do: "[OK]", else: "[ERR]"
      IO.puts("  #{status_icon} #{inv.skill_name} (#{inv.tool_use_id})")
    end

    stats = SkillTracker.get_stats(tracker)

    IO.puts("\nStatistics:")
    IO.puts("  Total: #{stats.total}")

    IO.puts("  By skill:")

    for {skill, count} <- stats.by_skill do
      IO.puts("    #{skill}: #{count}")
    end

    IO.puts("")
  end
end
