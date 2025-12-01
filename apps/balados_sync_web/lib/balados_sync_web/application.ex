defmodule BaladosSyncWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BaladosSyncCore.Application,
      BaladosSyncProjections.Application,
      BaladosSyncWeb.Telemetry,
      # Start a worker by calling: BaladosSyncWeb.Worker.start_link(arg)
      # {BaladosSyncWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      BaladosSyncWeb.Endpoint,
      # LRU avec max 500 entrées
      {Cachex, name: :rss_feed_cache, limit: 500}
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
