defmodule Mix.Tasks.Ask do
  @moduledoc """
  A simple query Mix task that waits for the complete response.

  Unlike `mix chat` which streams the response in real-time, this task
  waits for Claude to finish and returns the complete response at once.
  This is useful for scripting and automation.

  ## Usage

      # Simple query
      mix ask "What is 2 + 2?"

      # With a specific model
      mix ask --model sonnet "Explain quantum computing"

      # Allow tools for file operations
      mix ask --tools "Read the README.md file and summarize it"

  ## Options

    * `--model`, `-m` - Model to use: haiku, sonnet, or opus (default: haiku)
    * `--tools`, `-t` - Allow Claude to use tools
    * `--json`, `-j` - Output raw JSON response
    * `--quiet`, `-q` - Only output the response text (no headers)

  ## Exit Codes

    * 0 - Success
    * 1 - Error occurred

  ## Scripting Example

      # Use in a shell script
      ANSWER=$(mix ask -q "What is the square root of 144?")
      echo "Claude says: $ANSWER"

  """
  use Mix.Task

  alias ClaudeAgentSDK.Options

  @shortdoc "Ask Claude a question and get a complete response"

  @switches [
    model: :string,
    tools: :boolean,
    json: :boolean,
    quiet: :boolean
  ]

  @aliases [
    m: :model,
    t: :tools,
    j: :json,
    q: :quiet
  ]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:claude_agent_sdk)

    {opts, remaining, _invalid} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if remaining == [] do
      Mix.shell().info(@moduledoc)
    else
      prompt = Enum.join(remaining, " ")
      execute_query(prompt, opts)
    end
  end

  defp execute_query(prompt, opts) do
    model = opts[:model] || "haiku"
    allow_tools = opts[:tools] || false
    json_output = opts[:json] || false
    quiet = opts[:quiet] || false

    allowed_tools =
      if allow_tools do
        ["Read", "Glob", "Grep", "Bash", "Write", "Edit"]
      else
        []
      end

    options = %Options{
      model: model,
      max_turns: 5,
      allowed_tools: allowed_tools
    }

    unless quiet do
      Mix.shell().info("Asking Claude (#{model})...\n")
    end

    case ClaudeAgentSDK.query(prompt, options) do
      {:ok, messages} ->
        handle_success(messages, json_output, quiet)

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp handle_success(messages, json_output, quiet) do
    if json_output do
      messages
      |> Enum.map(&Map.from_struct/1)
      |> Jason.encode!(pretty: true)
      |> Mix.shell().info()
    else
      # Extract the final assistant response text
      response_text =
        messages
        |> Enum.filter(&(&1.role == :assistant))
        |> List.last()
        |> extract_text()

      if quiet do
        # Raw output for scripting
        IO.puts(response_text)
      else
        Mix.shell().info("Claude: #{response_text}")
      end
    end
  end

  defp extract_text(nil), do: "(No response)"

  defp extract_text(message) do
    message.content
    |> Enum.filter(&match?(%{type: :text}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join("\n")
  end
end
