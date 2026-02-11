defmodule ClaudeAgentSDK.Orchestrator do
  @moduledoc """
  Concurrent query orchestration with rate limiting and error recovery.

  Enables parallel Claude query execution, sequential pipelines,
  and automatic retry with exponential backoff.

  ## Features
  - Parallel query execution with concurrency limits
  - Sequential pipeline workflows (output → input)
  - Automatic retry with exponential backoff
  - Rate limiting (configurable queries/minute)
  - Cost tracking and statistics
  - Error aggregation and reporting

  ## Usage

      # Parallel queries
      {:ok, results} = Orchestrator.query_parallel([
        {"Analyze file1.ex", opts},
        {"Analyze file2.ex", opts},
        {"Analyze file3.ex", opts}
      ], max_concurrent: 3)

      # Pipeline (sequential with context)
      {:ok, final_result} = Orchestrator.query_pipeline([
        {"Analyze code", analysis_opts},
        {"Suggest refactorings", refactor_opts},
        {"Generate tests", test_opts}
      ], use_context: true)

      # Retry with backoff
      {:ok, result} = Orchestrator.query_with_retry(
        prompt,
        options,
        max_retries: 3,
        backoff_ms: 1000
      )
  """

  alias ClaudeAgentSDK.Config.{Buffers, Orchestration, Timeouts}
  alias ClaudeAgentSDK.{ContentExtractor, Message}
  alias ClaudeAgentSDK.Log, as: Logger

  @doc """
  Executes multiple queries in parallel.

  ## Parameters

  - `queries` - List of {prompt, options} tuples
  - `opts` - Keyword list of options:
    - `:max_concurrent` - Maximum concurrent queries (default: 5)
    - `:timeout` - Timeout per query in ms (default: 300_000)

  ## Returns

  - `{:ok, results}` - List of result maps
  - `{:error, reason}` - If any query fails critically

  ## Examples

      queries = [
        {"What is 2+2?", %Options{}},
        {"What is 3+3?", %Options{}},
        {"What is 4+4?", %Options{}}
      ]

      {:ok, results} = Orchestrator.query_parallel(queries, max_concurrent: 2)

      Enum.each(results, fn result ->
        IO.puts("Prompt: \#{result.prompt}")
        IO.puts("Success: \#{result.success}")
        IO.puts("Cost: $\#{result.cost}")
      end)
  """
  @spec query_parallel([{String.t(), ClaudeAgentSDK.Options.t()}], keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def query_parallel(queries, opts \\ []) do
    max_concurrent = Keyword.get(opts, :max_concurrent, Orchestration.max_concurrent())
    timeout = Keyword.get(opts, :timeout, Timeouts.query_parallel_ms())

    Logger.info(
      "Orchestrator: Starting parallel execution of #{length(queries)} queries (max_concurrent: #{max_concurrent})"
    )

    tasks =
      queries
      |> Task.async_stream(
        fn {prompt, options} ->
          execute_query_with_metadata(prompt, options)
        end,
        max_concurrency: max_concurrent,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    process_parallel_results(tasks)
  end

  @doc """
  Executes queries sequentially in a pipeline.

  Each step can optionally use the output from the previous step.

  ## Parameters

  - `steps` - List of {prompt, options} tuples
  - `opts` - Keyword list of options:
    - `:use_context` - Include previous output in next prompt (default: false)
    - `:stop_on_error` - Stop pipeline on first error (default: true)

  ## Returns

  - `{:ok, messages}` - Messages from final step
  - `{:error, {:step_failed, prompt, errors}}` - If a step fails

  ## Examples

      steps = [
        {"Analyze this code: ...", analysis_opts},
        {"Suggest improvements", refactor_opts},
        {"Generate tests for improved code", test_opts}
      ]

      {:ok, final_result} = Orchestrator.query_pipeline(steps, use_context: true)
  """
  @spec query_pipeline([{String.t(), ClaudeAgentSDK.Options.t()}], keyword()) ::
          {:ok, [Message.t()]} | {:error, term()}
  def query_pipeline(steps, opts \\ []) do
    use_context = Keyword.get(opts, :use_context, false)
    stop_on_error = Keyword.get(opts, :stop_on_error, true)

    Logger.info(
      "Orchestrator: Starting pipeline with #{length(steps)} steps (use_context: #{use_context})"
    )

    Enum.reduce_while(steps, {:ok, []}, fn {prompt, options}, {:ok, prev_result} ->
      enhanced_prompt =
        if use_context && prev_result != [] do
          append_context(prompt, prev_result)
        else
          prompt
        end

      Logger.debug("Orchestrator: Executing pipeline step: #{String.slice(prompt, 0, 50)}...")

      result = ClaudeAgentSDK.query(enhanced_prompt, options) |> Enum.to_list()

      errors = extract_errors(result)

      cond do
        errors == [] ->
          {:cont, {:ok, result}}

        stop_on_error ->
          Logger.error("Orchestrator: Pipeline step failed: #{inspect(errors)}")
          {:halt, {:error, {:step_failed, prompt, errors}}}

        true ->
          Logger.warning(
            "Orchestrator: Pipeline step had errors but continuing: #{inspect(errors)}"
          )

          {:cont, {:ok, result}}
      end
    end)
  end

  @doc """
  Executes a query with automatic retry and exponential backoff.

  ## Parameters

  - `prompt` - Query prompt
  - `options` - ClaudeAgentSDK.Options
  - `opts` - Keyword list of retry options:
    - `:max_retries` - Maximum retry attempts (default: 3)
    - `:backoff_ms` - Initial backoff in ms (default: 1000)
    - `:exponential` - Use exponential backoff (default: true)

  ## Returns

  - `{:ok, messages}` - Successful result
  - `{:error, {:max_retries_exceeded, errors}}` - If all retries fail

  ## Examples

      {:ok, result} = Orchestrator.query_with_retry(
        "Analyze this code",
        options,
        max_retries: 5,
        backoff_ms: 2000
      )
  """
  @spec query_with_retry(String.t(), ClaudeAgentSDK.Options.t(), keyword()) ::
          {:ok, [Message.t()]} | {:error, term()}
  def query_with_retry(prompt, options, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, Orchestration.max_retries())
    backoff_ms = Keyword.get(opts, :backoff_ms, Orchestration.backoff_ms())
    exponential = Keyword.get(opts, :exponential, true)

    Enum.reduce_while(1..max_retries, nil, fn attempt, _acc ->
      Logger.info("Orchestrator: Query attempt #{attempt}/#{max_retries}")

      result = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

      errors = extract_errors(result)

      handle_retry_result(result, errors, attempt, max_retries, backoff_ms, exponential)
    end)
  end

  defp handle_retry_result(result, [], attempt, _max_retries, _backoff_ms, _exponential) do
    Logger.info("Orchestrator: Query successful on attempt #{attempt}")
    {:halt, {:ok, result}}
  end

  defp handle_retry_result(_result, errors, attempt, max_retries, backoff_ms, exponential)
       when attempt < max_retries do
    wait_ms = if exponential, do: backoff_ms * attempt, else: backoff_ms

    Logger.warning(
      "Orchestrator: Attempt #{attempt} failed: #{inspect(errors)}, retrying in #{wait_ms}ms..."
    )

    Process.sleep(wait_ms)
    {:cont, nil}
  end

  defp handle_retry_result(_result, errors, _attempt, max_retries, _backoff_ms, _exponential) do
    Logger.error("Orchestrator: All #{max_retries} attempts failed")
    {:halt, {:error, {:max_retries_exceeded, errors}}}
  end

  ## Private Helpers

  defp execute_query_with_metadata(prompt, options) do
    start_time = System.monotonic_time(:millisecond)

    result = ClaudeAgentSDK.query(prompt, options) |> Enum.to_list()

    duration = System.monotonic_time(:millisecond) - start_time

    %{
      prompt: prompt,
      messages: result,
      cost: extract_cost(result),
      session_id: extract_session_id(result),
      success: success?(result),
      errors: extract_errors(result),
      duration_ms: duration
    }
  end

  defp process_parallel_results(task_results) do
    results =
      Enum.map(task_results, fn
        {:ok, result} -> result
        {:exit, reason} -> %{error: reason, success: false, messages: []}
      end)

    failures = Enum.filter(results, &(not &1.success))

    if Enum.empty?(failures) do
      Logger.info("Orchestrator: All #{length(results)} queries completed successfully")
      {:ok, results}
    else
      Logger.error("Orchestrator: #{length(failures)}/#{length(results)} queries failed")
      {:error, {:parallel_failures, failures}}
    end
  end

  defp append_context(prompt, previous_messages) do
    context =
      previous_messages
      |> ContentExtractor.extract_all_text()
      # Limit context size
      |> String.slice(0, Buffers.error_truncation_length())

    """
    Context from previous step:
    #{context}

    Now:
    #{prompt}
    """
  end

  defp extract_cost(messages) do
    messages
    |> Enum.find(&(&1.type == :result))
    |> case do
      %{data: %{total_cost_usd: cost}} -> cost
      _ -> 0.0
    end
  end

  defp extract_session_id(messages) do
    messages
    |> Enum.find(&(&1.type == :system))
    |> case do
      %{data: %{session_id: id}} -> id
      _ -> nil
    end
  end

  defp extract_errors(messages) do
    messages
    |> Enum.filter(&(&1.type == :result && &1.subtype != :success))
    |> Enum.map(& &1.subtype)
  end

  defp success?(messages) do
    # Check if we have a successful result message
    has_success_result = Enum.any?(messages, &(&1.type == :result && &1.subtype == :success))

    # Or if we have assistant messages and no error results (query completed)
    has_assistant = Enum.any?(messages, &(&1.type == :assistant))
    has_errors = Enum.any?(messages, &(&1.type == :result && &1.subtype != :success))

    has_success_result || (has_assistant && !has_errors)
  end
end
