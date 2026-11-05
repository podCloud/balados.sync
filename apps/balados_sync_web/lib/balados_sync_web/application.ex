defmodule BaladosSyncWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Cachex.Spec, only: [hook: 1]

  @impl true
  def start(_type, _args) do
    children = [
      BaladosSyncWeb.Telemetry,
      # Start a worker by calling: BaladosSyncWeb.Worker.start_link(arg)
      # {BaladosSyncWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      BaladosSyncWeb.Endpoint,
      # RSS feed cache: 5-minute expiration set per entry (RssCache.put/2),
      # bounded to 500 entries by Cachex 4's scheduled least-recently-written
      # eviction (the Cachex 3 `limit:` option no longer exists)
      {Cachex,
       name: :rss_feed_cache, hooks: [hook(module: Cachex.Limit.Scheduled, args: {500, [], []})]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BaladosSyncWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BaladosSyncWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
