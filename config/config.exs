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
config :balados_sync_projections,
  ecto_repos: [BaladosSyncProjections.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :balados_sync_core, BaladosSyncCore.Mailer, adapter: Swoosh.Adapters.Local

config :balados_sync_web,
  ecto_repos: [BaladosSyncProjections.Repo],
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
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
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

config :balados_sync_core, BaladosSyncCore.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "balados_sync_dev",
  schema: "events",
  pool_size: 10,
  pool_overflow: 10

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
