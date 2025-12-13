defmodule ClaudeAgentSDK.AbortSignal do
  @moduledoc """
  Lightweight cancellation token shared with callbacks.

  Callbacks receive this via `:signal` in their context and can poll
  `cancelled?/1` to cooperatively stop work when a cancel or shutdown
  occurs.
  """

  @type t :: %__MODULE__{ref: :atomics.atomics_ref()}

  defstruct [:ref]

  @doc """
  Creates a new abort signal.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{ref: :atomics.new(1, [])}
  end

  @doc """
  Marks the signal as cancelled.
  """
  @spec cancel(t()) :: :ok
  def cancel(%__MODULE__{ref: ref}) do
    :atomics.put(ref, 1, 1)
    :ok
  end

  @doc """
  Returns true if the signal has been cancelled.
  """
  @spec cancelled?(t() | nil) :: boolean()
  def cancelled?(%__MODULE__{ref: ref}) do
    :atomics.get(ref, 1) == 1
  end

  def cancelled?(_), do: false
end
