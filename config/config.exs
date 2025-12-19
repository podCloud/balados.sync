# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Mix tasks and generators
config :balados_sync_core,
  ecto_repos: [BaladosSyncCore.SystemRepo]

config :balados_sync_projections,
  ecto_repos: [BaladosSyncProjections.ProjectionsRepo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :balados_sync_core, BaladosSyncCore.Mailer, adapter: Swoosh.Adapters.Local

config :balados_sync_web,
  ecto_repos: [BaladosSyncCore.SystemRepo, BaladosSyncProjections.ProjectionsRepo],
  generators: [context_app: :balados_sync_core]

# Configures the endpoint
config :balados_sync_web, BaladosSyncWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BaladosSyncWeb.ErrorHTML, json: BaladosSyncWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BaladosSyncCore.PubSub,
  live_view: [signing_salt: "/fOa6cym"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  balados_sync_web: [
    args:
      ~w(js/app.ts --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/balados_sync_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  balados_sync_web: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/balados_sync_web/assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :balados_sync_core, event_stores: [BaladosSyncCore.EventStore]

# Configure Dispatcher event store adapter (dev/prod uses PostgreSQL EventStore)
config :balados_sync_core, BaladosSyncCore.Dispatcher,
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: BaladosSyncCore.EventStore
  ]

config :balados_sync_core, BaladosSyncCore.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "balados_sync_dev",
  schema: "events",
  pool_size: 10,
  pool_overflow: 10

# Configure Hammer for rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000, cleanup_interval_ms: 5_000]}

# Configure Quantum scheduler for background jobs
config :balados_sync_jobs, BaladosSyncJobs.Scheduler,
  jobs: [
    # Run snapshot worker every 5 minutes
    snapshot_worker: [
      schedule: "*/5 * * * *",
      task: {BaladosSyncJobs.SnapshotWorker, :perform, []},
      timezone: "UTC"
    ],
    # Run play token cleanup daily at 2 AM UTC
    play_token_cleanup: [
      schedule: "0 2 * * *",
      task: {BaladosSyncJobs.PlayTokenCleanupWorker, :perform, []},
      timezone: "UTC"
    ]
  ]

# Configure PlayToken expiration
config :balados_sync_projections,
  play_token_expiration_days: 365

# Configure PlayToken cleanup retention
config :balados_sync_jobs,
  play_token_retention_days: 30

# Configure WebSocket connection rate limiting (token bucket)
# - bucket_capacity: max burst of messages
# - refill_rate: tokens per second
config :balados_sync_web, :rate_limiter,
  bucket_capacity: 20,
  refill_rate: 10

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
