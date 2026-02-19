defmodule BaladosSyncProjections.Application do
  use Application

  def start(_type, _args) do
    children =
      [BaladosSyncProjections.ProjectionsRepo] ++
        projectors()

    opts = [strategy: :one_for_one, name: BaladosSyncProjections.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # In test environment, projectors are not started automatically
  # to avoid DBConnection.OwnershipError with Ecto Sandbox.
  # Tests that need projections should use fixtures or test projectors directly.
  defp projectors do
    if Application.get_env(:balados_sync_projections, :start_projectors, true) do
      [
        BaladosSyncProjections.Projectors.SubscriptionsProjector,
        BaladosSyncProjections.Projectors.PlayStatusesProjector,
        BaladosSyncProjections.Projectors.PublicEventsProjector,
        BaladosSyncProjections.Projectors.PopularityProjector,
        BaladosSyncProjections.Projectors.CollectionsProjector,
        BaladosSyncProjections.Projectors.LikeProjector
      ]
    else
      []
    end
  end
end
