# Exclude E2E tests by default (run with: mix test --include e2e)
ExUnit.start(exclude: [:e2e])

# Ensure dependent apps are started before configuring sandbox
{:ok, _} = Application.ensure_all_started(:balados_sync_core)
{:ok, _} = Application.ensure_all_started(:balados_sync_projections)
{:ok, _} = Application.ensure_all_started(:balados_sync_web)

Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncCore.SystemRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncProjections.ProjectionsRepo, :manual)

# Start Wallaby (ChromeDriver) for E2E tests
if System.get_env("INCLUDE_E2E") == "true" or "--include" in System.argv() do
  case Application.ensure_all_started(:wallaby) do
    {:ok, _} -> :ok
    {:error, reason} ->
      IO.warn("Could not start Wallaby: #{inspect(reason)}. E2E tests will be skipped.")
  end
end
