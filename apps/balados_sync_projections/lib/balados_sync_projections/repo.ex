defmodule BaladosSyncProjections.ProjectionsRepo do
  use Ecto.Repo,
    otp_app: :balados_sync_projections,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    config = Keyword.put(config, :migration_default_prefix, "public")
    {:ok, config}
  end
end
