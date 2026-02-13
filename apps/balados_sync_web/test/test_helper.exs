# Exclude E2E tests by default (run with: mix test --include e2e)
ExUnit.start(exclude: [:e2e])

# Ensure dependent apps are started before configuring sandbox
{:ok, _} = Application.ensure_all_started(:balados_sync_core)
{:ok, _} = Application.ensure_all_started(:balados_sync_projections)
{:ok, _} = Application.ensure_all_started(:balados_sync_web)

Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncCore.SystemRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(BaladosSyncProjections.ProjectionsRepo, :manual)

# Start Wallaby and the Phoenix server only when E2E tests are included.
# The server is configured with `server: false` in test.exs by default,
# so we start it here dynamically to avoid running it for regular unit tests.
if System.get_env("INCLUDE_E2E") == "true" or "--include" in System.argv() do
  # Start the Phoenix endpoint with server enabled for E2E browser tests
  Application.put_env(
    :balados_sync_web,
    BaladosSyncWeb.Endpoint,
    Keyword.put(
      Application.get_env(:balados_sync_web, BaladosSyncWeb.Endpoint),
      :server,
      true
    )
  )

  # Restart the endpoint so it picks up server: true
  Supervisor.terminate_child(BaladosSyncWeb.Supervisor, BaladosSyncWeb.Endpoint)
  Supervisor.restart_child(BaladosSyncWeb.Supervisor, BaladosSyncWeb.Endpoint)

  case Application.ensure_all_started(:wallaby) do
    {:ok, _} ->
      :ok

    {:error, reason} ->
      IO.warn("Could not start Wallaby: #{inspect(reason)}. E2E tests will be skipped.")
  end
end
