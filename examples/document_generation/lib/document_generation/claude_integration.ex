defmodule DocumentGeneration.ClaudeIntegration do
  @moduledoc """
  Integration with Claude Agent SDK for AI-powered document generation.

  This module provides the bridge between natural language requests and
  structured document generation. It uses Claude to understand complex
  requirements and generate appropriate document structures.

  ## Example

      alias DocumentGeneration.ClaudeIntegration

      # Generate a budget document with AI assistance
      {:ok, workbook} = ClaudeIntegration.generate_document(
        "Create a monthly budget tracker for a family of 4 with typical expenses",
        type: :budget_tracker
      )

      # Generate with streaming feedback
      ClaudeIntegration.generate_with_streaming(
        "Create a workout plan for marathon training",
        type: :workout_log,
        on_progress: fn msg -> IO.puts(msg) end
      )
  """

  alias ClaudeAgentSDK.{Options, Streaming}
  alias DocumentGeneration.{Excel, Generator}

  require Logger

  @typedoc "Document generation options"
  @type generate_opts :: [
          type: :budget_tracker | :workout_log | :custom,
          model: String.t(),
          max_turns: pos_integer(),
          output_path: String.t()
        ]

  @default_model "haiku"
  @default_max_turns 5

  @doc """
  Generates a document using Claude AI to interpret the request.

  This function sends the request to Claude, parses the response, and
  generates the appropriate Excel document.

  ## Options

    * `:type` - Document type (`:budget_tracker`, `:workout_log`, or `:custom`)
    * `:model` - Claude model to use (default: "haiku")
    * `:max_turns` - Maximum conversation turns (default: 5)
    * `:output_path` - Optional path to save the file

  ## Example

      {:ok, workbook} = ClaudeIntegration.generate_document(
        "Create a monthly budget for January with rent, groceries, and utilities",
        type: :budget_tracker
      )
  """
  @spec generate_document(String.t(), generate_opts()) ::
          {:ok, Excel.workbook()} | {:error, term()}
  def generate_document(prompt, opts \\ []) do
    type = Keyword.get(opts, :type, :custom)
    model = Keyword.get(opts, :model, @default_model)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)

    system_prompt = build_extraction_prompt(type)
    full_prompt = "#{system_prompt}\n\nUser Request: #{prompt}"

    sdk_options = %Options{
      model: model,
      max_turns: max_turns,
      allowed_tools: [],
      system_prompt: system_prompt
    }

    case run_claude_query(full_prompt, sdk_options) do
      {:ok, response} ->
        parse_and_generate(response, type, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a document with streaming progress updates.

  ## Options

  Same as `generate_document/2` plus:

    * `:on_progress` - Function called with progress messages

  ## Example

      ClaudeIntegration.generate_with_streaming(
        "Create a budget for college expenses",
        type: :budget_tracker,
        on_progress: &IO.puts/1
      )
  """
  @spec generate_with_streaming(String.t(), generate_opts()) ::
          {:ok, Excel.workbook()} | {:error, term()}
  def generate_with_streaming(prompt, opts \\ []) do
    type = Keyword.get(opts, :type, :custom)
    model = Keyword.get(opts, :model, @default_model)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)

    system_prompt = build_extraction_prompt(type)

    sdk_options = %Options{
      model: model,
      max_turns: max_turns,
      allowed_tools: [],
      system_prompt: system_prompt,
      include_partial_messages: true
    }

    case Streaming.start_session(sdk_options) do
      {:ok, session} ->
        try do
          response = collect_streaming_response(session, prompt, on_progress)
          parse_and_generate(response, type, opts)
        after
          Streaming.close_session(session)
        end

      {:error, reason} ->
        {:error, {:session_failed, reason}}
    end
  end

  @doc """
  Creates a document interactively through a conversation with Claude.

  This function starts an interactive session where the user can refine
  their requirements through multiple exchanges with Claude.

  ## Example

      ClaudeIntegration.interactive_session(:budget_tracker, fn
        :prompt -> IO.gets("You: ") |> String.trim()
        {:response, text} -> IO.puts("Claude: \#{text}")
        {:document, workbook} -> DocumentGeneration.save(workbook, "budget.xlsx")
      end)
  """
  @spec interactive_session(atom(), (atom() | tuple() -> any())) :: :ok | {:error, term()}
  def interactive_session(type, handler) do
    model = @default_model

    sdk_options = %Options{
      model: model,
      max_turns: 20,
      allowed_tools: [],
      system_prompt: build_interactive_prompt(type),
      include_partial_messages: true
    }

    case Streaming.start_session(sdk_options) do
      {:ok, session} ->
        try do
          run_interactive_loop(session, type, handler)
        after
          Streaming.close_session(session)
        end

      {:error, reason} ->
        {:error, {:session_failed, reason}}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp run_claude_query(prompt, options) do
    response =
      ClaudeAgentSDK.query(prompt, options)
      |> Enum.reduce("", fn msg, acc ->
        case extract_text_from_message(msg) do
          nil -> acc
          text -> acc <> text
        end
      end)

    {:ok, response}
  rescue
    e ->
      Logger.error("Claude query failed: #{inspect(e)}")
      {:error, {:query_failed, e}}
  end

  defp extract_text_from_message(%{type: :assistant, content: content}) when is_list(content) do
    content
    |> Enum.filter(fn
      %{type: :text} -> true
      %{"type" => "text"} -> true
      _ -> false
    end)
    |> Enum.map_join("", fn
      %{text: text} -> text
      %{"text" => text} -> text
      _ -> ""
    end)
  end

  defp extract_text_from_message(_), do: nil

  defp collect_streaming_response(session, prompt, on_progress) do
    session
    |> Streaming.send_message(prompt)
    |> Stream.map(fn event ->
      case event do
        %{type: :text_delta, text: text} ->
          on_progress.("Generating: #{String.slice(text, 0..50)}...")
          text

        %{type: :message_stop} ->
          on_progress.("Generation complete.")
          ""

        _ ->
          ""
      end
    end)
    |> Enum.join("")
  end

  defp run_interactive_loop(session, type, handler) do
    case handler.(:prompt) do
      nil ->
        :ok

      "" ->
        run_interactive_loop(session, type, handler)

      "/done" ->
        :ok

      "/generate" ->
        # Generate document from conversation
        handler.({:response, "Generating document..."})
        :ok

      prompt ->
        response = collect_streaming_response(session, prompt, fn _ -> :ok end)
        handler.({:response, response})
        run_interactive_loop(session, type, handler)
    end
  end

  defp parse_and_generate(response, type, opts) do
    output_path = Keyword.get(opts, :output_path)

    result =
      case type do
        :budget_tracker ->
          parse_budget_response(response)

        :workout_log ->
          parse_workout_response(response)

        :custom ->
          parse_custom_response(response)
      end

    maybe_save_workbook(result, output_path)
  end

  defp maybe_save_workbook({:ok, workbook}, nil), do: {:ok, workbook}

  defp maybe_save_workbook({:ok, workbook}, output_path) do
    case DocumentGeneration.save(workbook, output_path) do
      :ok -> {:ok, workbook}
      error -> error
    end
  end

  defp maybe_save_workbook(error, _output_path), do: error

  defp parse_budget_response(response) do
    # Try to extract structured budget data from Claude's response
    case Generator.parse_budget_spec(response) do
      {:ok, %{categories: [_ | _] = categories}} ->
        workbook = Excel.budget_tracker(categories)
        {:ok, workbook}

      _ ->
        # Fall back to creating a default budget structure
        {:error, :could_not_parse_budget}
    end
  end

  defp parse_workout_response(response) do
    case Generator.parse_workout_spec(response) do
      {:ok, %{workouts: [_ | _] = workouts}} ->
        workbook = Excel.workout_log(workouts)
        {:ok, workbook}

      _ ->
        {:error, :could_not_parse_workouts}
    end
  end

  defp parse_custom_response(_response) do
    # For custom documents, we'd need more sophisticated parsing
    # For now, return an error indicating manual parsing is needed
    {:error, :custom_parsing_not_implemented}
  end

  defp build_extraction_prompt(:budget_tracker) do
    """
    You are a helpful assistant that extracts budget information from user requests.

    When the user describes their budget needs, respond with a structured list of
    budget categories in this exact format:

    Categories:
    - CategoryName: $BudgetAmount budget, $ActualAmount actual

    For example:
    Categories:
    - Housing: $1500 budget, $1450 actual
    - Food: $600 budget, $580 actual
    - Transport: $400 budget, $420 actual

    If actual spending is not mentioned, use the budget amount as actual.
    Be helpful and suggest reasonable budget categories based on the user's context.
    """
  end

  defp build_extraction_prompt(:workout_log) do
    """
    You are a helpful assistant that extracts workout information from user requests.

    When the user describes their workout needs, respond with a structured list of
    workouts in this format:

    Workouts:
    - Date: Exercise, Duration min, Calories cal

    For example:
    - Jan 1: Running, 30 min, 300 cal
    - Jan 2: Weights, 45 min, 200 cal
    - Jan 3: Swimming, 60 min, 400 cal

    Be helpful and suggest reasonable workouts based on the user's goals.
    """
  end

  defp build_extraction_prompt(:custom) do
    """
    You are a helpful assistant that helps create spreadsheet documents.
    Extract structured data from the user's request and format it clearly
    so it can be used to generate an Excel document.
    """
  end

  defp build_interactive_prompt(type) do
    base = build_extraction_prompt(type)

    """
    #{base}

    This is an interactive session. Help the user refine their requirements
    through conversation. Ask clarifying questions if needed.

    When the user types /generate, provide the final structured output.
    """
  end
end
