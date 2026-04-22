defmodule ClaudeAgentSDK.Mock.Process do
  @moduledoc """
  Package-local mock process fixture for Claude SDK tests.

  This module is only reachable when package-local test fixture mocking is
  enabled. Instead of spawning actual Claude CLI processes, it retrieves
  predefined responses from the `ClaudeAgentSDK.Mock` server and converts them
  into a stream of `Message` structs.

  It is intentionally not a PRELIM service-mode simulation selector. Cross-stack
  simulation must enter through ASM and the shared `cli_subprocess_core`
  provider runtime profiles so normal provider parsers and execution-surface
  controls still run.

  ## Behavior

  - **Prompt extraction**: Intelligently extracts the relevant prompt from CLI arguments
  - **Response retrieval**: Fetches appropriate mock responses from the Mock server
  - **Stream conversion**: Converts raw mock data into proper `Message` structs
  - **Type preservation**: Maintains the same message types and structure as real CLI output

  ## Message Types Supported

  - `:system` - System initialization and status messages
  - `:assistant` - AI assistant responses with content
  - `:user` - User input messages (for conversation context)
  - `:result` - Final results with cost and performance metrics

  ## Integration

  This module is automatically used only when the test-environment runtime mock
  fixture gate is enabled.

  ## Mock Response Format

  Raw mock responses are converted to structured `Message` structs following the same
  patterns as the real CLI output, ensuring compatibility across mock and live modes.
  """

  alias ClaudeAgentSDK.{Message, Mock, Options}

  @spec stream([String.t()], Options.t(), String.t() | nil) :: Enumerable.t()
  @doc """
  Streams mock messages instead of running the actual CLI.
  """
  def stream(args, %Options{} = _options, stdin_input \\ nil) do
    # Extract the prompt from args or use stdin_input
    prompt = stdin_input || extract_prompt(args)

    # Get mock response
    messages = Mock.get_response(prompt)

    # Convert to Message structs and create a stream
    messages
    |> Enum.map(&convert_to_message/1)
    |> Stream.concat([])
  end

  defp extract_prompt(args) do
    # The prompt is typically the last non-flag argument
    args
    |> Enum.reverse()
    |> Enum.find(fn arg ->
      not String.starts_with?(arg, "-") and arg not in ["continue", "resume"]
    end)
    |> Kernel.||("")
  end

  defp convert_to_message(raw_message) do
    # The message is already a map, parse it directly
    type = Message.__safe_type__(raw_message["type"])

    message = %Message{
      type: type,
      raw: raw_message
    }

    case type do
      :assistant ->
        %{
          message
          | data: %{message: raw_message["message"], session_id: raw_message["session_id"]}
        }

      :user ->
        %{
          message
          | data: %{message: raw_message["message"], session_id: raw_message["session_id"]}
        }

      :result ->
        subtype = Message.__safe_subtype__(:result, raw_message["subtype"])
        %{message | subtype: subtype, data: Map.drop(raw_message, ["type", "subtype"])}

      :system ->
        subtype = Message.__safe_subtype__(:system, raw_message["subtype"])
        %{message | subtype: subtype, data: Map.drop(raw_message, ["type", "subtype"])}

      _ ->
        %{message | data: raw_message}
    end
  end
end
