defmodule ClaudeCodeSDK.Mock.Process do
  @moduledoc """
  Mock process implementation that returns predefined responses instead of spawning a CLI.
  """

  alias ClaudeCodeSDK.{Message, Mock, Options}

  @doc """
  Streams mock messages instead of running the actual CLI.
  """
  def stream(args, %Options{} = _options) do
    # Extract the prompt from args (it's usually the last argument)
    prompt = extract_prompt(args)

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
    type = String.to_atom(raw_message["type"])

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
        subtype = if raw_message["subtype"], do: String.to_atom(raw_message["subtype"])
        %{message | subtype: subtype, data: Map.drop(raw_message, ["type", "subtype"])}

      :system ->
        subtype = if raw_message["subtype"], do: String.to_atom(raw_message["subtype"])
        %{message | subtype: subtype, data: Map.drop(raw_message, ["type", "subtype"])}

      _ ->
        %{message | data: raw_message}
    end
  end
end
