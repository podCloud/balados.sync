defmodule BaladosSyncProjections.Repo do
  use Ecto.Repo,
    otp_app: :balados_sync_projections,
    adapter: Ecto.Adapters.Postgres
end
