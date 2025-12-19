import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :balados_sync_core, BaladosSyncCore.SystemRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "balados_sync_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :balados_sync_projections, BaladosSyncProjections.ProjectionsRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "balados_sync_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Configure Dispatcher with In-Memory EventStore for test isolation
# This provides perfect isolation between tests - each test gets a fresh event store
# See: https://github.com/commanded/commanded/blob/master/guides/Testing.md
config :balados_sync_core, BaladosSyncCore.Dispatcher,
  event_store: [
    adapter: Commanded.EventStore.Adapters.InMemory,
    serializer: Commanded.Serialization.JsonSerializer
  ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :balados_sync_web, BaladosSyncWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3XB80yPu1D0OvXl1GesHIg8x2HCyDzrfMB9AlScl7PnNU+T8gbDpzAQgW7OyM14z",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails.
config :balados_sync_core, BaladosSyncCore.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Higher rate limits for tests to avoid flakiness
config :balados_sync_web, :rate_limiter,
  bucket_capacity: 100,
  refill_rate: 50
