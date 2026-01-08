defmodule PhoenixChatWeb.ErrorHTML do
  @moduledoc """
  Error pages for HTML requests.
  """
  use PhoenixChatWeb, :html

  @doc """
  Renders error pages.
  """
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
