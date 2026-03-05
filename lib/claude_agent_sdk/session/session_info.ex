defmodule ClaudeAgentSDK.Session.SessionInfo do
  @moduledoc """
  Struct representing metadata for a Claude Code session.

  Returned by `ClaudeAgentSDK.Session.History.list_sessions/1`.
  """

  defstruct [
    :session_id,
    :project_path,
    :first_prompt,
    :custom_title,
    :summary,
    :file_size,
    :last_modified
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          project_path: String.t() | nil,
          first_prompt: String.t() | nil,
          custom_title: String.t() | nil,
          summary: String.t() | nil,
          file_size: non_neg_integer(),
          last_modified: integer()
        }
end
