defmodule BaladosSyncProjections.Application do
  use Application

  def start(_type, _args) do
    children = [
      BaladosSyncProjections.SystemRepo,
      BaladosSyncProjections.ProjectionsRepo,
      # Les projectors qui écoutent les events
      BaladosSyncProjections.Projectors.SubscriptionsProjector,
      BaladosSyncProjections.Projectors.PlayStatusesProjector,
      BaladosSyncProjections.Projectors.PublicEventsProjector,
      BaladosSyncProjections.Projectors.PopularityProjector
    ]

    opts = [strategy: :one_for_one, name: BaladosSyncProjections.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
