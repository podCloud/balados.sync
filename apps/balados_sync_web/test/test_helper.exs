# Exclude E2E tests by default (run with: mix test --include e2e)
ExUnit.start(exclude: [:e2e])

# Ensure dependent apps are started before configuring sandbox
{:ok, _} = Application.ensure_all_started(:balados_sync_core)
{:ok, _} = Application.ensure_all_started(:balados_sync_projections)

Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncCore.SystemRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncProjections.ProjectionsRepo, :manual)

# Configure Wallaby for E2E tests only when they're included
# This prevents trying to start ChromeDriver for regular tests
if System.get_env("INCLUDE_E2E") == "true" or "--include" in System.argv() do
  # Start the endpoint with server: true for E2E tests
  Application.put_env(:balados_sync_web, BaladosSyncWeb.Endpoint,
    Keyword.merge(
      Application.get_env(:balados_sync_web, BaladosSyncWeb.Endpoint, []),
      server: true
    )
  )

  # Start Wallaby (ChromeDriver)
  case Application.ensure_all_started(:wallaby) do
    {:ok, _} -> :ok
    {:error, reason} ->
      IO.warn("Could not start Wallaby: #{inspect(reason)}. E2E tests will be skipped.")
  end
end
