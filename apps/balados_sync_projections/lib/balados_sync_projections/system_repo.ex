defmodule BaladosSyncProjections.SystemRepo do
  use Ecto.Repo,
    otp_app: :balados_sync_projections,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    config = Keyword.put(config, :migration_default_prefix, "system")
    {:ok, config}
  end

  @impl true
  def default_options(_operation) do
    [prefix: "system"]
  end
end
