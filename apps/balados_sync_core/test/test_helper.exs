ExUnit.start()

# Ensure dependent apps are started before configuring sandbox
{:ok, _} = Application.ensure_all_started(:balados_sync_core)
{:ok, _} = Application.ensure_all_started(:balados_sync_projections)

Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncCore.SystemRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncProjections.ProjectionsRepo, :manual)
