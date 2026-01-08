defmodule Mix.Tasks.Chat do
  @moduledoc """
  A streaming chat Mix task that demonstrates real-time Claude responses.

  ## Usage

      # Single prompt (streaming response)
      mix chat "What is the capital of France?"

      # Interactive multi-turn conversation
      mix chat --interactive

      # Specify model
      mix chat --model sonnet "Explain recursion"

      # Allow Claude to use tools
      mix chat --tools "List the files in this directory"

  ## Options

    * `--interactive`, `-i` - Start an interactive multi-turn chat session
    * `--model`, `-m` - Model to use: haiku, sonnet, or opus (default: haiku)
    * `--tools`, `-t` - Allow Claude to use tools (Read, Bash, etc.)
    * `--max-turns` - Maximum conversation turns (default: 10)

  ## Examples

      # Quick question with streaming output
      $ mix chat "What is 2 + 2?"
      The answer is 4.

      # Interactive session
      $ mix chat -i
      You: What's your name?
      Claude: I'm Claude, an AI assistant made by Anthropic.
      You: Tell me a joke
      Claude: Why do programmers prefer dark mode? ...
      You: /quit

  """
  use Mix.Task

  alias ClaudeAgentSDK.{Options, Streaming}

  @shortdoc "Chat with Claude using streaming responses"

  @switches [
    interactive: :boolean,
    model: :string,
    tools: :boolean,
    max_turns: :integer
  ]

  @aliases [
    i: :interactive,
    m: :model,
    t: :tools
  ]

  @impl Mix.Task
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:claude_agent_sdk)

    {opts, remaining, _invalid} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    model = opts[:model] || "haiku"
    max_turns = opts[:max_turns] || 10
    allow_tools = opts[:tools] || false
    interactive = opts[:interactive] || false

    options = build_options(model, max_turns, allow_tools)

    cond do
      interactive ->
        run_interactive(options)

      remaining != [] ->
        prompt = Enum.join(remaining, " ")
        run_single_prompt(options, prompt)

      true ->
        Mix.shell().info(@moduledoc)
    end
  end

  defp build_options(model, max_turns, allow_tools) do
    allowed_tools =
      if allow_tools do
        ["Read", "Glob", "Grep", "Bash", "Write", "Edit"]
      else
        []
      end

    %Options{
      model: model,
      max_turns: max_turns,
      allowed_tools: allowed_tools,
      include_partial_messages: true
    }
  end

  defp run_single_prompt(options, prompt) do
    case Streaming.start_session(options) do
      {:ok, session} ->
        try do
          stream_response(session, prompt)
        after
          Streaming.close_session(session)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to start session: #{inspect(reason)}")
    end
  end

  defp run_interactive(options) do
    Mix.shell().info("""
    Starting interactive chat session...
    Commands:
      /quit or /exit - End the session
      /clear - Clear conversation (start fresh)

    """)

    case Streaming.start_session(options) do
      {:ok, session} ->
        try do
          interactive_loop(session, options)
        after
          Streaming.close_session(session)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to start session: #{inspect(reason)}")
    end
  end

  defp interactive_loop(session, options) do
    case IO.gets("You: ") do
      :eof ->
        Mix.shell().info("\nGoodbye!")

      {:error, _reason} ->
        Mix.shell().info("\nGoodbye!")

      input ->
        prompt = String.trim(input)

        case prompt do
          "" ->
            interactive_loop(session, options)

          cmd when cmd in ["/quit", "/exit"] ->
            Mix.shell().info("Goodbye!")

          "/clear" ->
            Mix.shell().info("Starting fresh session...\n")
            Streaming.close_session(session)

            case Streaming.start_session(options) do
              {:ok, new_session} ->
                interactive_loop(new_session, options)

              {:error, reason} ->
                Mix.shell().error("Failed to restart: #{inspect(reason)}")
            end

          _ ->
            IO.write("Claude: ")
            stream_response(session, prompt)
            IO.puts("")
            interactive_loop(session, options)
        end
    end
  end

  defp stream_response(session, prompt) do
    session
    |> Streaming.send_message(prompt)
    |> Stream.each(fn
      %{type: :text_delta, text: text} ->
        IO.write(text)

      %{type: :tool_use_start, name: tool_name} ->
        IO.write("\n[Using #{tool_name}...] ")

      %{type: :tool_complete} ->
        IO.write("[Done]\n")

      %{type: :message_stop} ->
        IO.puts("")

      %{type: :error, error: reason} ->
        Mix.shell().error("\nError: #{inspect(reason)}")

      _event ->
        :ok
    end)
    |> Stream.run()
  end
end
