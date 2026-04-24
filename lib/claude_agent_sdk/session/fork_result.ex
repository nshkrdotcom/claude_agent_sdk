defmodule ClaudeAgentSDK.Session.ForkResult do
  @moduledoc """
  Result returned by `ClaudeAgentSDK.Session.History.fork_session/2`.
  """

  @enforce_keys [:source_session_id, :session_id, :file_path]
  defstruct [:source_session_id, :session_id, :file_path]

  @type t :: %__MODULE__{
          source_session_id: String.t(),
          session_id: String.t(),
          file_path: String.t() | nil
        }
end
