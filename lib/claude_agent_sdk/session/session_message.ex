defmodule ClaudeAgentSDK.Session.SessionMessage do
  @moduledoc """
  Historical user or assistant message reconstructed from a Claude CLI transcript.

  Returned by `ClaudeAgentSDK.get_session_messages/2` and
  `ClaudeAgentSDK.Session.History.get_session_messages/2`.
  """

  @enforce_keys [:type, :uuid, :session_id, :message]
  defstruct [:type, :uuid, :session_id, :message, parent_tool_use_id: nil]

  @type message_type :: String.t()

  @type t :: %__MODULE__{
          type: message_type(),
          uuid: String.t(),
          session_id: String.t(),
          message: map() | nil,
          parent_tool_use_id: nil
        }
end
