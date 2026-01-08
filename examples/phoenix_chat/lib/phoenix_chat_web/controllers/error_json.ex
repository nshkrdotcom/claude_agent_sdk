defmodule PhoenixChatWeb.ErrorJSON do
  @moduledoc """
  Error pages for JSON requests.
  """

  @doc """
  Renders error responses as JSON.

  By default, Phoenix returns the status message from the template name. For example,
  "404.json" becomes %{errors: %{detail: "Not Found"}}.
  """
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
