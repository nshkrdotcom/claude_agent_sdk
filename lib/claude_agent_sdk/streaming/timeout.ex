defmodule ClaudeAgentSDK.Streaming.Timeout do
  @moduledoc false

  @enforce_keys [:timeout_ms, :deadline_ms]
  defstruct [:timeout_ms, :deadline_ms]

  @type t :: %__MODULE__{
          timeout_ms: pos_integer(),
          deadline_ms: integer()
        }

  @spec new(pos_integer()) :: t()
  def new(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    %__MODULE__{
      timeout_ms: timeout_ms,
      deadline_ms: System.monotonic_time(:millisecond) + timeout_ms
    }
  end

  @spec reset(t()) :: t()
  def reset(%__MODULE__{timeout_ms: timeout_ms}), do: new(timeout_ms)

  @spec remaining_ms(t()) :: non_neg_integer()
  def remaining_ms(%__MODULE__{deadline_ms: deadline_ms}) do
    remaining_ms = deadline_ms - System.monotonic_time(:millisecond)

    if remaining_ms > 0 do
      remaining_ms
    else
      0
    end
  end

  @spec timeout_event() :: %{type: :error, error: :timeout}
  def timeout_event, do: %{type: :error, error: :timeout}
end
