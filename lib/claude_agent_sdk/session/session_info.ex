defmodule ClaudeAgentSDK.Session.SessionInfo do
  @moduledoc """
  Struct representing metadata for a Claude Code session.

  Returned by `ClaudeAgentSDK.Session.History.list_sessions/1`.
  """

  defstruct [
    :session_id,
    :summary,
    :cwd,
    :project_path,
    :first_prompt,
    :custom_title,
    :git_branch,
    :file_size,
    :last_modified
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          summary: String.t(),
          cwd: String.t() | nil,
          project_path: String.t() | nil,
          first_prompt: String.t() | nil,
          custom_title: String.t() | nil,
          git_branch: String.t() | nil,
          file_size: non_neg_integer(),
          last_modified: integer()
        }
end
