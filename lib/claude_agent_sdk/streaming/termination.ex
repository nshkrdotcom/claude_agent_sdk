defmodule ClaudeAgentSDK.Streaming.Termination do
  @moduledoc """
  Shared termination logic for streaming sessions.

  Tracks stop_reason updates and determines when a message should complete.
  """

  @type stop_reason :: String.t() | nil

  @spec step(map(), stop_reason()) :: {stop_reason(), boolean()}
  def step(event, current_reason) do
    new_reason =
      case event do
        %{type: :message_start} ->
          nil

        %{type: :message_delta, stop_reason: reason} when not is_nil(reason) ->
          reason

        _ ->
          current_reason
      end

    complete? =
      case event do
        %{type: :message_stop} ->
          new_reason != "tool_use"

        _ ->
          false
      end

    {new_reason, complete?}
  end

  @spec reduce([map()], stop_reason()) :: {stop_reason(), boolean()}
  def reduce(events, current_reason) when is_list(events) do
    Enum.reduce(events, {current_reason, false}, fn event, {reason, complete?} ->
      {next_reason, event_complete?} = step(event, reason)
      {next_reason, complete? or event_complete?}
    end)
  end
end
