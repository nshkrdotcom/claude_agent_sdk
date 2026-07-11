defmodule ClaudeAgentSDK.InterruptReceipt do
  @moduledoc """
  Typed result of an interrupt control request (upstream
  `interrupt_receipt_v1`, CLI 2.1.205+).

  `still_queued` lists the UUIDs of queued async user messages that survive
  the interrupt: commands still in the queue, plus any batch already dequeued
  for the imminent turn but not yet reachable by the abort. These will still
  run unless cancelled first.

  Older CLIs acknowledge interrupts without a payload; the receipt then has
  an empty `still_queued`. Feature-detect via the `interrupt_receipt_v1`
  entry in the `system/init` frame's `capabilities`
  (see `ClaudeAgentSDK.Message.capability?/2`).
  """

  defstruct still_queued: [], raw: %{}

  @type t :: %__MODULE__{still_queued: [String.t()], raw: map()}

  @doc """
  Builds a receipt from the inner control-response payload.

  `still_queued` entries are filtered to strings (matching the TypeScript
  SDK); a missing or malformed payload yields an empty receipt.
  """
  @spec from_response(map() | nil) :: t()
  def from_response(%{} = payload) do
    still_queued =
      case payload["still_queued"] do
        list when is_list(list) -> Enum.filter(list, &is_binary/1)
        _ -> []
      end

    %__MODULE__{still_queued: still_queued, raw: payload}
  end

  def from_response(_payload), do: %__MODULE__{}
end
