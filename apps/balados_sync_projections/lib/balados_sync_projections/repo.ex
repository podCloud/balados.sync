defmodule BaladosSyncProjections.Repo do
  use Ecto.Repo,
    otp_app: :balados_sync_projections,
    adapter: Ecto.Adapters.Postgres,
    prefix: "system"

  @impl true
  def default_options(_operation) do
    [prefix: "system"]
  end
end
