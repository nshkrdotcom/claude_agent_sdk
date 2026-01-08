defmodule ResearchAgent.Application do
  @moduledoc """
  OTP Application for the ResearchAgent.

  This application starts the necessary supervision tree for research coordination.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add any persistent processes here if needed
      # For now, coordinators are started per-session
    ]

    opts = [strategy: :one_for_one, name: ResearchAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
